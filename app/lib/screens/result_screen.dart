import 'package:flutter/material.dart';
import '../l10n/app_text.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../models/category.dart';
import '../services/triage_service.dart';
import '../widgets/common.dart';

/// Shows one action, how sure the app is, and what to do (FR4).
/// Pops with an [ImageSource] when the seller wants to scan again.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.outcome});

  final TriageOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final r = outcome.result;
    final color = categoryColor(r.category);
    final isUncertain = r.category == TriageCategory.uncertain;
    // The bar only makes sense for a direct model answer: for a spoilage
    // override it would show a low number next to a warning, and for an
    // unsupported photo it is confidence that the photo is NOT produce.
    final showConfidence = r.reason == DecisionReason.model;
    final reason = t.reason(r.reason.id);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: LayoutBuilder(
                        builder: (context, c) => ScanThumb(
                          path: outcome.scan.imagePath,
                          size: c.maxWidth,
                          radius: 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Icon(categoryIcon(r.category), color: color, size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.category(r.category),
                          style: text.headlineMedium!.copyWith(color: color),
                        ),
                      ),
                    ],
                  ),
                  if (r.crop != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      t.crop(r.crop),
                      style: text.bodyLarge!.copyWith(color: Brand.inkSoft),
                    ),
                  ],
                  if (showConfidence) ...[
                    const SizedBox(height: 20),
                    ConfidenceBar(value: r.confidence, color: color),
                  ],
                  if (reason.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      reason,
                      style: text.bodyLarge!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (outcome.rule != null) ...[
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.whatToDo,
                              style: text.bodySmall!.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              t.advice(outcome.rule!.id, outcome.rule!.advice),
                              style: text.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    [
                      t.disclaimer,
                      if (r.inferenceMs != null) t.analysedIn(r.inferenceMs!),
                    ].join('\n'),
                    textAlign: TextAlign.center,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: _Actions(isUncertain: isUncertain),
            ),
          ],
        ),
      ),
    );
  }
}

/// Done / Scan again. Side by side normally; stacked when the text is
/// large or the screen is narrow, so labels never get cut off.
class _Actions extends StatelessWidget {
  const _Actions({required this.isUncertain});

  final bool isUncertain;

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final done = OutlinedButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(t.done),
    );
    final again = FilledButton.icon(
      icon: Icon(
        isUncertain ? Icons.refresh_rounded : Icons.photo_camera_rounded,
      ),
      label: Text(isUncertain ? t.retake : t.scanAnother),
      onPressed: () => Navigator.of(context).pop(ImageSource.camera),
    );
    return LayoutBuilder(
      builder: (context, c) {
        final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
        if (textScale > 1.25 || c.maxWidth < 330) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [again, const SizedBox(height: 8), done],
          );
        }
        return Row(
          children: [
            Expanded(child: done),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: again),
          ],
        );
      },
    );
  }
}
