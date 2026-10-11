import 'package:flutter/widgets.dart';

import '../models/category.dart';
import '../models/user.dart';
import '../services/auth/auth_service.dart';

/// Languages the app supports.
enum AppLanguage {
  en('en', 'English'),
  rw('rw', 'Kinyarwanda');

  const AppLanguage(this.code, this.nativeName);

  final String code;
  final String nativeName;

  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
    (l) => l.code == code,
    orElse: () => AppLanguage.en,
  );
}

/// Every user-facing text, English and Kinyarwanda side by side.
///
/// KINYARWANDA REVIEW NEEDED: the Kinyarwanda was written by the developer
/// with an AI assistant and has not yet been checked by a native speaker.
/// Have it reviewed (ideally by sellers in Nyabihu and Rusizi) before the
/// field study, and fix wording directly in the second argument of `_t`.
class AppText {
  const AppText(this.lang);

  final AppLanguage lang;

  static const en = AppText(AppLanguage.en);

  /// The current language, or English when no [LanguageScope] is above
  /// [context] (for example in isolated widget tests).
  static AppText of(BuildContext context) =>
      AppText(LanguageScope.maybeOf(context) ?? AppLanguage.en);

  String _t(String english, String kinyarwanda) =>
      lang == AppLanguage.rw ? kinyarwanda : english;

  bool get isRw => lang == AppLanguage.rw;

  // ---- general -------------------------------------------------------
  String get appName => 'HarvestShelf';
  String get tagline =>
      _t('Know what to sell first.', 'Menya icyo ugomba kugurisha mbere.');
  String get disclaimer => _t(
    'Visible condition only. This is not a food-safety check.',
    "Iri suzuma rireba uko bigaragara gusa. Ntabwo ari igenzura ry'umutekano w'ibiribwa.",
  );
  String get demoWarning => _t(
    'Demo model: not trained on real produce. Results are not meaningful.',
    "Icyitegererezo cy'igerageza: nticyatojwe ku musaruro nyawo. Ibisubizo ntibyizewe.",
  );
  String get demoShort => _t(
    'Demo model · results not meaningful',
    "Icyitegererezo cy'igerageza · ibisubizo ntibyizewe",
  );
  String get aboutModel =>
      _t('About this model', "Ibyerekeye iki cyitegererezo");
  String get offlinePromise => _t(
    'Works offline · Your data stays on this phone',
    'Ikora nta interineti · Amakuru yawe aguma kuri iyi telefoni',
  );
  String get couldNotStart =>
      _t('The app could not start.', 'Porogaramu ntiyashoboye gutangira.');
  String get ok => _t('OK', 'Yego');
  String get cancel => _t('Cancel', 'Reka');
  String get save => _t('Save', 'Bika');
  String get delete => _t('Delete', 'Siba');
  String get done => _t('Done', 'Funga');
  String get back => _t('Back', 'Subira inyuma');
  String get language => _t('Language', 'Ururimi');
  String logoLabel() => '$appName logo';

  // ---- navigation ----------------------------------------------------
  String get scan => _t('Scan', 'Suzuma');
  String get history => _t('History', 'Amateka');
  String get profile => _t('Profile', 'Umwirondoro');

  // ---- home / scanning -----------------------------------------------
  String greeting(DateTime now) => now.hour < 12
      ? _t('Good morning', 'Mwaramutse')
      : now.hour < 17
      ? _t('Good afternoon', 'Mwiriwe')
      : _t('Good evening', 'Mwiriwe');
  String get scanProduce => _t('Scan produce', 'Suzuma umusaruro');
  String get takePhoto => _t('Take photo', 'Fata ifoto');
  String get chooseFromGallery => _t('Choose from gallery', 'Hitamo mu mafoto');
  String get scanHint => _t(
    'One tomato or banana hand, filling the frame, in daylight.',
    'Inyanya imwe cyangwa igitoki kimwe, cyuzuye ifoto, ku manywa.',
  );
  String get checking => _t('Checking produce…', 'Turimo gusuzuma…');
  String scanFailed(Object e) => _t('Scan failed: $e', 'Isuzuma ryanze: $e');
  String get today => _t('Today', 'Uyu munsi');
  String get yesterday => _t('Yesterday', 'Ejo hashize');
  String get recent => _t('Recent', 'Ibiheruka');
  String get seeAll => _t('See all', 'Reba byose');
  String get noScansHome => _t(
    'No scans yet. Your first result will appear here.',
    'Nta suzuma rirakorwa. Igisubizo cya mbere kizagaragara hano.',
  );

