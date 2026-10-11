import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'image_quality_service.dart';
import 'resize.dart';

/// Output of [prepareImage]: the model input plus what is needed to save it.
class PreparedImage {
  const PreparedImage({
    required this.input,
    required this.quality,
    required this.thumbnailJpg,
  });

  /// Shape [1, size, size, 3], RGB values in 0-255 (the model rescales
  /// internally, see `training/src/models.py`).
  final List<List<List<List<double>>>> input;
  final QualityReport quality;

  /// Small JPEG kept for the history screen.
  final Uint8List thumbnailJpg;
}

class _Request {
  const _Request(this.bytes, this.inputSize);
  final Uint8List bytes;
  final int inputSize;
}

/// Decodes, checks and resizes a photo on a background isolate so the UI
/// stays responsive.
Future<PreparedImage> prepareImage(Uint8List bytes, int inputSize) =>
    compute(_prepare, _Request(bytes, inputSize));

PreparedImage _prepare(_Request r) {
  final decoded = img.decodeImage(r.bytes);
  if (decoded == null) {
    throw const FormatException('Could not decode image');
  }
  final image = img.bakeOrientation(decoded);
  final quality = assessQuality(image);

  // Centre square crop then box resize, matching tools/make_parity_fixtures.py
  // and the Pillow BOX resize used to prepare training images.
  final square = cropSquareAndResize(image, r.inputSize);

  final input = List.generate(
    1,
    (_) => List.generate(
      r.inputSize,
      (y) => List.generate(r.inputSize, (x) {
        final p = square.getPixel(x, y);
        return [p.r.toDouble(), p.g.toDouble(), p.b.toDouble()];
      }),
    ),
  );

  return PreparedImage(
    input: input,
    quality: quality,
    thumbnailJpg: img.encodeJpg(square, quality: 80),
  );
}
