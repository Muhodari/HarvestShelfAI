/// Widgets that show a scan result: action badge, confidence, photo, history row.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/time_format.dart';
import '../models/category.dart';
import '../models/scan.dart';
import '../l10n/app_text.dart';

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
          Flexible(
            child: Text(
              AppText.of(context).category(category),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
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
            minHeight: 8,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }
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
                color: Brand.line,
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
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final Scan scan;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final showPct = scan.reason == DecisionReason.model;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          ScanThumb(path: scan.imagePath, size: 52, radius: 14),
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
                const SizedBox(height: 6),
                CategoryBadge(category: scan.category),
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