  // ---- result ----------------------------------------------------------
  String get scanAnother => _t('Scan another', 'Suzuma ikindi');
  String get retake => _t('Retake photo', 'Ongera ufate ifoto');
  String get confidence => _t('Confidence', 'Icyizere');
  String get whatToDo => _t('What to do', 'Icyo wakora');
  String analysedIn(int ms) => _t(
    'Analysed on this phone in $ms ms.',
    'Byasuzumiwe kuri iyi telefoni mu $ms ms.',
  );

  String category(TriageCategory c) => switch (c) {
    TriageCategory.fresh => _t('Fresh', 'Bishya'),
    TriageCategory.sellSoon => _t('Sell Soon', 'Gurisha vuba'),
    TriageCategory.discountToday => _t(
      'Discount Today',
      'Gabanya igiciro uyu munsi',
    ),
    TriageCategory.spoilageRisk => _t('Spoilage Risk', 'Byenda kwangirika'),
    TriageCategory.uncertain => _t('Uncertain', 'Ntibisobanutse'),
  };

  /// Short labels for the "Today" tally.
  String categoryShort(TriageCategory c) => switch (c) {
    TriageCategory.fresh => _t('Fresh', 'Bishya'),
    TriageCategory.sellSoon => _t('Sell soon', 'Gurisha vuba'),
    TriageCategory.discountToday => _t('Discount', 'Gabanya'),
    TriageCategory.spoilageRisk => _t('Spoilage', 'Byangirika'),
    TriageCategory.uncertain => _t('Unsure', 'Ntibizwi'),
  };

  String crop(String? crop) => switch (crop) {
    'tomato' => _t('Tomato', 'Inyanya'),
    'banana' => _t('Green banana', 'Igitoki kibisi'),
    _ => _t('Unknown', 'Ntibizwi'),
  };

  String reason(String reasonId) => switch (reasonId) {
    'too_dark' => _t(
      'The photo is too dark. Move to better light.',
      'Ifoto irijimye cyane. Jya ahari urumuri ruhagije.',
    ),
    'too_bright' => _t(
      'The photo is too bright. Avoid direct sun glare.',
      'Ifoto ifite urumuri rwinshi. Irinde izuba rikubita ku ifoto.',
    ),
    'blurry' => _t(
      'The photo is blurred. Hold the phone still and refocus.',
      'Ifoto ntigaragara neza. Fata telefoni neza utanyeganyega.',
    ),
    'unsupported' => _t(
      'This does not look like a tomato or green banana.',
      "Ibi ntibisa n'inyanya cyangwa igitoki kibisi.",
    ),
    'low_confidence' => _t(
      'The app is not sure. Retake the photo closer, in good light.',
      'Porogaramu ntizi neza. Ongera ufate ifoto wegereye, ahari urumuri.',
    ),
    'spoilage_override' => _t(
      'Some signs of spoilage were detected. Check the item carefully.',
      'Habonetse ibimenyetso byo kwangirika. Bigenzure neza.',
    ),
    _ => '',
  };

  /// Advice for a guidance rule (ids from assets/guidance_rules.json);
  /// [fallback] is the English text stored in the database.
  String advice(int ruleId, String fallback) {
    if (!isRw) return fallback;
    return switch (ruleId) {
      1 || 5 => 'Ubwiza bwo kugurisha ni bwiza. Gurisha ku giciro gisanzwe.',
      2 =>
        'Ibimenyetso bya mbere byo kwera cyangwa guhinduka. Bishyire imbere ku meza ubigurishe mbere.',
      3 =>
        'Byatangiye kwangirika. Gabanya igiciro ubigurishe uyu munsi. Ntubishyire ku zuba.',
      4 =>
        "Bikure mu bicuruzwa bisanzwe. Bitandukanye n'inyanya nshya kugira ngo bitazangiza.",
      6 =>
        'Hari ibikomere bito cyangwa gutangira kwera. Gurisha ibi bitoki mbere.',
      7 =>
        'Bifite ibikomere cyangwa byoroshye. Gabanya igiciro ubigurishe uyu munsi.',
      8 =>
        "Bikure mu bicuruzwa bisanzwe. Bitandukanye n'ibitoki bishya; ibyeze bishobora kwihutisha kwera kw'ibindi.",
      9 =>
        "Ongera ufate ifoto: ikintu kimwe, cyuzuye ifoto, ku manywa. Niba bitarasobanuka, genzura n'intoki.",
      _ => fallback,
    };
  }

