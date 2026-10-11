import '../models/category.dart';
import '../models/model_meta.dart';
import '../models/triage_result.dart';

/// Turns class probabilities into one triage action (FR4, NFR6).
///
/// Mirrors `training/src/decision.py`; both are tested against
/// `shared/decision_cases.json`. Rule order:
///   1. top class is `unusable`            -> Uncertain (unsupported)
///   2. spoilage prob of top crop >= tSpoil -> Spoilage Risk
///   3. top prob < tConf                    -> Uncertain (low confidence)
///   4. otherwise                           -> category of top class
/// Rule 2 runs before rule 3 because missing a Spoilage Risk item costs
/// more than an unnecessary warning.
class DecisionMapper {
  const DecisionMapper(this.meta);

  final ModelMeta meta;

  TriageResult map(List<double> probs) {
    if (probs.length != meta.labels.length) {
      throw ArgumentError(
        'Expected ${meta.labels.length} probabilities, got ${probs.length}',
      );
    }

    var top = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[top]) top = i;
    }
    final label = meta.labels[top];

    if (label.isUnusable) {
      return TriageResult(
        category: TriageCategory.uncertain,
        crop: null,
        confidence: probs[top],
        reason: DecisionReason.unsupported,
      );
    }

    final spoilIdx = meta.spoilageIndex(label.crop);
    if (spoilIdx != null && probs[spoilIdx] >= meta.tSpoil) {
      return TriageResult(
        category: TriageCategory.spoilageRisk,
        crop: label.crop,
        confidence: probs[spoilIdx],
        reason: spoilIdx == top
            ? DecisionReason.model
            : DecisionReason.spoilageOverride,
      );
    }

    if (probs[top] < meta.tConf) {
      return TriageResult(
        category: TriageCategory.uncertain,
        crop: label.crop,
        confidence: probs[top],
        reason: DecisionReason.lowConfidence,
      );
    }

    return TriageResult(
      category: label.category,
      crop: label.crop,
      confidence: probs[top],
      reason: DecisionReason.model,
    );
  }
}
