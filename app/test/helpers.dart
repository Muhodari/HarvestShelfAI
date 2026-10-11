import 'dart:io';
import 'dart:typed_data';

import 'package:harvestshelf/app_services.dart';
import 'package:harvestshelf/data/database.dart';
import 'package:harvestshelf/data/repositories.dart';
import 'package:harvestshelf/models/model_meta.dart';
import 'package:harvestshelf/models/triage_result.dart';
import 'package:harvestshelf/services/auth/auth_service.dart';
import 'package:harvestshelf/services/auth/pin_hasher.dart';
import 'package:harvestshelf/services/auth/session.dart';
import 'package:harvestshelf/services/image_quality_service.dart';
import 'package:harvestshelf/services/preprocessing_service.dart';
import 'package:harvestshelf/services/triage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Few iterations so tests stay fast; production uses PinHasher.defaultIterations.
const fastHasher = PinHasher(iterations: 10);

final guidanceJson = File('assets/guidance_rules.json').readAsStringSync();

Future<AppDatabase> openTestDb({int version = AppDatabase.version}) {
  sqfliteFfiInit();
  return AppDatabase.open(
    guidanceJson: guidanceJson,
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
    targetVersion: version,
  );
}

ModelMeta testMeta({bool isDemo = false, String? notice}) => ModelMeta.fromJson(
  {
    'model_version': 'v-test',
    'architecture': 'test',
    'input_size': 4,
    'input_range': '0_255',
    't_conf': 0.55,
    't_spoil': 0.35,
    'is_demo': isDemo,
    'notice': notice,
    'quality': {
      'min_brightness': 40,
      'max_brightness': 235,
      'min_sharpness': 80,
    },
  },
  [
    for (final (i, id) in [
      'tomato_fresh',
      'tomato_sell_soon',
      'tomato_discount_today',
      'tomato_spoilage_risk',
      'banana_fresh',
      'banana_sell_soon',
      'banana_discount_today',
      'banana_spoilage_risk',
    ].indexed)
      {
        'index': i,
        'id': id,
        'crop': id.split('_').first,
        'category': id.substring(id.indexOf('_') + 1),
      },
    {'index': 8, 'id': 'unusable', 'crop': 'none', 'category': 'uncertain'},
  ],
);

/// Full service graph on an in-memory database with a fake classifier that
/// always returns [probs].
Future<AppServices> testServices(
  AppDatabase db, {
  List<double> probs = const [0.05, 0.85, 0.05, 0.05, 0, 0, 0, 0, 0],
  QualityReport quality = const QualityReport(brightness: 120, sharpness: 300),
  DateTime Function()? clock,
}) async {
  final meta = testMeta();
  final scans = ScanRepository(db);
  final guidance = GuidanceRepository(db);
  final auth = AuthService(db, hasher: fastHasher, clock: clock);
  final session = SessionController(auth);
  await session.restore();
  final language = await AppServices.loadLanguage(SettingsRepository(db));
  return AppServices(
    meta: meta,
    scans: scans,
    guidance: guidance,
    auth: auth,
    session: session,
    language: language,
    triage: TriageService(
      meta: meta,
      scans: scans,
      guidance: guidance,
      clock: clock,
      prepare: (_, size) async => PreparedImage(
        input: const [],
        quality: quality,
        thumbnailJpg: Uint8List(0),
      ),
      classify: (_) async => Prediction(probabilities: probs, inferenceMs: 42),
    ),
  );
}
