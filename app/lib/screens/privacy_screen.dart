import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../core/theme.dart';

/// Privacy policy and end-user terms, in the current language.
///
/// Opened from Profile → About and from the consent box when registering.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const PrivacyScreen()));

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(t.privacyTitle)),
      body: SafeArea(
        child: ListView(
          key: const Key('privacy_list'),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Text(t.privacyIntro, style: text.bodyLarge!.copyWith(height: 1.55)),
            for (final (heading, body) in t.privacySections) ...[
              const SizedBox(height: 28),
              Text(heading, style: text.titleMedium),
              const SizedBox(height: 10),
              Text(body, style: text.bodyLarge!.copyWith(height: 1.55)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A consent checkbox that blocks form submission until ticked.
class ConsentField extends FormField<bool> {
  ConsentField({
    super.key,
    required String label,
    required String requiredMessage,
    required String linkLabel,
    required VoidCallback onOpenPolicy,
  }) : super(
         initialValue: false,
         validator: (v) => v == true ? null : requiredMessage,
         builder: (state) => Column(
           crossAxisAlignment: CrossAxisAlignment.stretch,
           children: [
             CheckboxListTile(
               key: const Key('consent_box'),
               value: state.value ?? false,
               onChanged: state.didChange,
               contentPadding: EdgeInsets.zero,
               controlAffinity: ListTileControlAffinity.leading,
               title: Text(label),
               subtitle: state.hasError
                   ? Text(
                       state.errorText!,
                       style: const TextStyle(color: Brand.danger),
                     )
                   : null,
             ),
             Align(
               alignment: Alignment.centerLeft,
               child: TextButton.icon(
                 key: const Key('consent_policy'),
                 onPressed: onOpenPolicy,
                 icon: const Icon(Icons.privacy_tip_outlined),
                 label: Text(linkLabel),
               ),
             ),
           ],
         ),
       );
}
