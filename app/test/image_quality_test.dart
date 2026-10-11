import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harvestshelf/models/category.dart';
import 'package:harvestshelf/models/model_meta.dart';
import 'package:harvestshelf/services/image_quality_service.dart';
import 'package:image/image.dart' as img;

void main() {
  const t = QualityThresholds();

  img.Image solid(int v) =>
      img.Image(width: 300, height: 200)..clear(img.ColorRgb8(v, v, v));

  img.Image checkerboard() {
    final im = img.Image(width: 300, height: 200);
    for (final p in im) {
      final on = ((p.x ~/ 4) + (p.y ~/ 4)).isEven;
      p
        ..r = on ? 200 : 60
        ..g = on ? 200 : 60
        ..b = on ? 200 : 60;
    }
    return im;
  }

  test('black image is too dark', () {
    final q = assessQuality(solid(5));
    expect(q.brightness, closeTo(5, 0.5));
    expect(q.failure(t), DecisionReason.tooDark);
  });

  test('white image is too bright', () {
    expect(assessQuality(solid(250)).failure(t), DecisionReason.tooBright);
  });

  test('flat grey image has no detail and counts as blurry', () {
    final q = assessQuality(solid(128));
    expect(q.sharpness, closeTo(0, 1e-6));
    expect(q.failure(t), DecisionReason.blurry);
  });

  test('high-contrast pattern passes', () {
    final q = assessQuality(checkerboard());
    expect(q.sharpness, greaterThan(t.minSharpness));
    expect(q.failure(t), isNull);
  });

  test('blurring lowers sharpness', () {
    final sharp = assessQuality(checkerboard()).sharpness;
    final blurred = assessQuality(
      img.gaussianBlur(checkerboard(), radius: 6),
    ).sharpness;
    expect(blurred, lessThan(sharp / 10));
  });

  group('matches Python (shared/quality_cases.json)', () {
    final shared =
        jsonDecode(File('../shared/quality_cases.json').readAsStringSync())
            as Map<String, dynamic>;
    final th = QualityThresholds.fromJson(
      shared['thresholds'] as Map<String, dynamic>,
    );
    for (final c in (shared['cases'] as List).cast<Map<String, dynamic>>()) {
      test(c['file'], () {
        final im = img.decodePng(
          File('../shared/quality_fixtures/${c['file']}').readAsBytesSync(),
        )!;
        final q = assessQuality(im);
        expect(
          q.brightness,
          closeTo((c['brightness'] as num).toDouble(), 1e-6),
        );
        expect(q.sharpness, closeTo((c['sharpness'] as num).toDouble(), 1e-4));
        expect(q.failure(th)?.id, c['failure']);
      });
    }
  });
}
