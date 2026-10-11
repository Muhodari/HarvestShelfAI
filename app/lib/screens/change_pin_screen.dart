import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/session.dart';
import '../widgets/common.dart';

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_current, _new, _confirm]) {
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
      await session.auth.changePin(
        session.user!,
        currentPin: _current.text,
        newPin: _new.text,
        confirmPin: _confirm.text,
      );
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(t.pinChanged)));
    } on AuthException catch (e) {
      setState(() => _error = t.authError(e.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.changePin)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            PinField(controller: _current, label: t.currentPin),
            const SizedBox(height: 14),
            PinField(
              controller: _new,
              label: t.newPin,
              validator: (v) => (AuthService.validatePin(v ?? '') == null
                  ? null
                  : t.authError(AuthService.validatePin(v ?? '')!)),
            ),
            const SizedBox(height: 14),
            PinField(
              controller: _confirm,
              label: t.confirmPin,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              validator: (v) =>
                  v != _new.text ? t.authError(AuthError.pinMismatch) : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              FormErrorBox(_error!),
            ],
            const SizedBox(height: 24),
            FilledButton(
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
                  : Text(t.saveNewPin),
            ),
          ],
        ),
      ),
    );
  }
}
