import 'category.dart';

/// One output class of the classifier, e.g. `tomato_sell_soon`.
class ClassLabel {
  const ClassLabel({
    required this.index,
    required this.id,
    required this.crop,
    required this.category,
  });

  final int index;
  final String id;

  /// `tomato`, `banana`, or `none` for the unusable class.
  final String crop;
  final TriageCategory category;

  bool get isUnusable => crop == 'none';

  factory ClassLabel.fromJson(Map<String, dynamic> json) => ClassLabel(
    index: json['index'] as int,
    id: json['id'] as String,
    crop: json['crop'] as String,
    category: TriageCategory.fromId(json['category'] as String),
  );
}

/// Image-quality thresholds applied before inference.
class QualityThresholds {
  const QualityThresholds({
    this.minBrightness = 40,
    this.maxBrightness = 235,
    this.minSharpness = 80,
  });

  /// Mean luminance (0-255) below which a photo is too dark.
  final double minBrightness;

  /// Mean luminance (0-255) above which a photo is overexposed.
  final double maxBrightness;

  /// Sharpest-tile Laplacian variance below which a photo is too blurry.
  final double minSharpness;

  factory QualityThresholds.fromJson(Map<String, dynamic> json) =>
      QualityThresholds(
        minBrightness: (json['min_brightness'] as num).toDouble(),
        maxBrightness: (json['max_brightness'] as num).toDouble(),
        minSharpness: (json['min_sharpness'] as num).toDouble(),
      );
}

/// Everything the app needs to know about the bundled model.
///
/// Produced by `training/src/export_tflite.py`, so retraining never
/// requires changing Dart code.
class ModelMeta {
  const ModelMeta({
    required this.modelVersion,
    required this.architecture,
    required this.inputSize,
    required this.tConf,
    required this.tSpoil,
    required this.isDemo,
    required this.quality,
    required this.labels,
    this.notice,
  });

  final String modelVersion;
  final String architecture;
  final int inputSize;
  final double tConf;
  final double tSpoil;

  /// True for the untrained placeholder model; the UI shows a warning.
  final bool isDemo;

  /// Optional warning shown in a banner, e.g. for an interim model trained
  /// on non-Rwandan data.
  final String? notice;
  final QualityThresholds quality;
  final List<ClassLabel> labels;

  factory ModelMeta.fromJson(
    Map<String, dynamic> meta,
    List<dynamic> labelsJson,
  ) {
    final labels =
        labelsJson
            .map((e) => ClassLabel.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    for (var i = 0; i < labels.length; i++) {
      if (labels[i].index != i) {
        throw FormatException('labels.json indices must be 0..n-1');
      }
    }
    if (meta['input_range'] != '0_255') {
      throw FormatException(
        'Unsupported input_range ${meta['input_range']}; expected 0_255',
      );
    }
    return ModelMeta(
      modelVersion: meta['model_version'] as String,
      architecture: meta['architecture'] as String,
      inputSize: meta['input_size'] as int,
      tConf: (meta['t_conf'] as num).toDouble(),
      tSpoil: (meta['t_spoil'] as num).toDouble(),
      isDemo: meta['is_demo'] as bool? ?? false,
      notice: meta['notice'] as String?,
      quality: QualityThresholds.fromJson(
        meta['quality'] as Map<String, dynamic>,
      ),
      labels: labels,
    );
  }

  /// Index of the spoilage-risk class for [crop], or null if none.
  int? spoilageIndex(String crop) {
    for (final l in labels) {
      if (l.crop == crop && l.category == TriageCategory.spoilageRisk) {
        return l.index;
      }
    }
    return null;
  }
}
