import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
import '../../services/auth/session.dart';
import '../../widgets/common.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import '../profile_screen.dart' show chooseLanguage;

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final hasUsers = SessionScope.of(context).hasUsers;
    final text = Theme.of(context).textTheme;

    void open(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const Key('welcome_language'),
                  icon: const Icon(Icons.translate_rounded, size: 20),
                  label: Text(
                    LanguageScope.controllerOf(context).language.nativeName,
                  ),
                  onPressed: () => chooseLanguage(context),
                ),
              ),
              const Spacer(flex: 3),
              const Center(child: AppLogo(size: 104)),
              const SizedBox(height: 28),
              Text(
                t.appName,
                textAlign: TextAlign.center,
                style: text.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                t.tagline,
                textAlign: TextAlign.center,
                style: text.bodyLarge!.copyWith(color: text.bodySmall!.color),
              ),
              const Spacer(flex: 4),
              if (hasUsers) ...[
                FilledButton(
                  onPressed: () => open(const LoginScreen()),
                  child: Text(t.login),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => open(const RegisterScreen()),
                  child: Text(t.createAccount),
                ),
              ] else
                FilledButton(
                  onPressed: () => open(const RegisterScreen()),
                  child: Text(t.setUpPhone),
                ),
              const SizedBox(height: 20),
              Text(
                t.offlinePromise,
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