  // ---- history -----------------------------------------------------------
  String get all => _t('All', 'Byose');
  String get couldNotLoadHistory =>
      _t('Could not load history', 'Amateka ntiyabonetse');
  String get noScansYet => _t('No scans yet', 'Nta suzuma rirakorwa');
  String get scansAppearHere => _t(
    'Your scans will appear here, newest first.',
    'Amasuzuma yawe azagaragara hano, aheruka mbere.',
  );
  String formatDay(DateTime t, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final diff = DateTime(
      n.year,
      n.month,
      n.day,
    ).difference(DateTime(t.year, t.month, t.day)).inDays;
    if (diff == 0) return today;
    if (diff == 1) return yesterday;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return isRw
        ? '${t.day}/${t.month}/${t.year}'
        : '${t.day} ${months[t.month - 1]} ${t.year}';
  }

  // ---- accounts ------------------------------------------------------------
  String get setUpPhone => _t('Set up this phone', 'Tegura iyi telefoni');
  String get createAccount => _t('Create account', 'Fungura konti');
  String get createYourAccount =>
      _t('Create your account', 'Fungura konti yawe');
  String get takesAMinute =>
      _t('It takes less than a minute.', "Bifata munsi y'umunota umwe.");
  String get haveAccount => _t('I already have an account', 'Mfite konti');
  String get login => _t('Log in', 'Injira');
  String get logout => _t('Log out', 'Sohoka');
  String get welcomeBack => _t('Welcome back', 'Murakaza neza');
  String get loginSubtitle =>
      _t('Log in to see your scans.', 'Injira urebe amasuzuma yawe.');
  String get firstAccountNote => _t(
    'This is the first account on this phone, so it will be the Researcher account. '
        'Researchers can add sellers and export the study log.',
    "Iyi ni konti ya mbere kuri iyi telefoni, bityo izaba konti y'Umushakashatsi. "
        "Abashakashatsi bashobora kongeramo abacuruzi no gukuramo raporo y'ubushakashatsi.",
  );
  String get fullName => _t('Your name', 'Amazina yawe');
  String get nameHelp => _t(
    'Shown in the app, e.g. Aline Uwase.',
    'Agaragara muri porogaramu, urugero: Aline Uwase.',
  );
  String get username => _t('Username', 'Izina ryo kwinjira');
  String get usernameHint => 'e.g. aline.m';
  String get usernameHelp => _t(
    'You will use this to log in. No @ or spaces.',
    'Uzarikoresha winjira. Nta @ cyangwa umwanya.',
  );
  String get usernameLoginHelp => _t(
    'The short username you chose, not your name or email.',
    'Izina rigufi wahisemo, si amazina yawe cyangwa imeyili.',
  );
  String get usernameNotEmail => _t(
    'This looks like an email or a name. Enter your username instead (e.g. aline.m).',
    "Ibi bisa n'imeyili cyangwa amazina. Andika izina ryo kwinjira (urugero: aline.m).",
  );
  String get enterUsername =>
      _t('Enter your username.', 'Andika izina ryo kwinjira.');
  String get pinLabel => 'PIN';
  String get enterPin => _t('Enter your PIN.', 'Andika PIN yawe.');
  String get pin => _t('PIN (4 to 6 digits)', 'PIN (imibare 4 kugeza kuri 6)');
  String get confirmPin => _t('Repeat PIN', 'Ongera wandike PIN');
  String get showPin => _t('Show PIN', 'Erekana PIN');
  String get hidePin => _t('Hide PIN', 'Hisha PIN');
  String get noAccount =>
      _t('New here? Create an account', 'Uri mushya? Fungura konti');
  String get forgotPin => _t(
    'Forgot your PIN? Ask the researcher to reset it.',
    'Wibagiwe PIN? Saba umushakashatsi kuyihindura.',
  );
  String get pinStored => _t(
    'Your PIN is stored scrambled (hashed) on this phone only.',
    "PIN yawe ibikwa mu buryo bw'ibanga kuri iyi telefoni gusa.",
  );
  String accountCreated(String username) => _t(
    'Account created. Log in next time with username "$username" and your PIN.',
    'Konti yafunguwe. Ubutaha injira ukoresheje izina "$username" na PIN yawe.',
  );
  String role(UserRole r) => switch (r) {
    UserRole.researcher => _t('Researcher', 'Umushakashatsi'),
    UserRole.seller => _t('Seller', 'Umucuruzi'),
  };

