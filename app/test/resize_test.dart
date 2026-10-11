import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harvestshelf/services/resize.dart';
import 'package:image/image.dart' as img;

/// The app must resize exactly like Pillow's BOX filter, which prepared the
/// training images. Expected outputs were made with
/// `Image.resize((w, h), Image.BOX)` in Pillow 10.4.
void main() {
  for (final (name, w, h) in [
    ('rand_a', 23, 17),
    ('rand_d', 64, 50),
    ('rand_e', 256, 256), // 1.5x: pixel centres fall exactly on box edges
    ('rand_f', 200, 300),
  ]) {
    test('boxResize matches Pillow BOX ($name -> ${w}x$h)', () {
      final src = img.decodePng(
        File('test/fixtures/resize_${name}_src.png').readAsBytesSync(),
      )!;
      final want = img.decodePng(
        File('test/fixtures/resize_${name}_pillow.png').readAsBytesSync(),
      )!;
      final got = boxResize(src, w, h);
      expect(got.width, w);
      expect(got.height, h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final a = got.getPixel(x, y), b = want.getPixel(x, y);
          expect([a.r, a.g, a.b], [b.r, b.g, b.b], reason: 'pixel ($x, $y)');
        }
      }
    });
  }

  test('cropSquareAndResize takes the centre square', () {
    final im = img.Image(width: 30, height: 10)..clear(img.ColorRgb8(0, 0, 0));
    img.fillRect(
      im,
      x1: 10,
      y1: 0,
      x2: 19,
      y2: 9,
      color: img.ColorRgb8(255, 255, 255),
    );
    final out = cropSquareAndResize(im, 5);
    expect(out.width, 5);
    for (final p in out) {
      expect(p.r, 255);
    }
  });
}
