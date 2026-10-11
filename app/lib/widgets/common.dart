import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/category.dart';
import '../models/scan.dart';
import '../models/user.dart';
import '../l10n/app_text.dart';

/// The HarvestShelf app icon (scripts/make_logo.py).
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

/// Soft pill: tinted background, coloured icon and text.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.category});

  final TriageCategory category;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(categoryIcon(category), color: color, size: 15),
          const SizedBox(width: 5),
          Text(
            AppText.of(context).category(category),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class ConfidenceBar extends StatelessWidget {
  const ConfidenceBar({super.key, required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppText.of(context).confidence,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Text(
              '$pct%',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              semanticsLabel: '${AppText.of(context).confidence} $pct%',
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 6,
            color: color,
            backgroundColor: Brand.line,
          ),
        ),
      ],
    );
  }
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

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.radius = 22});

  final AppUser user;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: Brand.green.withValues(alpha: 0.12),
    child: Text(
      user.initials,
      style: TextStyle(
        color: Brand.green,
        fontWeight: FontWeight.w800,
        fontSize: radius * 0.7,
      ),
    ),
  );
}

/// Plain role text, e.g. "Researcher".
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) => Text(
    AppText.of(context).role(role),
    style: Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w700),
  );
}

class ScanThumb extends StatelessWidget {
  const ScanThumb({
    super.key,
    required this.path,
    this.size = 48,
    this.radius = 12,
  });

  final String? path;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = path;
    final file = p == null ? null : File(p);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: file != null && file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : ColoredBox(
                color: Brand.surface,
                child: Icon(
                  Icons.image_outlined,
                  color: Brand.inkSoft,
                  size: size * 0.42,
                ),
              ),
      ),
    );
  }
}

/// One row of history: thumbnail, crop, action, time.
class ScanTile extends StatelessWidget {
  const ScanTile({
    super.key,
    required this.scan,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
  });

  final Scan scan;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final showPct = scan.reason == DecisionReason.model;
    final color = categoryColor(scan.category);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          ScanThumb(path: scan.imagePath),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    AppText.of(context).crop(scan.crop),
                    if (showPct) '${(scan.confidence * 100).round()}%',
                  ].join(' · '),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        AppText.of(context).category(scan.category),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatClock(scan.createdAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Brand.inkSoft.withValues(alpha: 0.6)),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );
}

/// Small sentence-case heading above a group.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

/// Numeric, hidden PIN input.
class PinField extends StatefulWidget {
  const PinField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;

  @override
  State<PinField> createState() => _PinFieldState();
}

class _PinFieldState extends State<PinField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: widget.fieldKey,
    controller: widget.controller,
    obscureText: _hidden,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(6),
    ],
    textInputAction: widget.textInputAction,
    onFieldSubmitted: widget.onSubmitted,
    validator: widget.validator,
    autofillHints: const [AutofillHints.password],
    style: const TextStyle(
      fontSize: 18,
      letterSpacing: 4,
      fontWeight: FontWeight.w700,
    ),
    decoration: InputDecoration(
      labelText: widget.label,
      suffixIcon: IconButton(
        tooltip: _hidden
            ? AppText.of(context).showPin
            : AppText.of(context).hidePin,
        icon: Icon(
          _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          semanticLabel: _hidden
              ? AppText.of(context).showPin
              : AppText.of(context).hidePin,
        ),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    ),
  );
}

/// Inline form error.
class FormErrorBox extends StatelessWidget {
  const FormErrorBox(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.error_outline_rounded, color: Brand.danger, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          message,
          style: const TextStyle(
            color: Brand.danger,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    ],
  );
}

/// Spinner sized for a button label.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 22,
    height: 22,
    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
  );
}

String _two(int v) => v.toString().padLeft(2, '0');

String formatClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String formatTime(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${formatClock(t)}';
