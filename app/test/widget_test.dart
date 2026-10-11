import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harvestshelf/l10n/app_text.dart';
import 'package:harvestshelf/models/category.dart';
import 'package:harvestshelf/models/scan.dart';
import 'package:harvestshelf/models/triage_result.dart';
import 'package:harvestshelf/screens/result_screen.dart';
import 'package:harvestshelf/services/triage_service.dart';

void main() {
  // Phone-sized window (about 415 x 923 logical pixels).
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 2.6;
  });
  tearDown(
    () => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .reset(),
  );

  TriageOutcome outcome(TriageResult r) => TriageOutcome(
    result: r,
    scan: Scan(
      id: 1,
      crop: r.crop,
      category: r.category,
      confidence: r.confidence,
      reason: r.reason,
      inferenceMs: r.inferenceMs,
      modelVersion: 'v1',
      createdAt: DateTime(2026, 11, 5),
    ),
    rule: const GuidanceRule(
      id: 3,
      crop: 'tomato',
      category: TriageCategory.discountToday,
      advice: 'Lower the price and sell it today.',
    ),
  );

  testWidgets('result screen shows action, crop, confidence and advice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          outcome: outcome(
            const TriageResult(
              category: TriageCategory.discountToday,
              crop: 'tomato',
              confidence: 0.82,
              reason: DecisionReason.model,
              inferenceMs: 140,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Discount Today'), findsOneWidget);
    expect(find.text('Tomato'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(find.text('Lower the price and sell it today.'), findsOneWidget);
    expect(find.textContaining(AppText.en.disclaimer), findsOneWidget);
    expect(find.text(AppText.en.scanAnother), findsOneWidget);
  });

  testWidgets(
    'spoilage override shows the reason instead of a low confidence',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResultScreen(
            outcome: outcome(
              const TriageResult(
                category: TriageCategory.spoilageRisk,
                crop: 'tomato',
                confidence: 0.21,
                reason: DecisionReason.spoilageOverride,
                inferenceMs: 120,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Spoilage Risk'), findsOneWidget);
      expect(find.textContaining('Confidence'), findsNothing);
      expect(find.textContaining('signs of spoilage'), findsOneWidget);
    },
  );

  testWidgets('uncertain quality failure offers retake and hides confidence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          outcome: outcome(
            const TriageResult(
              category: TriageCategory.uncertain,
              crop: null,
              confidence: 0,
              reason: DecisionReason.blurry,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Uncertain'), findsOneWidget);
    expect(find.textContaining('blurred'), findsOneWidget);
    expect(find.textContaining('Confidence'), findsNothing);
    expect(find.text(AppText.en.retake), findsOneWidget);
  });
}
