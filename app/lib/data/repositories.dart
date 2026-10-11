import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/category.dart';
import '../models/scan.dart';
import 'database.dart';

/// Saved scans (FR5). Each seller sees only their own.
class ScanRepository {
  ScanRepository(this._db);

  final AppDatabase _db;

  Future<int> insert(Scan scan) => _db.db.insert('scan', scan.toMap());

  /// The user's scans, newest first.
  Future<List<Scan>> forUser(int userId) async {
    final rows = await _db.db.query(
      'scan',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(Scan.fromMap).toList();
  }

  /// Every scan on the phone, for the researcher's anonymous export (FR6).
  Future<List<Scan>> allForExport() async {
    final rows = await _db.db.query(
      'scan',
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(Scan.fromMap).toList();
  }

  /// Counts per category for one user, optionally only since [since].
  Future<Map<TriageCategory, int>> countsByCategory(
    int userId, {
    DateTime? since,
  }) async {
    final rows = await _db.db.rawQuery(
      'SELECT category, COUNT(*) AS n FROM scan WHERE user_id = ? AND created_at >= ? '
      'GROUP BY category',
      [userId, (since ?? DateTime(1970)).toIso8601String()],
    );
    return {
      for (final r in rows)
        TriageCategory.fromId(r['category'] as String): r['n'] as int,
    };
  }

  /// Deletes the user's scans; returns their thumbnail paths.
  Future<List<String>> deleteForUser(int userId) async {
    final paths = (await _db.db.query(
      'scan',
      columns: ['image_path'],
      where: 'user_id = ? AND image_path IS NOT NULL',
      whereArgs: [userId],
    )).map((r) => r['image_path'] as String).toList();
    await _db.db.delete('scan', where: 'user_id = ?', whereArgs: [userId]);
    return paths;
  }
}

/// Advice text per crop and category.
class GuidanceRepository {
  GuidanceRepository(this._db);

  final AppDatabase _db;

  /// Crop-specific rule, falling back to the `any` rule for the category.
  Future<GuidanceRule?> ruleFor(String? crop, TriageCategory category) async {
    final rows = await _db.db.query(
      'guidance_rule',
      where: "category = ? AND crop IN (?, 'any')",
      whereArgs: [category.id, crop ?? 'any'],
      // Exact crop match sorts before 'any'.
      orderBy: "CASE WHEN crop = 'any' THEN 1 ELSE 0 END",
      limit: 1,
    );
    return rows.isEmpty ? null : GuidanceRule.fromMap(rows.first);
  }

  Future<GuidanceRule?> byId(int id) async {
    final rows = await _db.db.query(
      'guidance_rule',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : GuidanceRule.fromMap(rows.first);
  }
}

/// Small key-value settings stored on the phone.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<String?> get(String key) async {
    final rows = await _db.db.query(
      'app_setting',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> set(String key, String value) => _db.db.insert('app_setting', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
