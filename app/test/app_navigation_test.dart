import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harvestshelf/app_services.dart';
import 'package:harvestshelf/data/database.dart';
import 'package:harvestshelf/data/repositories.dart';
import 'package:harvestshelf/main.dart';
import 'package:harvestshelf/models/category.dart';
import 'package:harvestshelf/models/scan.dart';

import 'helpers.dart';

/// Drives the real app tree: sign-up, tabs, pushed routes, logout, login.
void main() {
  late AppDatabase db;
  late AppServices services;

  setUp(() async {
    db = await openTestDb();
    services = await testServices(db);
  });

  tearDown(() => db.close());

  /// Lets real-thread work (sqflite ffi, PIN hashing isolates) finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(HarvestShelfApp(init: () async => services));
    await settle(tester);
  }

  testWidgets(
    'first run: set up researcher, see home, history, profile, log out, log in',
    (tester) async {
      await start(tester);
      expect(find.text('Set up this phone'), findsOneWidget);

      await tester.tap(find.text('Set up this phone'));
      await settle(tester);
      expect(
        find.textContaining('first account on this phone'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('reg_name')),
        'Sage Muhodari',
      );
      await tester.enterText(find.byKey(const Key('reg_username')), 'sage');
      await tester.enterText(find.byKey(const Key('reg_pin')), '2580');
      await tester.enterText(find.byKey(const Key('reg_confirm')), '2580');
      await tester.tap(find.byKey(const Key('reg_submit')));
      await settle(tester);
      expect(find.textContaining('username "sage"'), findsOneWidget);
      // Let the confirmation message time out.
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();

      // Home tab
      expect(find.text('Sage'), findsOneWidget);
      expect(find.text('Scan produce'), findsOneWidget);
      expect(
        find.text('Interim model · for testing only'),
        findsNothing,
      ); // test meta has no notice

      // A scan saved for this user shows up in History.
      final me = services.session.user!;
      await tester.runAsync(
        () => services.scans.insert(
          Scan(
            crop: 'tomato',
            category: TriageCategory.fresh,
            confidence: 0.9,
            reason: DecisionReason.model,
            inferenceMs: 100,
            modelVersion: 'v-test',
            createdAt: DateTime.now(),
            userId: me.id,
          ),
        ),
      );
      services.triage.changes.value++;
      await tester.tap(find.byTooltip('History'));
      await settle(tester);
      expect(find.text('Today'), findsWidgets);
      expect(find.textContaining('Tomato · 90%'), findsOneWidget);

      // Profile: researcher tools are visible; manage users opens.
      await tester.tap(find.byTooltip('Profile'));
      await settle(tester);
      expect(find.text('@sage · Researcher'), findsOneWidget);
      expect(find.text('Manage users'), findsOneWidget);
      await tester.tap(find.text('Manage users'));
      await settle(tester);
      expect(find.text('@sage · 1 scans · you'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);

      // Log out
      await tester.scrollUntilVisible(find.byKey(const Key('logout')), 200);
      await tester.ensureVisible(find.byKey(const Key('logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout')));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
      await settle(tester);
      expect(find.text('Log in'), findsOneWidget);
      expect(services.session.user, isNull);

      // Wrong PIN, then right PIN
      await tester.tap(find.text('Log in'));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('login_username')), 'sage');
      await tester.enterText(find.byKey(const Key('login_pin')), '9999');
      await tester.tap(find.byKey(const Key('login_submit')));
      await settle(tester);
      expect(find.text('Username or PIN is not correct.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('login_pin')), '2580');
      await tester.tap(find.byKey(const Key('login_submit')));
      await settle(tester);
      expect(find.text('Scan produce'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a seller does not see research tools and sees only their own history',
    (tester) async {
      await tester.runAsync(() async {
        final boss = await services.auth.register(
          displayName: 'Sage',
          username: 'sage',
          pin: '2580',
          confirmPin: '2580',
        );
        await services.scans.insert(
          Scan(
            crop: 'banana',
            category: TriageCategory.spoilageRisk,
            confidence: 0.9,
            reason: DecisionReason.model,
            inferenceMs: 1,
            modelVersion: 'v',
            createdAt: DateTime.now(),
            userId: boss.id,
          ),
        );
        await services.auth.register(
          displayName: 'Aline Uwase',
          username: 'aline',
          pin: '1357',
          confirmPin: '1357',
        );
        await services.session.login('aline', '1357');
      });
      await start(tester);
      expect(find.text('Aline'), findsOneWidget);

      await tester.tap(find.byTooltip('History'));
      await settle(tester);
      expect(find.text('No scans yet'), findsOneWidget);

      await tester.tap(find.byTooltip('Profile'));
      await settle(tester);
      expect(find.text('@aline · Seller'), findsOneWidget);
      expect(find.text('Manage users'), findsNothing);
      expect(find.text('Export test log (CSV)'), findsNothing);
    },
  );

  testWidgets(
    'typing an email or display name as username explains the mistake',
    (tester) async {
      await tester.runAsync(
        () => services.auth.register(
          displayName: 'test@gmail.com',
          username: 'test',
          pin: '2580',
          confirmPin: '2580',
        ),
      );
      await tester.runAsync(() => services.session.restore());
      await start(tester);
      await tester.tap(find.text('Log in'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('login_username')),
        'test@gmail.com',
      );
      await tester.enterText(find.byKey(const Key('login_pin')), '2580');
      await tester.tap(find.byKey(const Key('login_submit')));
      await settle(tester);
      expect(
        find.textContaining('Enter your username instead'),
        findsOneWidget,
      );
      expect(services.session.user, isNull);

      await tester.enterText(find.byKey(const Key('login_username')), 'test');
      await tester.tap(find.byKey(const Key('login_submit')));
      await settle(tester);
      expect(services.session.user?.username, 'test');
    },
  );

  testWidgets('switching to Kinyarwanda changes the text and is remembered', (
    tester,
  ) async {
    await start(tester);
    expect(find.text('Set up this phone'), findsOneWidget);
    await tester.tap(find.byKey(const Key('welcome_language')));
    await settle(tester);
    await tester.tap(find.text('Kinyarwanda'));
    await settle(tester);
    expect(
      find.text('Tegura iyi telefoni'),
      findsOneWidget,
    ); // "Set up this phone"
    expect(find.text('Set up this phone'), findsNothing);

    // Register in Kinyarwanda; tabs and actions are translated too.
    await tester.tap(find.text('Tegura iyi telefoni'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('reg_name')), 'Aline Uwase');
    await tester.enterText(find.byKey(const Key('reg_username')), 'aline');
    await tester.enterText(find.byKey(const Key('reg_pin')), '2580');
    await tester.enterText(find.byKey(const Key('reg_confirm')), '2580');
    await tester.tap(find.byKey(const Key('reg_submit')));
    await settle(tester);
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('Suzuma umusaruro'), findsOneWidget); // "Scan produce"
    expect(find.text('Amateka'), findsOneWidget); // "History" tab

    // The choice is stored on the phone.
    final again = await tester.runAsync(
      () => AppServices.loadLanguage(SettingsRepository(db)),
    );
    expect(again!.language.code, 'rw');
  });

  testWidgets('startup failure shows an error screen', (tester) async {
    await tester.pumpWidget(
      HarvestShelfApp(init: () async => throw StateError('model missing')),
    );
    await tester.pumpAndSettle();
    expect(find.text('The app could not start.'), findsOneWidget);
    expect(find.textContaining('model missing'), findsOneWidget);
  });
}
