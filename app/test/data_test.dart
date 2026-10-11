import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harvestshelf/data/database.dart';
import 'package:harvestshelf/data/repositories.dart';
import 'package:harvestshelf/models/category.dart';
import 'package:harvestshelf/models/scan.dart';
import 'package:harvestshelf/services/export_service.dart';
import 'package:harvestshelf/services/image_quality_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late ScanRepository scans;
  late GuidanceRepository guidance;

  setUp(() async {
    db = await openTestDb();
    scans = ScanRepository(db);
    guidance = GuidanceRepository(db);
  });

  tearDown(() => db.close());

  Future<int> user(String name) => db.db.insert('app_user', {
    'username': name,
    'display_name': name,
    'role': 'seller',
    'pin_hash': 'x',
    'created_at': DateTime(2026).toIso8601String(),
  });

  Scan scan(
    TriageCategory c,
    DateTime t, {
    String? crop = 'tomato',
    int? userId,
  }) => Scan(
    crop: crop,
    category: c,
    confidence: 0.9,
    reason: DecisionReason.model,
    inferenceMs: 120,
    modelVersion: 'v1',
    createdAt: t,
    userId: userId,
  );

  group('guidance', () {
    test('every crop and category has advice', () async {
      for (final crop in ['tomato', 'banana']) {
        for (final c in TriageCategory.values) {
          expect(
            await guidance.ruleFor(crop, c),
            isNotNull,
            reason: '$crop/${c.id}',
          );
        }
      }
    });

    test('crop-specific rule wins over any', () async {
      expect(
        (await guidance.ruleFor('banana', TriageCategory.spoilageRisk))!.crop,
        'banana',
      );
    });

    test('unknown crop falls back to any', () async {
      expect(
        (await guidance.ruleFor(null, TriageCategory.uncertain))!.crop,
        'any',
      );
    });
  });

  group('scans', () {
    test('each user sees only their own scans, newest first', () async {
      final a = await user('aline');
      final b = await user('bosco');
      await scans.insert(
        scan(TriageCategory.fresh, DateTime(2026, 11, 1), userId: a),
      );
      await scans.insert(
        scan(TriageCategory.spoilageRisk, DateTime(2026, 11, 3), userId: a),
      );
      await scans.insert(
        scan(TriageCategory.fresh, DateTime(2026, 11, 2), userId: b),
      );

      expect((await scans.forUser(a)).map((s) => s.createdAt.day), [3, 1]);
      expect((await scans.forUser(b)).single.createdAt.day, 2);
      expect(await scans.countsByCategory(a), {
        TriageCategory.fresh: 1,
        TriageCategory.spoilageRisk: 1,
      });
      expect(await scans.countsByCategory(a, since: DateTime(2026, 11, 2)), {
        TriageCategory.spoilageRisk: 1,
      });
      expect(await scans.allForExport(), hasLength(3));
    });

    test('deleteForUser leaves other users alone', () async {
      final a = await user('aline');
      final b = await user('bosco');
      await scans.insert(
        scan(TriageCategory.fresh, DateTime(2026, 11, 1), userId: a),
      );
      await scans.insert(
        scan(TriageCategory.fresh, DateTime(2026, 11, 1), userId: b),
      );
      await scans.deleteForUser(a);
      expect(await scans.forUser(a), isEmpty);
      expect(await scans.forUser(b), hasLength(1));
    });

    test('CSV export: header, user id, no names, oldest first', () async {
      final a = await user('aline');
      await scans.insert(
        scan(TriageCategory.fresh, DateTime(2026, 11, 1), userId: a),
      );
      await scans.insert(
        scan(
          TriageCategory.uncertain,
          DateTime(2026, 11, 2),
          crop: null,
          userId: a,
        ),
      );
      final csv = scansToCsv(await scans.allForExport());
      final lines = csv.trim().split('\n');
      expect(lines.first, csvHeader.join(','));
      expect(lines, hasLength(3));
      expect(lines[1], startsWith('1,$a,'));
      expect(lines[2], contains(',,uncertain,'));
      expect(csv, isNot(contains('aline')));
    });
  });

  group('database upgrade v1 -> v2', () {
    test('keeps existing scans and adds accounts', () async {
      sqfliteFfiInit();
      final path =
          '${Directory.systemTemp.path}/hs_upgrade_${DateTime.now().microsecondsSinceEpoch}.db';
      final v1 = await AppDatabase.open(
        guidanceJson: guidanceJson,
        factory: databaseFactoryFfi,
        path: path,
        targetVersion: 1,
      );
      await v1.db.insert('scan', {
        'crop': 'tomato',
        'category': 'fresh',
        'confidence': 0.9,
        'reason': 'model',
        'model_version': 'old',
        'created_at': DateTime(2026, 10, 1).toIso8601String(),
      });
      await v1.close();

      final v2 = await AppDatabase.open(
        guidanceJson: guidanceJson,
        factory: databaseFactoryFfi,
        path: path,
      );
      final rows = await v2.db.query('scan');
      expect(rows.single['user_id'], isNull);
      expect(rows.single['model_version'], 'old');
      expect(await v2.db.query('app_user'), isEmpty);
      expect(await ScanRepository(v2).allForExport(), hasLength(1));
      await v2.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });
  });

  group('database upgrade v2 -> v3', () {
    test('adds settings and keeps accounts', () async {
      sqfliteFfiInit();
      final path =
          '${Directory.systemTemp.path}/hs_v3_${DateTime.now().microsecondsSinceEpoch}.db';
      final v2 = await AppDatabase.open(
        guidanceJson: guidanceJson,
        factory: databaseFactoryFfi,
        path: path,
        targetVersion: 2,
      );
      await v2.db.insert('app_user', {
        'username': 'aline',
        'display_name': 'Aline',
        'role': 'seller',
        'pin_hash': 'x',
        'created_at': DateTime(2026).toIso8601String(),
      });
      await v2.close();
      final v3 = await AppDatabase.open(
        guidanceJson: guidanceJson,
        factory: databaseFactoryFfi,
        path: path,
      );
      expect(await v3.db.query('app_user'), hasLength(1));
      final settings = SettingsRepository(v3);
      expect(await settings.get('language'), isNull);
      await settings.set('language', 'rw');
      await settings.set('language', 'en');
      expect(await settings.get('language'), 'en');
      await v3.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });
  });

  group('triage service', () {
    test('good photo is classified, mapped and saved for the user', () async {
      final services = await testServices(
        db,
        clock: () => DateTime(2026, 11, 5, 9, 30),
      );
      final a = await user('aline');
      var notified = 0;
      services.triage.changes.addListener(() => notified++);
      final out = await services.triage.triage(Uint8List(0), userId: a);
      expect(out.result.category, TriageCategory.sellSoon);
      expect(out.result.inferenceMs, 42);
      expect(out.rule!.advice, contains('front of the stall'));
      final saved = (await scans.forUser(a)).single;
      expect(saved.id, out.scan.id);
      expect(saved.userId, a);
      expect(saved.ruleId, out.rule!.id);
      expect(notified, 1);
    });

    test('dark photo is rejected without running the model', () async {
      final services = await testServices(
        db,
        quality: const QualityReport(brightness: 10, sharpness: 300),
        probs: List.filled(9, 1 / 9),
      );
      final a = await user('aline');
      final out = await services.triage.triage(Uint8List(0), userId: a);
      expect(out.result.category, TriageCategory.uncertain);
      expect(out.result.reason, DecisionReason.tooDark);
      expect(out.scan.inferenceMs, isNull);
      expect(out.rule!.crop, 'any');
    });
  });
}
