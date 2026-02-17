part of 'cover_art_service.dart';

const int _preferredCoverMinWidth = 300;
const int _preferredCoverMinHeight = 450;
const double _preferredCoverAspectMin = 0.62;
const double _preferredCoverAspectMax = 0.72;
const int _imageHeaderMaxReadBytes = 512 * 1024;

const Set<int> _jpegSofMarkers = <int>{
  0xC0,
  0xC1,
  0xC2,
  0xC3,
  0xC5,
  0xC6,
  0xC7,
  0xC9,
  0xCA,
  0xCB,
  0xCD,
  0xCE,
  0xCF,
};

extension _CoverArtServiceQuality on CoverArtService {
  Future<bool> _needsApiUpgradeForCached(
    CoverArtResult cached, {
    required String? apiKey,
  }) async {
    if (!_isApiEnabled(apiKey)) {
      return false;
    }
    final localPath = _filePathFromUri(cached.uri);
    if (localPath == null) {
      return false;
    }
    return !(await _isPreferredPortraitCover(localPath));
  }

  Future<bool> _needsApiUpgradeForPath(
    String localPath, {
    required String? apiKey,
  }) async {
    if (!_isApiEnabled(apiKey)) {
      return false;
    }
    return !(await _isPreferredPortraitCover(localPath));
  }

  bool _isApiEnabled(String? apiKey) {
    final normalized = apiKey?.trim();
    return normalized != null && normalized.isNotEmpty;
  }

  String? _filePathFromUri(String? uriText) {
    if (uriText == null || uriText.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(uriText);
    if (uri == null || !uri.isScheme('file')) {
      return null;
    }
    try {
      return uri.toFilePath();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isPreferredPortraitCover(String path) async {
    final cacheKey = path.toLowerCase();
    final cached = CoverArtService._coverQualityPathCache.remove(cacheKey);
    if (cached != null) {
      CoverArtService._coverQualityPathCache[cacheKey] = cached;
      return cached;
    }

    var preferred = false;
    final lowerName = p.basename(path).toLowerCase();
    if (lowerName.contains('600x900')) {
      preferred = true;
    } else {
      final size = await _readImageSize(path);
      if (size != null) {
        preferred = _isPreferredPortraitSize(size.width, size.height);
      }
    }

    CoverArtService._coverQualityPathCache[cacheKey] = preferred;
    CoverArtService._trimLru(
      CoverArtService._coverQualityPathCache,
      CoverArtService._maxCoverQualityCacheEntries,
    );
    return preferred;
  }

  bool _isPreferredPortraitSize(int width, int height) {
    if (width < _preferredCoverMinWidth || height < _preferredCoverMinHeight) {
      return false;
    }
    if (height <= width) {
      return false;
    }
    final aspect = width / height;
    return aspect >= _preferredCoverAspectMin &&
        aspect <= _preferredCoverAspectMax;
  }

  Future<({int width, int height})?> _readImageSize(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }

    final bytes = await _readImageHeaderBytes(file);
    if (bytes.length < 24) {
      return null;
    }

    final png = _tryReadPngSize(bytes);
    if (png != null) {
      return png;
    }
    return _tryReadJpegSize(bytes);
  }

  Future<List<int>> _readImageHeaderBytes(File file) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, _imageHeaderMaxReadBytes)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  ({int width, int height})? _tryReadPngSize(List<int> bytes) {
    if (bytes.length < 24) {
      return null;
    }
    if (bytes[0] != 0x89 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x4E ||
        bytes[3] != 0x47) {
      return null;
    }
    final width = _readUint32BE(bytes, 16);
    final height = _readUint32BE(bytes, 20);
    if (width <= 0 || height <= 0) {
      return null;
    }
    return (width: width, height: height);
  }

  ({int width, int height})? _tryReadJpegSize(List<int> bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return null;
    }

    var index = 2;
    while (index + 8 < bytes.length) {
      if (bytes[index] != 0xFF) {
        index++;
        continue;
      }

      final marker = bytes[index + 1];
      if (marker == 0xFF) {
        index++;
        continue;
      }
      if (marker == 0xD8 ||
          marker == 0xD9 ||
          (marker >= 0xD0 && marker <= 0xD7) ||
          marker == 0x01) {
        index += 2;
        continue;
      }

      if (index + 3 >= bytes.length) {
        return null;
      }
      final segmentLength = (bytes[index + 2] << 8) | bytes[index + 3];
      if (segmentLength < 2) {
        return null;
      }

      if (_jpegSofMarkers.contains(marker)) {
        if (index + 8 >= bytes.length) {
          return null;
        }
        final height = (bytes[index + 5] << 8) | bytes[index + 6];
        final width = (bytes[index + 7] << 8) | bytes[index + 8];
        if (width <= 0 || height <= 0) {
          return null;
        }
        return (width: width, height: height);
      }

      index += 2 + segmentLength;
    }
    return null;
  }

  int _readUint32BE(List<int> bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }
}
