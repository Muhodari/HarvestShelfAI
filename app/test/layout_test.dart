import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harvestshelf/app_services.dart';
import 'package:harvestshelf/data/database.dart';
import 'package:harvestshelf/main.dart';
import 'package:harvestshelf/models/category.dart';
import 'package:harvestshelf/models/scan.dart';
import 'package:harvestshelf/models/triage_result.dart';
import 'package:harvestshelf/screens/result_screen.dart';
import 'package:harvestshelf/services/triage_service.dart';
import 'package:harvestshelf/core/theme.dart';

import 'helpers.dart';

/// Every screen must lay out without overflow on a small phone, in
/// landscape, and with large system text (accessibility settings).
/// Overflow errors fail the test automatically.
void main() {
  const configs = <(String, Size, double)>[
    ('small phone 360x640, text 1.0', Size(360, 640), 1.0),
    ('phone, large text 1.6', Size(412, 915), 1.6),
    ('phone, largest text 2.0', Size(412, 915), 2.0),
    ('landscape 915x412, text 1.3', Size(915, 412), 1.3),
  ];

  late AppDatabase db;
  late AppServices services;

  setUp(() async {
    db = await openTestDb();
    services = await testServices(db);
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    await tester.scrollUntilVisible(
      find.byKey(Key(key)),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(find.byKey(Key(key)), text);
  }

  void setView(WidgetTester tester, Size size, double textScale) {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  for (final (name, size, scale) in configs) {
    testWidgets('all screens fit: $name', (tester) async {
      setView(tester, size, scale);
      await tester.pumpWidget(HarvestShelfApp(init: () async => services));
      await settle(tester);

      // Welcome -> register
      await tester.tap(find.text('Set up this phone'));
      await settle(tester);
      await enter(tester, 'reg_name', 'Aline Uwase');
      await enter(tester, 'reg_username', 'aline.u');
      await enter(tester, 'reg_pin', '2580');
      await enter(tester, 'reg_confirm', '2580');
      await tester.scrollUntilVisible(
        find.byKey(const Key('reg_submit')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reg_submit')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();

      // Data for the lists
      final me = services.session.user!;
      await tester.runAsync(() async {
        for (final c in TriageCategory.values) {
          await services.scans.insert(
            Scan(
              crop: c == TriageCategory.uncertain ? null : 'banana',
              category: c,
              confidence: 0.91,
              reason: c == TriageCategory.uncertain
                  ? DecisionReason.lowConfidence
                  : DecisionReason.model,
              inferenceMs: 120,
              modelVersion: 'v',
              createdAt: DateTime.now(),
              userId: me.id,
            ),
          );
        }
      });
      services.triage.changes.value++;
      await settle(tester);

      await tester.tap(find.byTooltip('History'));
      await settle(tester);
      await tester.tap(find.byTooltip('Profile'));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Manage users'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Manage users'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage users'));
      await settle(tester);
      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Change PIN'),
        -100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Change PIN'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change PIN'));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('result screen fits: $name', (tester) async {
      setView(tester, size, scale);
      for (final c in TriageCategory.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: ResultScreen(
              outcome: TriageOutcome(
                result: TriageResult(
                  category: c,
                  crop: 'tomato',
                  confidence: 0.83,
                  reason: c == TriageCategory.uncertain
                      ? DecisionReason.blurry
                      : DecisionReason.model,
                  inferenceMs: 120,
                ),
                scan: Scan(
                  id: 1,
                  crop: 'tomato',
                  category: c,
                  confidence: 0.83,
                  reason: DecisionReason.model,
                  inferenceMs: 120,
                  modelVersion: 'v',
                  createdAt: DateTime(2026, 11, 5),
                ),
                rule: GuidanceRule(
                  id: 1,
                  crop: 'tomato',
                  category: c,
                  advice:
                      'Remove from normal sale. Keep it away from fresh tomatoes so it does not affect them.',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final e = tester.takeException();
        expect(e, isNull, reason: c.id);
      }
    });
  }

  testWidgets('screen-reader labels exist for key controls', (tester) async {
    final handle = tester.ensureSemantics();
    setView(tester, const Size(412, 915), 1.0);
    await tester.pumpWidget(HarvestShelfApp(init: () async => services));
    await settle(tester);
    await tester.tap(find.text('Set up this phone'));
    await settle(tester);
    final missing = <String>[];
    for (final label in [
      'Your name',
      'Username',
      'PIN (4 to 6 digits)',
      'Repeat PIN',
      'Show PIN',
      'Create account',
      'Back',
    ]) {
      if (find
          .bySemanticsLabel(RegExp(RegExp.escape(label)))
          .evaluate()
          .isEmpty) {
        missing.add(label);
      }
    }
    expect(missing, isEmpty, reason: 'controls without a screen-reader label');
    handle.dispose();
  });
}
