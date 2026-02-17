import 'dart:io';

import 'package:flutter/painting.dart';

import '../../services/cover_art_service.dart';

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
    return FileImage(File.fromUri(uri));
  }
  if (uri.isScheme('http') || uri.isScheme('https')) {
    return NetworkImage(uriText);
  }
  return null;
}
