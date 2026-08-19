import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:compact_games/core/utils/cover_art_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Encodes a [size]-square PNG filled with [color].
Future<Uint8List> _png(Color color, {int size = 40}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// A transparent field with one small opaque mark, like a sparse icon.
Future<Uint8List> _pngWithSpeck({int size = 40}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(4, 4, 8, 8),
    Paint()..color = const Color(0xFFFFAA00),
  );
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('imageHasVisiblePixels', () {
    test('a fully transparent icon has nothing to show', () async {
      // This is the shape an executable with no icon resource extracts to: a
      // valid PNG of the right size that paints nothing at all. It used to be
      // cached as a successful cover, leaving a permanently blank card with no
      // placeholder behind it.
      expect(
        await imageHasVisiblePixels(await _png(const Color(0x00000000))),
        isFalse,
      );
    });

    test('a solid cover is visible', () async {
      expect(
        await imageHasVisiblePixels(await _png(const Color(0xFF3E7BB8))),
        isTrue,
      );
    });

    test('a mostly empty icon with one mark still counts as visible', () async {
      // The probe downscales, so a small opaque area must survive the resize
      // rather than being averaged away into transparency.
      expect(await imageHasVisiblePixels(await _pngWithSpeck()), isTrue);
    });

    test('a nearly invisible wash is treated as blank', () async {
      expect(
        await imageHasVisiblePixels(await _png(const Color(0x03FFFFFF))),
        isFalse,
      );
    });

    test('bytes that are not an image are left to the image widget', () async {
      // Undecodable is not the same as blank: the widget's error path already
      // falls back to the placeholder, and guessing here would evict a cover
      // that a later decode might have handled.
      expect(
        await imageHasVisiblePixels(Uint8List.fromList(<int>[1, 2, 3, 4])),
        isTrue,
      );
    });
  });
}
