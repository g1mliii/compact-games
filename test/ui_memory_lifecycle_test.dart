import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compact_games/core/performance/ui_memory_lifecycle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UiMemoryLifecycle.configureImageCache', () {
    test('sets the documented 50MB / 300 entry caps', () {
      final imageCache = PaintingBinding.instance.imageCache;
      // Scribble over the caps to prove configureImageCache sets them back.
      imageCache.maximumSizeBytes = 1;
      imageCache.maximumSize = 1;

      UiMemoryLifecycle.configureImageCache();

      expect(imageCache.maximumSizeBytes, 50 * 1024 * 1024);
      expect(imageCache.maximumSize, 300);
      expect(UiMemoryLifecycle.imageCacheMaxBytes, 50 * 1024 * 1024);
      expect(UiMemoryLifecycle.imageCacheMaxEntries, 300);
    });
  });

  group('UiMemoryLifecycle.trim', () {
    setUp(() {
      UiMemoryLifecycle.configureImageCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });

    tearDown(() {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });

    test('background level keeps cached images (clears live only)', () async {
      final imageCache = PaintingBinding.instance.imageCache;
      await _populateImageCache(imageCache, count: 3);
      final populated = imageCache.currentSize;
      expect(populated, greaterThan(0));

      UiMemoryLifecycle.trim(UiMemoryTrimLevel.background);

      // background only calls clearLiveImages() — cached entries stay.
      expect(imageCache.currentSize, populated);
    });

    test('trayHide level clears cache and live images', () async {
      final imageCache = PaintingBinding.instance.imageCache;
      await _populateImageCache(imageCache, count: 3);
      expect(imageCache.currentSize, greaterThan(0));

      UiMemoryLifecycle.trim(UiMemoryTrimLevel.trayHide);

      expect(imageCache.currentSize, 0);
      expect(imageCache.liveImageCount, 0);
    });

    test('pressure level clears cache and live images', () async {
      final imageCache = PaintingBinding.instance.imageCache;
      await _populateImageCache(imageCache, count: 3);
      expect(imageCache.currentSize, greaterThan(0));

      UiMemoryLifecycle.trim(UiMemoryTrimLevel.pressure);

      expect(imageCache.currentSize, 0);
      expect(imageCache.liveImageCount, 0);
    });

    test('shutdown level clears cache and live images', () async {
      final imageCache = PaintingBinding.instance.imageCache;
      await _populateImageCache(imageCache, count: 3);
      expect(imageCache.currentSize, greaterThan(0));

      UiMemoryLifecycle.trim(UiMemoryTrimLevel.shutdown);

      expect(imageCache.currentSize, 0);
      expect(imageCache.liveImageCount, 0);
    });
  });
}

/// Populates Flutter's [ImageCache] with [count] synthetic 1x1 images so that
/// trim assertions have something concrete to clear.
Future<void> _populateImageCache(
  ImageCache imageCache, {
  required int count,
}) async {
  for (var i = 0; i < count; i++) {
    final image = await _makeOnePixelImage();
    imageCache.putIfAbsent(
      _FakeImageKey(i),
      () => _ImmediateImageStreamCompleter(image),
    );
  }
}

Future<ui.Image> _makeOnePixelImage() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
  return recorder.endRecording().toImage(1, 1);
}

class _FakeImageKey {
  const _FakeImageKey(this.id);
  final int id;

  @override
  bool operator ==(Object other) => other is _FakeImageKey && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class _ImmediateImageStreamCompleter extends ImageStreamCompleter {
  _ImmediateImageStreamCompleter(ui.Image image) {
    setImage(ImageInfo(image: image));
  }
}
