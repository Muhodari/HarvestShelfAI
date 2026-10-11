import 'dart:io';

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'core/constants.dart';
import 'l10n/app_text.dart';
import 'data/database.dart';
import 'data/repositories.dart';
import 'models/model_meta.dart';
import 'services/auth/auth_service.dart';
import 'services/auth/session.dart';
import 'services/classifier_service.dart';
import 'services/triage_service.dart';

/// Everything the screens need, created once at start-up.
class AppServices {
  AppServices({
    required this.meta,
    required this.scans,
    required this.guidance,
    required this.triage,
    required this.auth,
    required this.session,
    required this.language,
  });

  final ModelMeta meta;
  final ScanRepository scans;
  final GuidanceRepository guidance;
  final TriageService triage;
  final AuthService auth;
  final SessionController session;
  final LanguageController language;

  /// Saved language, or the phone's language if it is Kinyarwanda.
  static Future<LanguageController> loadLanguage(
    SettingsRepository settings,
  ) async {
    final saved = await settings.get('language');
    final device = PlatformDispatcher.instance.locale.languageCode;
    return LanguageController(
      initial: AppLanguage.fromCode(saved ?? device),
      save: (l) => settings.set('language', l.code),
    );
  }

  static Future<AppServices> init() async {
    final meta = await ClassifierService.loadMeta(rootBundle);
    final classifier = await ClassifierService.load(meta);
    final db = await AppDatabase.open(
      guidanceJson: await rootBundle.loadString(Assets.guidanceRules),
    );
    final scans = ScanRepository(db);
    final guidance = GuidanceRepository(db);
    final auth = AuthService(db);
    final session = SessionController(auth);
    final language = await loadLanguage(SettingsRepository(db));
    await session.restore();

    final thumbs = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'thumbs'),
    );
    await thumbs.create(recursive: true);

    Future<String?> saveThumbnail(Uint8List jpg) async {
      final f = File(
        p.join(thumbs.path, '${DateTime.now().microsecondsSinceEpoch}.jpg'),
      );
      await f.writeAsBytes(jpg);
      return f.path;
    }

    return AppServices(
      meta: meta,
      scans: scans,
      guidance: guidance,
      auth: auth,
      session: session,
      language: language,
      triage: TriageService(
        meta: meta,
        classify: classifier.classify,
        scans: scans,
        guidance: guidance,
        saveThumbnail: saveThumbnail,
      ),
    );
  }

  /// Removes thumbnail files of deleted scans.
  static Future<void> deleteFiles(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
  }
}

/// Makes [AppServices] available to the widget tree.
class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!.services;

  @override
  bool updateShouldNotify(Services oldWidget) => services != oldWidget.services;
}
