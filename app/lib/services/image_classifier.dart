import '../models/triage_result.dart';

/// What the triage pipeline needs from a model: an RGB 0-255 image tensor in,
/// one probability per class out.
///
/// [TriageService] depends on this interface, not on TensorFlow Lite, so the
/// model runtime can be swapped (the app uses [ClassifierService]; tests use
/// a fixed fake) without touching the pipeline.
abstract interface class ImageClassifier {
  Future<Prediction> classify(List<List<List<List<double>>>> input);
}
