import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harvestshelf/models/model_meta.dart';
import 'package:harvestshelf/services/decision_mapper.dart';

/// Runs the same cases as training/tests/test_decision.py.
void main() {
  final shared =
      jsonDecode(File('../shared/decision_cases.json').readAsStringSync())
          as Map<String, dynamic>;

  final meta = ModelMeta.fromJson({
    'model_version': 'test',
    'architecture': 'test',
    'input_size': 224,
    'input_range': '0_255',
    't_conf': shared['t_conf'],
    't_spoil': shared['t_spoil'],
    'quality': {
      'min_brightness': 40,
      'max_brightness': 235,
      'min_sharpness': 80,
    },
  }, shared['labels'] as List<dynamic>);
  final mapper = DecisionMapper(meta);

  for (final c in (shared['cases'] as List).cast<Map<String, dynamic>>()) {
    test(c['name'], () {
      final probs = (c['probs'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
      final want = c['expected'] as Map<String, dynamic>;
      final got = mapper.map(probs);
      expect(got.category.id, want['category']);
      expect(got.crop, want['crop']);
      expect(got.reason.id, want['reason']);
      expect(
        got.confidence,
        closeTo((want['confidence'] as num).toDouble(), 1e-9),
      );
    });
  }

  test('rejects wrong number of probabilities', () {
    expect(() => mapper.map([1.0]), throwsArgumentError);
  });
}
