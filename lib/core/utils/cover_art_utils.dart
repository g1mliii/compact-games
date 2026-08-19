import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../services/cover_art_service.dart';

/// How art from [source] wants to be drawn.
///
/// Locally-derived art is a small square tile — an extracted executable icon or
/// the logo a packaged app declares — so it is centred on a plate rather than
/// stretched across the cover the way a store capsule is.
CoverArtType? coverArtTypeFromSource(CoverArtSource source) {
  return isLocallyDerivedCoverSource(source) ? CoverArtType.icon : null;
}

/// Whether art from [source] was produced from files on this machine rather
/// than fetched from a catalog.
///
/// These are the sources that can decode to a perfectly transparent image, so
/// they are the ones worth probing for visible pixels.
bool isLocallyDerivedCoverSource(CoverArtSource source) {
  return source == CoverArtSource.exeIcon ||
      source == CoverArtSource.packagedAppLogo;
}

ImageProvider<Object>? imageProviderFromCover(CoverArtResult? result) {
  final uriText = result?.uri;
  if (uriText == null || uriText.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(uriText);
  if (uri == null) {
    return null;
  }
  if (uri.isScheme('file')) {
    return RevisionedFileImage(
      File.fromUri(uri),
      revision: result?.revision ?? 0,
    );
  }
  if (uri.isScheme('http') || uri.isScheme('https')) {
    return NetworkImage(uriText);
  }
  return null;
}

/// [provider] set to decode at the size it will actually be painted.
///
/// A Steam library capsule is 600x900; painting one straight into a 30px row
/// thumbnail decodes the full image and holds ~2MB of RGBA in the image cache
/// for something that needs a few kilobytes. Widths are bucketed to 32px so a
/// handful of layouts share cache entries instead of each claiming its own, and
/// the result is clamped: below the floor the art turns to mush on a HiDPI
/// screen, and above the ceiling there is nothing left to gain.
ImageProvider<Object> coverDecodedFor(
  ImageProvider<Object> provider, {
  required BuildContext context,
  required double logicalWidth,
}) {
  final raw = logicalWidth * MediaQuery.devicePixelRatioOf(context);
  final bucketed = ((raw / 32).ceil() * 32).clamp(64, 640);
  return ResizeImage(provider, width: bucketed);
}

class RevisionedFileImage extends FileImage {
  const RevisionedFileImage(super.file, {required this.revision, super.scale});

  final int revision;

  @override
  bool operator ==(Object other) {
    return other is RevisionedFileImage &&
        other.file.path == file.path &&
        other.scale == scale &&
        other.revision == revision;
  }

  @override
  int get hashCode => Object.hash(file.path, scale, revision);
}

/// Whether [bytes] decode to an image with any pixel the user would see.
///
/// Extracted executable icons are the reason this exists: an executable with no
/// icon resource still yields a perfectly valid, perfectly transparent PNG. It
/// passes every size and decode check and then paints nothing, which looks
/// exactly like a broken card — and worse, it is cached as a successful cover,
/// so the placeholder never gets its turn.
///
/// Decoded at [_alphaProbeExtent] square, so the codec does the downscaling and
/// this never walks the original pixels. Anything undecodable is reported as
/// visible: that is the image widget's error path to handle, not this one's.
Future<bool> imageHasVisiblePixels(Uint8List bytes) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: _alphaProbeExtent,
      targetHeight: _alphaProbeExtent,
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      return true;
    }
    final rgba = data.buffer.asUint8List();
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] > _minVisibleAlpha) {
        return true;
      }
    }
    return false;
  } catch (_) {
    return true;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

/// Size the alpha probe decodes to. Big enough that a small mark in one corner
/// still lands on a sampled pixel, small enough to be free.
const int _alphaProbeExtent = 16;

/// Alpha at or below this is not something the user can see against the tile.
const int _minVisibleAlpha = 8;
