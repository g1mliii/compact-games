import 'dart:io';

import 'package:flutter/painting.dart';

import '../../services/cover_art_service.dart';

CoverArtType? coverArtTypeFromSource(CoverArtSource source) {
  return source == CoverArtSource.exeIcon ? CoverArtType.icon : null;
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
