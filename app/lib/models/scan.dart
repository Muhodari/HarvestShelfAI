import 'category.dart';

/// One saved scan (a row in the `scan` table).
class Scan {
  const Scan({
    this.id,
    required this.crop,
    required this.category,
    required this.confidence,
    required this.reason,
    required this.inferenceMs,
    required this.modelVersion,
    required this.createdAt,
    this.imagePath,
    this.ruleId,
    this.userId,
  });

  final int? id;

  /// Owner; null for scans made before accounts existed.
  final int? userId;
  final String? crop;
  final TriageCategory category;
  final double confidence;
  final DecisionReason reason;
  final int? inferenceMs;
  final String modelVersion;
  final DateTime createdAt;

  /// Local thumbnail path; images never leave the phone.
  final String? imagePath;
  final int? ruleId;

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'crop': crop,
    'category': category.id,
    'confidence': confidence,
    'reason': reason.id,
    'inference_ms': inferenceMs,
    'model_version': modelVersion,
    'created_at': createdAt.toIso8601String(),
    'image_path': imagePath,
    'rule_id': ruleId,
    'user_id': userId,
  };

  factory Scan.fromMap(Map<String, Object?> m) => Scan(
    id: m['id'] as int?,
    crop: m['crop'] as String?,
    category: TriageCategory.fromId(m['category'] as String),
    confidence: (m['confidence'] as num).toDouble(),
    reason: DecisionReason.fromId(m['reason'] as String),
    inferenceMs: m['inference_ms'] as int?,
    modelVersion: m['model_version'] as String,
    createdAt: DateTime.parse(m['created_at'] as String),
    imagePath: m['image_path'] as String?,
    ruleId: m['rule_id'] as int?,
    userId: m['user_id'] as int?,
  );
}

/// Advice text for a crop and category (a row in `guidance_rule`).
class GuidanceRule {
  const GuidanceRule({
    required this.id,
    required this.crop,
    required this.category,
    required this.advice,
  });

  final int id;

  /// `tomato`, `banana`, or `any`.
  final String crop;
  final TriageCategory category;
  final String advice;

  factory GuidanceRule.fromMap(Map<String, Object?> m) => GuidanceRule(
    id: m['id'] as int,
    crop: m['crop'] as String,
    category: TriageCategory.fromId(m['category'] as String),
    advice: m['advice'] as String,
  );
}
