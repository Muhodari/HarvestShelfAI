import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Box-filter (area) resize that reproduces Pillow's `Image.BOX`, which the
/// training pipeline uses. The `image` package's own `average` resize
/// differs from it by up to ~90 grey levels at edges, enough to shift model
/// probabilities, so the app does not rely on it.
///
/// Like Pillow: separable passes (horizontal then vertical), each output
/// pixel averages the source pixels whose centres fall inside its box, and
/// the intermediate result is rounded to 8 bits.
img.Image boxResize(img.Image src, int width, int height) {
  final sw = src.width, sh = src.height;
  final rgb = Uint8List(sw * sh * 3);
  var k = 0;
  for (final p in src) {
    rgb[k++] = p.r.toInt();
    rgb[k++] = p.g.toInt();
    rgb[k++] = p.b.toInt();
  }

  // Horizontal pass: sh rows x width columns.
  final xb = _bounds(sw, width);
  final tmp = Uint8List(sh * width * 3);
  for (var y = 0; y < sh; y++) {
    final row = y * sw * 3;
    for (var x = 0; x < width; x++) {
      final lo = xb[2 * x], hi = xb[2 * x + 1];
      var r = 0, g = 0, b = 0;
      for (var i = lo; i < hi; i++) {
        final o = row + i * 3;
        r += rgb[o];
        g += rgb[o + 1];
        b += rgb[o + 2];
      }
      final n = hi - lo;
      final o = (y * width + x) * 3;
      tmp[o] = _div(r, n);
      tmp[o + 1] = _div(g, n);
      tmp[o + 2] = _div(b, n);
    }
  }

  // Vertical pass.
  final yb = _bounds(sh, height);
  final out = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    final lo = yb[2 * y], hi = yb[2 * y + 1];
    final n = hi - lo;
    for (var x = 0; x < width; x++) {
      var r = 0, g = 0, b = 0;
      for (var j = lo; j < hi; j++) {
        final o = (j * width + x) * 3;
        r += tmp[o];
        g += tmp[o + 1];
        b += tmp[o + 2];
      }
      out.setPixelRgb(x, y, _div(r, n), _div(g, n), _div(b, n));
    }
  }
  return out;
}

/// Centre square crop, then [boxResize] to [size] x [size].
img.Image cropSquareAndResize(img.Image src, int size) {
  final s = src.width < src.height ? src.width : src.height;
  final square = img.copyCrop(
    src,
    x: (src.width - s) ~/ 2,
    y: (src.height - s) ~/ 2,
    width: s,
    height: s,
  );
  return boxResize(square, size, size);
}

/// For each output index, the [lo, hi) range of source pixels whose centres
/// lie in its box (Pillow's precompute_coeffs with the box filter).
Int32List _bounds(int inSize, int outSize) {
  final scale = inSize / outSize;
  final support = scale < 1 ? 0.5 : 0.5 * scale;
  final res = Int32List(outSize * 2);
  for (var i = 0; i < outSize; i++) {
    final center = (i + 0.5) * scale;
    var lo = (center - support + 0.5).floor();
    var hi = (center + support + 0.5).floor();
    if (lo < 0) lo = 0;
    if (hi > inSize) hi = inSize;
    // Box filter: keep pixels with -0.5 < (j + 0.5 - center) / scale' <= 0.5
    // (Pillow's box_filter; the boundary matters at ratios such as 1.5),
    // where scale' = max(scale, 1).
    final ss = scale < 1 ? 1.0 : scale;
    while (lo < hi && (lo + 0.5 - center) / ss <= -0.5) {
      lo++;
    }
    while (hi > lo && (hi - 1 + 0.5 - center) / ss > 0.5) {
      hi--;
    }
    res[2 * i] = lo;
    res[2 * i + 1] = hi;
  }
  return res;
}

int _div(int sum, int n) {
  final v = (sum / n).round();
  return v > 255 ? 255 : v;
}
