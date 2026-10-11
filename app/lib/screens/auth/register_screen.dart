import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
import '../../services/auth/auth_service.dart';
import '../../services/auth/session.dart';
import '../../widgets/common.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _username, _pin, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final t = AppText.of(context);
    if (_busy || !_form.currentState!.validate()) return;
    final session = SessionScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.register(
        displayName: _name.text,
        username: _username.text,
        pin: _pin.text,
        confirmPin: _confirm.text,
      );
      navigator.popUntil((r) => r.isFirst);
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            t.accountCreated(AuthService.normalizeUsername(_username.text)),
          ),
        ),
      );
    } on AuthException catch (e) {
      setState(() => _error = t.authError(e.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final first = !SessionScope.of(context).hasUsers;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Text(
                first ? t.setUpPhone : t.createYourAccount,
                style: text.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                t.takesAMinute,
                style: text.bodyLarge!.copyWith(color: text.bodySmall!.color),
              ),
              if (first) ...[
                const SizedBox(height: 16),
                Text(t.firstAccountNote, style: text.bodySmall),
              ],
              const SizedBox(height: 24),
              TextFormField(
                key: const Key('reg_name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: InputDecoration(
                  labelText: t.fullName,
                  helperText: t.nameHelp,
                ),
                validator: (v) => (AuthService.validateName(v ?? '') == null
                    ? null
                    : t.authError(AuthService.validateName(v ?? '')!)),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('reg_username'),
                controller: _username,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newUsername],
                decoration: InputDecoration(
                  labelText: t.username,
                  hintText: t.usernameHint,
                  helperText: t.usernameHelp,
                ),
                validator: (v) => (AuthService.validateUsername(v ?? '') == null
                    ? null
                    : t.authError(AuthService.validateUsername(v ?? '')!)),
              ),
              const SizedBox(height: 14),
              PinField(
                fieldKey: const Key('reg_pin'),
                controller: _pin,
                label: t.pin,
                validator: (v) => (AuthService.validatePin(v ?? '') == null
                    ? null
                    : t.authError(AuthService.validatePin(v ?? '')!)),
              ),
              const SizedBox(height: 14),
              PinField(
                fieldKey: const Key('reg_confirm'),
                controller: _confirm,
                label: t.confirmPin,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                validator: (v) =>
                    v != _pin.text ? t.authError(AuthError.pinMismatch) : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                FormErrorBox(_error!),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('reg_submit'),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(t.createAccount),
              ),
              if (!first) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  child: Text(t.haveAccount),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                t.pinStored,
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
