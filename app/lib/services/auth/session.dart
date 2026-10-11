import 'package:flutter/widgets.dart';

import '../../models/user.dart';
import 'auth_service.dart';

/// Who is signed in. Persists across restarts through the `session` table.
class SessionController extends ChangeNotifier {
  SessionController(this.auth);

  final AuthService auth;

  AppUser? _user;
  bool _ready = false;
  bool _hasUsers = false;

  AppUser? get user => _user;

  /// False until the stored session has been read at start-up.
  bool get ready => _ready;

  /// False on a fresh install: the welcome screen then offers to create
  /// the first (researcher) account.
  bool get hasUsers => _hasUsers;

  Future<void> restore() async {
    _user = await auth.currentUser();
    _hasUsers = await auth.hasAnyUser();
    _ready = true;
    notifyListeners();
  }

  Future<AppUser> login(String username, String pin) async {
    _user = await auth.login(username, pin);
    _hasUsers = true;
    notifyListeners();
    return _user!;
  }

  /// Creates the account and signs straight in.
  Future<AppUser> register({
    required String displayName,
    required String username,
    required String pin,
    required String confirmPin,
  }) async {
    await auth.register(
      displayName: displayName,
      username: username,
      pin: pin,
      confirmPin: confirmPin,
    );
    return login(username, pin);
  }

  Future<void> logout() async {
    await auth.logout();
    _user = null;
    notifyListeners();
  }

  /// Re-reads the signed-in user after a name or role change.
  Future<void> refresh() async {
    final u = _user;
    if (u == null) return;
    _user = await auth.byId(u.id);
    if (_user == null) await auth.logout();
    notifyListeners();
  }
}

/// Rebuilds dependants when the session changes.
class SessionScope extends InheritedNotifier<SessionController> {
  const SessionScope({
    super.key,
    required SessionController session,
    required super.child,
  }) : super(notifier: session);

  static SessionController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  /// The signed-in user. Only call below the auth gate.
  static AppUser userOf(BuildContext context) => of(context).user!;
}
