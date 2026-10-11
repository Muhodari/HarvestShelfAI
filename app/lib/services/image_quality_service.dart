import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/category.dart';
import '../models/model_meta.dart';
import 'resize.dart';

/// Sharpness is the Laplacian variance of the sharpest tile in a
/// [qualityTiles] x [qualityTiles] grid (same as training/src/quality.py).
/// The whole-image variance wrongly rejected 43% of in-focus tomato photos:
/// a smooth fruit on a plain cloth has few edges overall, but a crisp outline.
const qualityTiles = 4;

/// Width the photo is reduced to before measuring quality.
/// `training/src/quality.py` uses the same value so thresholds tuned on the
/// dataset apply on the phone.
const qualityWidth = 256;

class QualityReport {
  const QualityReport({required this.brightness, required this.sharpness});

  /// Mean luminance, 0-255.
  final double brightness;

  /// Variance of the 4-neighbour Laplacian of the luminance image.
  final double sharpness;

  /// The reason the photo is rejected, or null if it is usable (FR2).
  DecisionReason? failure(QualityThresholds t) {
    if (brightness < t.minBrightness) return DecisionReason.tooDark;
    if (brightness > t.maxBrightness) return DecisionReason.tooBright;
    if (sharpness < t.minSharpness) return DecisionReason.blurry;
    return null;
  }
}

/// Measures brightness and sharpness of [image].
QualityReport assessQuality(img.Image image) {
  final small = image.width > qualityWidth
      ? boxResize(
          image,
          qualityWidth,
          (image.height * qualityWidth / image.width).round(),
        )
      : image;
  final w = small.width;
  final h = small.height;

  final gray = List<double>.filled(w * h, 0);
  var sum = 0.0;
  for (final p in small) {
    final y = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    gray[p.y * w + p.x] = y.toDouble();
    sum += y;
  }
  final brightness = sum / (w * h);

  if (w < 3 || h < 3) {
    return QualityReport(brightness: brightness, sharpness: 0);
  }

  // Laplacian of the interior pixels, (h - 2) x (w - 2).
  final lw = w - 2, lh = h - 2;
  final lap = Float64List(lw * lh);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      lap[(y - 1) * lw + (x - 1)] =
          4 * gray[i] - gray[i - 1] - gray[i + 1] - gray[i - w] - gray[i + w];
    }
  }
  final sharpness = sharpestTileVariance(lap, lw, lh);
  return QualityReport(brightness: brightness, sharpness: sharpness);
}

/// Population variance of the sharpest tile; whole-image variance when the
/// image is too small to tile.
double sharpestTileVariance(
  Float64List lap,
  int w,
  int h, {
  int tiles = qualityTiles,
}) {
  double variance(int x0, int y0, int tw, int th) {
    var sum = 0.0, sq = 0.0;
    for (var y = y0; y < y0 + th; y++) {
      for (var x = x0; x < x0 + tw; x++) {
        final v = lap[y * w + x];
        sum += v;
        sq += v * v;
      }
    }
    final n = tw * th;
    final mean = sum / n;
    return sq / n - mean * mean;
  }

  final th = h ~/ tiles, tw = w ~/ tiles;
  if (th == 0 || tw == 0) return variance(0, 0, w, h);
  var best = 0.0;
  for (var i = 0; i < tiles; i++) {
    for (var j = 0; j < tiles; j++) {
      final v = variance(j * tw, i * th, tw, th);
      if (v > best) best = v;
    }
  }
  return best;
}
