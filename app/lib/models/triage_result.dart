import 'category.dart';

/// Raw classifier output for one image.
class Prediction {
  const Prediction({required this.probabilities, required this.inferenceMs});

  final List<double> probabilities;
  final int inferenceMs;
}

/// The final answer shown to the seller.
class TriageResult {
  const TriageResult({
    required this.category,
    required this.crop,
    required this.confidence,
    required this.reason,
    this.inferenceMs,
  });

  final TriageCategory category;

  /// `tomato`, `banana`, or null when the crop could not be determined.
  final String? crop;

  /// Probability behind the decision (0-1). For quality failures this is 0.
  final double confidence;
  final DecisionReason reason;

  /// Null when the image was rejected before inference.
  final int? inferenceMs;

  TriageResult withInferenceMs(int ms) => TriageResult(
    category: category,
    crop: crop,
    confidence: confidence,
    reason: reason,
    inferenceMs: ms,
  );
}
