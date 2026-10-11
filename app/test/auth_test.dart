import 'package:flutter_test/flutter_test.dart';
import 'package:harvestshelf/data/database.dart';
import 'package:harvestshelf/models/user.dart';
import 'package:harvestshelf/services/auth/auth_service.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late AuthService auth;
  late DateTime now;

  setUp(() async {
    db = await openTestDb();
    now = DateTime(2026, 11, 5, 9);
    auth = AuthService(db, hasher: fastHasher, clock: () => now);
  });

  tearDown(() => db.close());

  Future<AppUser> reg(String name, String username, [String pin = '2580']) =>
      auth.register(
        displayName: name,
        username: username,
        pin: pin,
        confirmPin: pin,
      );

  Matcher throwsAuth(AuthError e) =>
      throwsA(isA<AuthException>().having((x) => x.error, 'error', e));

  group('validation', () {
    test('names', () {
      expect(AuthService.validateName(' A '), AuthError.invalidName);
      expect(AuthService.validateName('Aline Mukamana'), isNull);
    });

    test('usernames', () {
      expect(AuthService.validateUsername('al'), AuthError.invalidUsername);
      expect(
        AuthService.validateUsername('aline m'),
        AuthError.invalidUsername,
      );
      expect(
        AuthService.validateUsername('Aline.M_2'),
        isNull,
      ); // normalised to lower case
    });

    test('PINs: 4-6 digits, not trivially guessable', () {
      for (final bad in ['123', '1234567', '12a4']) {
        expect(AuthService.validatePin(bad), AuthError.invalidPin, reason: bad);
      }
      for (final weak in [
        '0000',
        '1111',
        '1234',
        '4321',
        '123456',
        '7890',
        '0987',
      ]) {
        expect(AuthService.validatePin(weak), AuthError.weakPin, reason: weak);
      }
      for (final ok in ['2580', '1357', '904417']) {
        expect(AuthService.validatePin(ok), isNull, reason: ok);
      }
    });
  });

  group('register', () {
    test('first account is a researcher, later ones are sellers', () async {
      expect(await auth.hasAnyUser(), isFalse);
      expect((await reg('Sage', 'sage')).role, UserRole.researcher);
      expect((await reg('Aline', 'aline')).role, UserRole.seller);
    });

    test('rejects duplicate usernames regardless of case', () async {
      await reg('Aline', 'aline');
      expect(() => reg('Other', 'ALINE'), throwsAuth(AuthError.usernameTaken));
    });

    test('rejects mismatched PINs and stores only a hash', () async {
      expect(
        () => auth.register(
          displayName: 'Aline',
          username: 'aline',
          pin: '2580',
          confirmPin: '2581',
        ),
        throwsAuth(AuthError.pinMismatch),
      );
      await reg('Aline', 'aline');
      final row = (await db.db.query('app_user')).single;
      expect(row['pin_hash'] as String, startsWith(r'pbkdf2_sha256$'));
      expect(row['pin_hash'] as String, isNot(contains('2580')));
    });
  });

  group('login / logout', () {
    test('correct PIN starts a session that survives a restart', () async {
      await reg('Aline', 'aline');
      final u = await auth.login(
        'Aline',
        '2580',
      ); // username is case-insensitive
      expect(u.lastLoginAt, now);
      final restarted = AuthService(db, hasher: fastHasher);
      expect((await restarted.currentUser())!.username, 'aline');
      await restarted.logout();
      expect(await auth.currentUser(), isNull);
    });

    test('wrong PIN and unknown user give the same error', () async {
      await reg('Aline', 'aline');
      expect(
        () => auth.login('aline', '9999'),
        throwsAuth(AuthError.wrongCredentials),
      );
      expect(
        () => auth.login('nobody', '2580'),
        throwsAuth(AuthError.wrongCredentials),
      );
    });

    test(
      'locks after 5 wrong PINs, unlocks after 30 s, success resets the count',
      () async {
        await reg('Aline', 'aline');
        for (var i = 0; i < 4; i++) {
          await expectLater(
            auth.login('aline', '9999'),
            throwsAuth(AuthError.wrongCredentials),
          );
        }
        await expectLater(
          auth.login('aline', '9999'),
          throwsAuth(AuthError.lockedOut),
        );
        // Even the right PIN is refused while locked.
        await expectLater(
          auth.login('aline', '2580'),
          throwsAuth(AuthError.lockedOut),
        );
        now = now.add(const Duration(seconds: 31));
        await auth.login('aline', '2580');
        final row = (await db.db.query('app_user')).single;
        expect(row['failed_attempts'], 0);
        expect(row['locked_until'], isNull);
      },
    );

    test('change PIN needs the current PIN', () async {
      final u = await reg('Aline', 'aline');
      expect(
        () => auth.changePin(
          u,
          currentPin: '1111',
          newPin: '1357',
          confirmPin: '1357',
        ),
        throwsAuth(AuthError.wrongCurrentPin),
      );
      await auth.changePin(
        u,
        currentPin: '2580',
        newPin: '1357',
        confirmPin: '1357',
      );
      await auth.login('aline', '1357');
      expect(
        () => auth.login('aline', '2580'),
        throwsAuth(AuthError.wrongCredentials),
      );
    });
  });

  group('researcher tools', () {
    late AppUser boss;
    late AppUser seller;

    setUp(() async {
      boss = await reg('Sage', 'sage');
      seller = await reg('Aline', 'aline');
    });

    test('sellers cannot manage users', () {
      expect(() => auth.listUsers(seller), throwsAuth(AuthError.notAllowed));
      expect(
        () => auth.deleteUser(seller, boss.id),
        throwsAuth(AuthError.notAllowed),
      );
    });

    test('create, list, change role, reset PIN', () async {
      final bosco = await auth.createUser(
        boss,
        displayName: 'Bosco',
        username: 'bosco',
        pin: '4826',
        role: UserRole.seller,
      );
      expect((await auth.listUsers(boss)).map((u) => u.username), [
        'aline',
        'bosco',
        'sage',
      ]);
      await auth.setRole(boss, bosco.id, UserRole.researcher);
      expect((await auth.byId(bosco.id))!.role, UserRole.researcher);
      await auth.resetPin(boss, seller.id, '7531');
      await auth.login('aline', '7531');
    });

    test('reset PIN clears a lockout', () async {
      for (var i = 0; i < 5; i++) {
        await expectLater(
          auth.login('aline', '9999'),
          throwsA(isA<AuthException>()),
        );
      }
      await auth.resetPin(boss, seller.id, '7531');
      await auth.login('aline', '7531');
    });

    test('the last researcher cannot be demoted or deleted', () async {
      expect(
        () => auth.setRole(boss, boss.id, UserRole.seller),
        throwsAuth(AuthError.lastResearcher),
      );
      expect(
        () => auth.deleteUser(boss, boss.id),
        throwsAuth(AuthError.cannotDeleteSelf),
      );
      await auth.setRole(boss, seller.id, UserRole.researcher);
      await auth.setRole(
        boss,
        boss.id,
        UserRole.seller,
      ); // fine now: another researcher exists
    });

    test(
      'deleting a user removes their scans and returns thumbnail paths',
      () async {
        await db.db.insert('scan', {
          'crop': 'tomato',
          'category': 'fresh',
          'confidence': 0.9,
          'reason': 'model',
          'model_version': 'v',
          'created_at': now.toIso8601String(),
          'image_path': '/tmp/x.jpg',
          'user_id': seller.id,
        });
        expect(await auth.scanCount(seller.id), 1);
        expect(await auth.deleteUser(boss, seller.id), ['/tmp/x.jpg']);
        expect(await auth.byId(seller.id), isNull);
        expect(await db.db.query('scan'), isEmpty);
      },
    );

    test('deleting the signed-in user ends their session', () async {
      await auth.login('aline', '2580');
      await auth.deleteUser(boss, seller.id);
      expect(await auth.currentUser(), isNull);
    });
  });
}
