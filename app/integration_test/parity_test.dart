// On-device check that the phone reproduces the evaluated pipeline.
//
//   flutter test integration_test/parity_test.dart -d <device>
//
// Fixtures come from training/tools/make_parity_fixtures.py and must be
// regenerated whenever the bundled model changes.
//
// PNG fixtures give both sides identical pixels, so preprocessing and the
// decision rule must match Python; the remaining difference (~0.02) comes
// from dynamic-range quantized kernels rounding differently on ARM and x86.
// JPEG fixtures follow the real camera path; Dart's and Pillow's JPEG
// decoders round a few pixels differently, so probabilities move a little
// more. In both cases the action shown must be identical. (The resize
// mismatch this test was written to catch moved probabilities by > 0.13.)

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harvestshelf/services/classifier_service.dart';
import 'package:harvestshelf/services/decision_mapper.dart';
import 'package:harvestshelf/services/preprocessing_service.dart';
import 'package:integration_test/integration_test.dart';

import 'parity_fixtures.dart';

const tolerance = {'png': 0.03, 'jpg': 0.10};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('phone matches Python on test photos', (tester) async {
    final meta = await ClassifierService.loadMeta(rootBundle);
    expect(meta.modelVersion, parityModelVersion,
        reason: 'regenerate parity_fixtures.dart for the bundled model');
    final classifier = await ClassifierService.load(meta);
    final mapper = DecisionMapper(meta);

    final maxDiff = {'png': 0.0, 'jpg': 0.0};
    final mismatches = <String>[];
    final times = <int>[];
    for (final f in parityFixtures) {
      final fmt = f['format'] as String;
      final bytes = Uint8List.fromList(base64Decode(f['data'] as String));
      final prepared = await prepareImage(bytes, meta.inputSize);
      final pred = await classifier.classify(prepared.input);
      times.add(pred.inferenceMs);
      final want = f['probs'] as List<double>;
      var diff = 0.0;
      for (var i = 0; i < want.length; i++) {
        final d = (pred.probabilities[i] - want[i]).abs();
        if (d > diff) diff = d;
      }
      if (diff > maxDiff[fmt]!) maxDiff[fmt] = diff;
      final got = mapper.map(pred.probabilities);
      if (got.category.id != f['category']) mismatches.add('${f['id']} ($fmt)');
      // ignore: avoid_print
      print('PARITY [$fmt] ${f['id']} true=${f['true']} python=${f['category']} '
          'phone=${got.category.id} diff=${diff.toStringAsFixed(4)} ${pred.inferenceMs} ms');
    }
    times.sort();
    // ignore: avoid_print
    print('PARITY SUMMARY fixtures=${parityFixtures.length} mismatched_actions=${mismatches.length} '
        'max_diff_png=${maxDiff['png']!.toStringAsFixed(4)} max_diff_jpg=${maxDiff['jpg']!.toStringAsFixed(4)} '
        'median_ms=${times[times.length ~/ 2]} max_ms=${times.last}');
    await classifier.close();

    expect(mismatches, isEmpty);
    for (final fmt in tolerance.keys) {
      expect(maxDiff[fmt], lessThan(tolerance[fmt]!), reason: fmt);
    }
  });
}
