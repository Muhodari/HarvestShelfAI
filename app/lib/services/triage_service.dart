import 'package:flutter/foundation.dart';

import '../data/repositories.dart';
import '../models/category.dart';
import '../models/model_meta.dart';
import '../models/scan.dart';
import '../models/triage_result.dart';
import 'decision_mapper.dart';
import 'preprocessing_service.dart';

typedef ClassifyFn =
    Future<Prediction> Function(List<List<List<List<double>>>> input);
typedef PrepareFn =
    Future<PreparedImage> Function(Uint8List bytes, int inputSize);
typedef SaveThumbnailFn = Future<String?> Function(Uint8List jpg);

/// A finished scan: what to show and what was stored.
class TriageOutcome {
  const TriageOutcome({required this.result, required this.scan, this.rule});

  final TriageResult result;
  final Scan scan;
  final GuidanceRule? rule;
}

/// Photo in, saved scan out:
/// prepare -> quality check -> classify -> map -> look up advice -> save.
/// Nothing here touches the network (NFR1, NFR5).
class TriageService {
  TriageService({
    required this.meta,
    required this.classify,
    required this.scans,
    required this.guidance,
    this.prepare = prepareImage,
    this.saveThumbnail,
    DateTime Function()? clock,
  }) : _mapper = DecisionMapper(meta),
       _clock = clock ?? DateTime.now;

  final ModelMeta meta;
  final ClassifyFn classify;
  final PrepareFn prepare;
  final ScanRepository scans;
  final GuidanceRepository guidance;
  final SaveThumbnailFn? saveThumbnail;
  final DecisionMapper _mapper;
  final DateTime Function() _clock;

  /// Incremented after every saved scan so history views can refresh.
  final changes = ValueNotifier<int>(0);

  /// Analyses [photoBytes] and saves the scan for [userId].
  Future<TriageOutcome> triage(
    Uint8List photoBytes, {
    required int userId,
  }) async {
    final prepared = await prepare(photoBytes, meta.inputSize);

    final TriageResult result;
    final failure = prepared.quality.failure(meta.quality);
    if (failure != null) {
      result = TriageResult(
        category: TriageCategory.uncertain,
        crop: null,
        confidence: 0,
        reason: failure,
      );
    } else {
      final prediction = await classify(prepared.input);
      result = _mapper
          .map(prediction.probabilities)
          .withInferenceMs(prediction.inferenceMs);
    }

    final rule = await guidance.ruleFor(result.crop, result.category);
    final imagePath = await saveThumbnail?.call(prepared.thumbnailJpg);

    final scan = Scan(
      crop: result.crop,
      category: result.category,
      confidence: result.confidence,
      reason: result.reason,
      inferenceMs: result.inferenceMs,
      modelVersion: meta.modelVersion,
      createdAt: _clock(),
      imagePath: imagePath,
      ruleId: rule?.id,
      userId: userId,
    );
    final id = await scans.insert(scan);
    changes.value++;

    return TriageOutcome(
      result: result,
      scan: Scan.fromMap({...scan.toMap(), 'id': id}),
      rule: rule,
    );
  }
}
