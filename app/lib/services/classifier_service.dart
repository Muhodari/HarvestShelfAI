import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/constants.dart';
import '../models/model_meta.dart';
import '../models/triage_result.dart';

/// Runs the bundled TensorFlow Lite model on the phone (FR3).
class ClassifierService {
  ClassifierService._(this.meta, this._interpreter, this._isolate);

  final ModelMeta meta;
  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;

  static Future<ModelMeta> loadMeta(AssetBundle bundle) async {
    final meta =
        jsonDecode(await bundle.loadString(Assets.modelMeta))
            as Map<String, dynamic>;
    final labels =
        jsonDecode(await bundle.loadString(Assets.labels)) as List<dynamic>;
    return ModelMeta.fromJson(meta, labels);
  }

  static Future<ClassifierService> load(ModelMeta meta) async {
    final options = InterpreterOptions()..threads = 4;
    final interpreter = await Interpreter.fromAsset(
      Assets.model,
      options: options,
    );

    final inShape = interpreter.getInputTensor(0).shape;
    final outShape = interpreter.getOutputTensor(0).shape;
    final expectedIn = [1, meta.inputSize, meta.inputSize, 3];
    if (!_listEquals(inShape, expectedIn) ||
        outShape.last != meta.labels.length) {
      interpreter.close();
      throw StateError(
        'Model shape $inShape -> $outShape does not match '
        'model_meta.json ($expectedIn -> ${meta.labels.length})',
      );
    }

    final isolate = await IsolateInterpreter.create(
      address: interpreter.address,
    );
    return ClassifierService._(meta, interpreter, isolate);
  }

  Future<Prediction> classify(List<List<List<List<double>>>> input) async {
    final output = [List<double>.filled(meta.labels.length, 0)];
    final sw = Stopwatch()..start();
    await _isolate.run(input, output);
    sw.stop();
    return Prediction(
      probabilities: List<double>.from(output.first),
      inferenceMs: sw.elapsedMilliseconds,
    );
  }

  Future<void> close() async {
    await _isolate.close();
    _interpreter.close();
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
