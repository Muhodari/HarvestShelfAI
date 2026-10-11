import 'package:flutter/material.dart';

import 'app_services.dart';
import 'l10n/app_text.dart';
import 'core/theme.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/home_shell.dart';
import 'services/auth/session.dart';
import 'widgets/common.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HarvestShelfApp());
}

class HarvestShelfApp extends StatefulWidget {
  const HarvestShelfApp({super.key, this.init = AppServices.init});

  /// Creates the services; tests pass a fake.
  final Future<AppServices> Function() init;

  @override
  State<HarvestShelfApp> createState() => _HarvestShelfAppState();
}

class _HarvestShelfAppState extends State<HarvestShelfApp> {
  AppServices? _services;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.init().then(
      (s) => setState(() => _services = s),
      onError: (Object e) => setState(() => _error = e),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    return MaterialApp(
      title: 'HarvestShelf',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Services and the session sit above the Navigator so every pushed
      // route can reach them.
      builder: (context, child) => services == null
          ? child!
          : Services(
              services: services,
              child: LanguageScope(
                controller: services.language,
                child: SessionScope(session: services.session, child: child!),
              ),
            ),
      home: _error != null
          ? _StartupError(error: _error!)
          : services == null
          ? const _Splash()
          : const AuthGate(),
    );
  }
}

/// Welcome/login when signed out, the main app when signed in.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    if (!session.ready) return const _Splash();
    return session.user == null
        ? const WelcomeScreen()
        // Keyed by user so nothing from a previous user's session survives.
        : HomeShell(key: ValueKey(session.user!.id));
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Brand.greenDeep,
    body: Center(child: AppLogo(size: 112)),
  );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 16),
            Text(
              AppText.of(context).couldNotStart,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
