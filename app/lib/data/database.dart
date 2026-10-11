import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite storage (Figure 7 in the proposal, plus local accounts).
///
/// v1: guidance_rule, scan
/// v2: app_user, session, scan.user_id
/// v3: app_setting (e.g. the chosen language)
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const version = 3;

  /// Opens the database. [guidanceJson] is the content of
  /// `assets/guidance_rules.json`; it seeds `guidance_rule` on first run.
  /// Tests pass [factory], [path] (e.g. `inMemoryDatabasePath`) and may
  /// pin an older [targetVersion] to test upgrades.
  static Future<AppDatabase> open({
    required String guidanceJson,
    DatabaseFactory? factory,
    String? path,
    int targetVersion = version,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath =
        path ?? p.join(await f.getDatabasesPath(), 'harvestshelf.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: targetVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, v) async {
          await _createV1(db, guidanceJson);
          if (v >= 2) await _upgradeToV2(db);
          if (v >= 3) await _upgradeToV3(db);
        },
        onUpgrade: (db, from, to) async {
          if (from < 2 && to >= 2) await _upgradeToV2(db);
          if (from < 3 && to >= 3) await _upgradeToV3(db);
        },
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _createV1(Database db, String guidanceJson) async {
    await db.execute('''
      CREATE TABLE guidance_rule (
        id INTEGER PRIMARY KEY,
        crop TEXT NOT NULL,
        category TEXT NOT NULL,
        advice TEXT NOT NULL,
        UNIQUE (crop, category)
      )''');
    await db.execute('''
      CREATE TABLE scan (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        crop TEXT,
        category TEXT NOT NULL,
        confidence REAL NOT NULL,
        reason TEXT NOT NULL,
        inference_ms INTEGER,
        model_version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        image_path TEXT,
        rule_id INTEGER REFERENCES guidance_rule(id)
      )''');
    await db.execute('CREATE INDEX scan_created_at ON scan(created_at)');

    final rules = jsonDecode(guidanceJson) as List<dynamic>;
    final batch = db.batch();
    for (final r in rules.cast<Map<String, dynamic>>()) {
      batch.insert('guidance_rule', {
        'id': r['id'],
        'crop': r['crop'],
        'category': r['category'],
        'advice': r['advice'],
      });
    }
    await batch.commit(noResult: true);
  }

  /// Local accounts. Scans made before accounts existed keep user_id NULL;
  /// they appear only in the researcher's export.
  static Future<void> _upgradeToV2(Database db) async {
    await db.execute('''
      CREATE TABLE app_user (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE COLLATE NOCASE,
        display_name TEXT NOT NULL,
        role TEXT NOT NULL CHECK (role IN ('researcher', 'seller')),
        pin_hash TEXT NOT NULL,
        failed_attempts INTEGER NOT NULL DEFAULT 0,
        locked_until TEXT,
        created_at TEXT NOT NULL,
        last_login_at TEXT
      )''');
    await db.execute('''
      CREATE TABLE session (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        user_id INTEGER NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
        started_at TEXT NOT NULL
      )''');
    await db.execute(
      'ALTER TABLE scan ADD COLUMN user_id INTEGER REFERENCES app_user(id) ON DELETE CASCADE',
    );
    await db.execute('CREATE INDEX scan_user ON scan(user_id, created_at)');
  }

  /// Device-wide settings that apply before anyone signs in.
  static Future<void> _upgradeToV3(Database db) => db.execute(
    'CREATE TABLE app_setting (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  );

  Future<void> close() => db.close();
}