  String authError(AuthError e) => switch (e) {
    AuthError.invalidName => _t(
      e.message,
      'Andika amazina yawe (inyuguti 2 kugeza kuri 40).',
    ),
    AuthError.invalidUsername => _t(
      e.message,
      'Izina ryo kwinjira: inyuguti 3 kugeza kuri 20, imibare, utudomo cyangwa _.',
    ),
    AuthError.usernameTaken => _t(
      e.message,
      'Iryo zina risanzwe rikoreshwa kuri iyi telefoni.',
    ),
    AuthError.invalidPin => _t(
      e.message,
      'PIN igomba kuba imibare 4 kugeza kuri 6.',
    ),
    AuthError.weakPin => _t(
      e.message,
      'Hitamo PIN itoroshye gukekwa (si 1234, 0000, ...).',
    ),
    AuthError.pinMismatch => _t(e.message, 'PIN zombi ntizihuye.'),
    AuthError.wrongCredentials => _t(e.message, 'Izina cyangwa PIN si byo.'),
    AuthError.lockedOut => _t(
      e.message,
      'Wagerageje PIN nabi inshuro nyinshi. Ongera ugerageze nyuma gato.',
    ),
    AuthError.wrongCurrentPin => _t(e.message, 'PIN ufite ubu si yo.'),
    AuthError.notAllowed => _t(
      e.message,
      'Umushakashatsi wenyine ni we ushobora gukora ibi.',
    ),
    AuthError.cannotDeleteSelf => _t(
      e.message,
      'Ntushobora gusiba konti yawe hano.',
    ),
    AuthError.lastResearcher => _t(
      e.message,
      "Hagomba gusigara nibura konti imwe y'umushakashatsi.",
    ),
    AuthError.notFound => _t(e.message, 'Konti ntiyabonetse.'),
  };

  // ---- profile -------------------------------------------------------------
  String get account => _t('Account', 'Konti');
  String get editName => _t('Edit name', 'Hindura amazina');
  String get changePin => _t('Change PIN', 'Hindura PIN');
  String get research => _t('Research', 'Ubushakashatsi');
  String get manageUsers => _t('Manage users', 'Gucunga abakoresha');
  String get manageUsersSub => _t(
    'Add sellers, reset PINs, change roles',
    "Ongeramo abacuruzi, hindura PIN n'inshingano",
  );
  String get exportLog =>
      _t('Export test log (CSV)', "Kuramo raporo y'igerageza (CSV)");
  String get exportSub => _t(
    'All scans on this phone. No images, names or usernames.',
    'Amasuzuma yose ari kuri iyi telefoni. Nta mafoto, amazina cyangwa amazina yo kwinjira.',
  );
  String get model => _t('Model', 'Icyitegererezo');
  String modelSub(String version, double tConf, double tSpoil) => _t(
    '$version · thresholds confidence $tConf, spoilage $tSpoil',
    '$version · imipaka: icyizere $tConf, kwangirika $tSpoil',
  );
  String get myData => _t('My data', 'Amakuru yanjye');
  String get clearHistory => _t('Clear my history', 'Siba amateka yanjye');
  String get about => _t('About', 'Ibyerekeye');
  String get worksOffline => _t('Works offline.', 'Ikora nta interineti.');
  String get logoutQ => _t('Log out?', 'Urashaka gusohoka?');
  String get logoutBody => _t(
    'Your scans stay saved on this phone.',
    'Amasuzuma yawe aguma abitswe kuri iyi telefoni.',
  );
  String savedTo(String path) => _t('Saved: $path', 'Byabitswe: $path');
  String exportFailed(Object e) => _t('Export failed: $e', 'Kubika byanze: $e');
  String get clearQ =>
      _t('Clear your history?', 'Urashaka gusiba amateka yawe?');
  String get clearBody => _t(
    'This deletes all of your scans on this phone. It cannot be undone.',
    'Ibi bisiba amasuzuma yawe yose kuri iyi telefoni. Ntibishobora gusubizwa.',
  );
  String deletedScans(int n) =>
      _t('Deleted $n scans.', 'Amasuzuma $n yasibwe.');
  String get currentPin => _t('Current PIN', 'PIN ufite ubu');
  String get newPin =>
      _t('New PIN (4 to 6 digits)', 'PIN nshya (imibare 4 kugeza kuri 6)');
  String get saveNewPin => _t('Save new PIN', 'Bika PIN nshya');
  String get pinChanged => _t('PIN changed.', 'PIN yahinduwe.');

