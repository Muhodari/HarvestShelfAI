import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../data/database.dart';
import '../../models/user.dart';
import 'pin_hasher.dart';

enum AuthError {
  invalidName('Enter your name (2 to 40 characters).'),
  invalidUsername('Username: 3 to 20 letters, numbers, dots or underscores.'),
  usernameTaken('That username is already used on this phone.'),
  invalidPin('PIN must be 4 to 6 digits.'),
  weakPin('Choose a less obvious PIN (not 1234, 0000, ...).'),
  pinMismatch('The two PINs do not match.'),
  wrongCredentials('Username or PIN is not correct.'),
  lockedOut('Too many wrong PINs. Try again shortly.'),
  wrongCurrentPin('Your current PIN is not correct.'),
  notAllowed('Only a researcher can do this.'),
  cannotDeleteSelf('You cannot delete your own account here.'),
  lastResearcher('At least one researcher account must remain.'),
  notFound('Account not found.');

  const AuthError(this.message);

  final String message;
}

class AuthException implements Exception {
  const AuthException(this.error, {this.lockedUntil});

  final AuthError error;
  final DateTime? lockedUntil;

  String get message => error.message;

  @override
  String toString() => 'AuthException(${error.name})';
}

/// Local, offline accounts stored in SQLite.
///
/// The first account created becomes a researcher; later self-registered
/// accounts are sellers. After [maxAttempts] wrong PINs an account is locked
/// for [lockDuration].
class AuthService {
  AuthService(
    this._db, {
    this.hasher = const PinHasher(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final PinHasher hasher;
  final DateTime Function() _clock;

  static const maxAttempts = 5;
  static const lockDuration = Duration(seconds: 30);

  static final _usernameRe = RegExp(r'^[a-z0-9_.]{3,20}$');
  static final _pinRe = RegExp(r'^\d{4,6}$');

  // ---- validation (also used by the forms) --------------------------------

  static String normalizeUsername(String u) => u.trim().toLowerCase();

  static AuthError? validateName(String name) {
    final n = name.trim();
    return n.length < 2 || n.length > 40 ? AuthError.invalidName : null;
  }

  static AuthError? validateUsername(String username) =>
      _usernameRe.hasMatch(normalizeUsername(username))
      ? null
      : AuthError.invalidUsername;

  static AuthError? validatePin(String pin) {
    if (!_pinRe.hasMatch(pin)) return AuthError.invalidPin;
    final digits = pin.codeUnits.map((c) => c - 48).toList();
    final allSame = digits.every((d) => d == digits.first);
    var up = true, down = true;
    for (var i = 1; i < digits.length; i++) {
      if (digits[i] != (digits[i - 1] + 1) % 10) up = false;
      if (digits[i] != (digits[i - 1] + 9) % 10) down = false;
    }
    return allSame || up || down ? AuthError.weakPin : null;
  }

  // ---- accounts --------------------------------------------------------

  Future<bool> hasAnyUser() async {
    final r = await _db.db.rawQuery('SELECT COUNT(*) AS n FROM app_user');
    return (r.first['n'] as int) > 0;
  }

  /// Self-registration. The very first account becomes a researcher.
  Future<AppUser> register({
    required String displayName,
    required String username,
    required String pin,
    required String confirmPin,
  }) async {
    final role = await hasAnyUser() ? UserRole.seller : UserRole.researcher;
    return _create(displayName, username, pin, confirmPin, role);
  }

  /// A researcher adds an account for someone else (e.g. a seller without
  /// their own phone access during the study).
  Future<AppUser> createUser(
    AppUser actor, {
    required String displayName,
    required String username,
    required String pin,
    required UserRole role,
  }) async {
    _requireResearcher(actor);
    return _create(displayName, username, pin, pin, role);
  }

  Future<AppUser> _create(
    String displayName,
    String username,
    String pin,
    String confirmPin,
    UserRole role,
  ) async {
    final e =
        validateName(displayName) ??
        validateUsername(username) ??
        validatePin(pin);
    if (e != null) throw AuthException(e);
    if (pin != confirmPin) throw const AuthException(AuthError.pinMismatch);

    final uname = normalizeUsername(username);
    final exists = await _db.db.query(
      'app_user',
      columns: ['id'],
      where: 'username = ?',
      whereArgs: [uname],
    );
    if (exists.isNotEmpty) throw const AuthException(AuthError.usernameTaken);

    final id = await _db.db.insert('app_user', {
      'username': uname,
      'display_name': displayName.trim(),
      'role': role.id,
      'pin_hash': await hasher.hash(pin),
      'created_at': _clock().toIso8601String(),
    });
    return (await byId(id))!;
  }

  /// Checks the PIN and starts a session. Wrong PINs count towards a
  /// temporary lockout; an unknown username gives the same error so it does
  /// not reveal which usernames exist.
  Future<AppUser> login(String username, String pin) async {
    final rows = await _db.db.query(
      'app_user',
      where: 'username = ?',
      whereArgs: [normalizeUsername(username)],
    );
    if (rows.isEmpty) {
      // Same work as a real check, so timing does not reveal the username.
      await hasher.verify(pin, _dummyHash);
      throw const AuthException(AuthError.wrongCredentials);
    }
    final row = rows.first;
    final id = row['id'] as int;
    final now = _clock();

    final lockedUntil = row['locked_until'] == null
        ? null
        : DateTime.parse(row['locked_until'] as String);
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      throw AuthException(AuthError.lockedOut, lockedUntil: lockedUntil);
    }

    if (!await hasher.verify(pin, row['pin_hash'] as String)) {
      final attempts = (row['failed_attempts'] as int) + 1;
      final lock = attempts >= maxAttempts ? now.add(lockDuration) : null;
      await _db.db.update(
        'app_user',
        {
          'failed_attempts': lock == null ? attempts : 0,
          'locked_until': lock?.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (lock != null) {
        throw AuthException(AuthError.lockedOut, lockedUntil: lock);
      }
      throw const AuthException(AuthError.wrongCredentials);
    }

    await _db.db.transaction((txn) async {
      await txn.update(
        'app_user',
        {
          'failed_attempts': 0,
          'locked_until': null,
          'last_login_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert('session', {
        'id': 1,
        'user_id': id,
        'started_at': now.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    return (await byId(id))!;
  }

  Future<void> logout() => _db.db.delete('session');

  /// The signed-in user, or null. Survives app restarts.
  Future<AppUser?> currentUser() async {
    final rows = await _db.db.rawQuery(
      '''
      SELECT u.* FROM session s JOIN app_user u ON u.id = s.user_id WHERE s.id = 1''',
    );
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  Future<AppUser?> byId(int id) async {
    final rows = await _db.db.query(
      'app_user',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  Future<void> changePin(
    AppUser user, {
    required String currentPin,
    required String newPin,
    required String confirmPin,
  }) async {
    final row = (await _db.db.query(
      'app_user',
      columns: ['pin_hash'],
      where: 'id = ?',
      whereArgs: [user.id],
    )).first;
    if (!await hasher.verify(currentPin, row['pin_hash'] as String)) {
      throw const AuthException(AuthError.wrongCurrentPin);
    }
    final e = validatePin(newPin);
    if (e != null) throw AuthException(e);
    if (newPin != confirmPin) throw const AuthException(AuthError.pinMismatch);
    await _db.db.update(
      'app_user',
      {'pin_hash': await hasher.hash(newPin)},
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<void> updateName(AppUser user, String displayName) async {
    final e = validateName(displayName);
    if (e != null) throw AuthException(e);
    await _db.db.update(
      'app_user',
      {'display_name': displayName.trim()},
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  // ---- researcher tools --------------------------------------------------

  Future<List<AppUser>> listUsers(AppUser actor) async {
    _requireResearcher(actor);
    final rows = await _db.db.query(
      'app_user',
      orderBy: 'display_name COLLATE NOCASE',
    );
    return rows.map(AppUser.fromMap).toList();
  }

  Future<int> scanCount(int userId) async {
    final r = await _db.db.rawQuery(
      'SELECT COUNT(*) AS n FROM scan WHERE user_id = ?',
      [userId],
    );
    return r.first['n'] as int;
  }

  Future<void> setRole(AppUser actor, int userId, UserRole role) async {
    _requireResearcher(actor);
    if (role == UserRole.seller) await _requireAnotherResearcher(userId);
    final n = await _db.db.update(
      'app_user',
      {'role': role.id},
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (n == 0) throw const AuthException(AuthError.notFound);
  }

  Future<void> resetPin(AppUser actor, int userId, String newPin) async {
    _requireResearcher(actor);
    final e = validatePin(newPin);
    if (e != null) throw AuthException(e);
    final n = await _db.db.update(
      'app_user',
      {
        'pin_hash': await hasher.hash(newPin),
        'failed_attempts': 0,
        'locked_until': null,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (n == 0) throw const AuthException(AuthError.notFound);
  }

  /// Deletes the account and, through ON DELETE CASCADE, its scans.
  /// Returns the deleted scans' thumbnail paths so the caller can remove
  /// the files.
  Future<List<String>> deleteUser(AppUser actor, int userId) async {
    _requireResearcher(actor);
    if (userId == actor.id) {
      throw const AuthException(AuthError.cannotDeleteSelf);
    }
    await _requireAnotherResearcher(userId);
    final paths = (await _db.db.query(
      'scan',
      columns: ['image_path'],
      where: 'user_id = ? AND image_path IS NOT NULL',
      whereArgs: [userId],
    )).map((r) => r['image_path'] as String).toList();
    final n = await _db.db.delete(
      'app_user',
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (n == 0) throw const AuthException(AuthError.notFound);
    return paths;
  }

  void _requireResearcher(AppUser actor) {
    if (!actor.isResearcher) throw const AuthException(AuthError.notAllowed);
  }

  /// Throws if [userId] is the only researcher left.
  Future<void> _requireAnotherResearcher(int userId) async {
    final r = await _db.db.rawQuery(
      "SELECT COUNT(*) AS n FROM app_user WHERE role = 'researcher' AND id != ?",
      [userId],
    );
    final target = await byId(userId);
    if (target != null && target.isResearcher && (r.first['n'] as int) == 0) {
      throw const AuthException(AuthError.lastResearcher);
    }
  }

  static const _dummyHash =
      r'pbkdf2_sha256$60000$AAAAAAAAAAAAAAAAAAAAAA==$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
}
