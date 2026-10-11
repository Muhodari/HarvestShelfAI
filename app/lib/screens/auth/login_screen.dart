import 'dart:async';

import '../../l10n/app_text.dart';
import 'package:flutter/material.dart';

import '../../services/auth/auth_service.dart';
import '../../services/auth/session.dart';
import '../../widgets/common.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;
  DateTime? _lockedUntil;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _username.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = AppText.of(context);
    if (_busy || _isLocked || !_form.currentState!.validate()) return;
    final session = SessionScope.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.login(_username.text, _pin.text);
      navigator.popUntil((r) => r.isFirst);
    } on AuthException catch (e) {
      _pin.clear();
      setState(() {
        _error = t.authError(e.error);
        _lockedUntil = e.lockedUntil;
      });
      if (e.lockedUntil != null) _startTicker();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _isLocked =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_isLocked) {
        t.cancel();
        _lockedUntil = null;
        _error = null;
      }
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final text = Theme.of(context).textTheme;
    final remaining = _isLocked
        ? _lockedUntil!.difference(DateTime.now()).inSeconds + 1
        : 0;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Form(
          key: _form,
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              children: [
                Text(t.welcomeBack, style: text.headlineMedium),
                const SizedBox(height: 6),
                Text(
                  t.loginSubtitle,
                  style: text.bodyLarge!.copyWith(color: text.bodySmall!.color),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  key: const Key('login_username'),
                  controller: _username,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  decoration: InputDecoration(
                    labelText: t.username,
                    helperText: t.usernameLoginHelp,
                  ),
                  validator: (v) {
                    final u = (v ?? '').trim();
                    if (u.isEmpty) return t.enterUsername;
                    if (u.contains('@') || u.contains(' ')) {
                      return t.usernameNotEmail;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                PinField(
                  fieldKey: const Key('login_pin'),
                  controller: _pin,
                  label: 'PIN',
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  validator: (v) => (v ?? '').length < 4 ? t.enterPin : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  FormErrorBox(
                    _isLocked ? '${_error!} ($remaining s)' : _error!,
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('login_submit'),
                  onPressed: _busy || _isLocked ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(t.login),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  ),
                  child: Text(t.noAccount),
                ),
                const SizedBox(height: 8),
                Text(
                  t.forgotPin,
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