  // ---- manage users ----------------------------------------------------------
  String get addUser => _t('Add user', 'Ongeramo umukoresha');
  String get addAUser => _t('Add a user', 'Ongeramo umukoresha');
  String get couldNotLoadUsers =>
      _t('Could not load users', 'Abakoresha ntibabonetse');
  String scansCount(int n) => _t('$n scans', 'amasuzuma $n');
  String get you => _t('you', 'wowe');
  String get deletingNote => _t(
    'Deleting a user also deletes their scans.',
    "Gusiba umukoresha bisiba n'amasuzuma ye.",
  );
  String get makeSeller => _t('Make seller', 'Mugire umucuruzi');
  String get makeResearcher => _t('Make researcher', 'Mugire umushakashatsi');
  String get resetPin => _t('Reset PIN', 'Hindura PIN');
  String get deleteAccountAndScans =>
      _t('Delete account and scans', "Siba konti n'amasuzuma");
  String roleChanged(String name, UserRole r) => _t(
    '$name is now a ${role(r).toLowerCase()}.',
    '$name ubu ni ${role(r).toLowerCase()}.',
  );
  String pinResetFor(String name) =>
      _t('PIN reset for $name.', 'PIN ya $name yahinduwe.');
  String deleteQ(String name) => _t('Delete $name?', 'Gusiba $name?');
  String get deleteBody => _t(
    'Their account and all their scans will be removed from this phone.',
    "Konti ye n'amasuzuma ye yose bizavanwa kuri iyi telefoni.",
  );
  String deletedUser(String name) => _t('$name deleted.', '$name yasibwe.');
  String newPinFor(String name) =>
      _t('New PIN for $name', 'PIN nshya ya $name');
  String get reset => _t('Reset', 'Hindura');
  String addedUser(String name) => _t(
    'Added $name. Give them their username and PIN.',
    'Wongeyemo $name. Muhe izina ryo kwinjira na PIN.',
  );
  String get name => _t('Name', 'Amazina');
  String get startingPin => _t(
    'Starting PIN (4 to 6 digits)',
    'PIN ya mbere (imibare 4 kugeza kuri 6)',
  );
}

/// The chosen language, persisted on the phone.
class LanguageController extends ChangeNotifier {
  LanguageController({
    required AppLanguage initial,
    required Future<void> Function(AppLanguage) save,
  }) : _language = initial,
       _save = save;

  AppLanguage _language;
  final Future<void> Function(AppLanguage) _save;

  AppLanguage get language => _language;

  Future<void> set(AppLanguage l) async {
    if (l == _language) return;
    _language = l;
    notifyListeners();
    await _save(l);
  }
}

class LanguageScope extends InheritedNotifier<LanguageController> {
  const LanguageScope({
    super.key,
    required LanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLanguage? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LanguageScope>()
      ?.notifier
      ?.language;

  static LanguageController controllerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageScope>()!.notifier!;
}
