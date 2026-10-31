/// App logo and model notice.
library;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../l10n/app_text.dart';

/// The HarvestShelf app icon.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: AppText.of(context).logoLabel(),
    child: Image.asset(
      Assets.logoIcon,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    ),
  );
}

/// One quiet line for demo/interim-model warnings; tap for the full text.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key, this.text, this.short});

  /// Full text; defaults to the demo-model warning.
  final String? text;
  final String? short;

  @override
  Widget build(BuildContext context) {
    final full = text ?? AppText.of(context).demoWarning;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppText.of(context).aboutModel),
          content: Text(full),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppText.of(context).ok),
            ),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: Color(0xFF8F5B00),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                short ?? full,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF8F5B00),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
