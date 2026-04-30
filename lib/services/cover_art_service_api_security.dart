part of 'cover_art_service.dart';

final RegExp _ipv4HostPattern = RegExp(
  r'^(?:\d{1,3}\.){3}\d{1,3}$',
  caseSensitive: false,
);

extension _CoverArtServiceApiSecurity on CoverArtService {
  Future<_BoundedImageResponse?> _sendStrictImageGetWithRetries({
    required Uri uri,
    required Duration timeout,
    required Map<String, String> headers,
  }) {
    return _withApiRetries<_BoundedImageResponse?>(() async {
      final _BoundedImageResponse response;
      try {
        response = await _withApiPermit(
          () =>
              _sendGetNoRedirect(uri: uri, timeout: timeout, headers: headers),
        );
      } on _ImageTooLargeException {
        return null;
      }
      if (response.statusCode == 429 || response.statusCode >= 500) {
        throw const _RetryableApiException();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      return response;
    });
  }

  Future<_BoundedImageResponse> _sendGetNoRedirect({
    required Uri uri,
    required Duration timeout,
    required Map<String, String> headers,
  }) async {
    final request = http.Request('GET', uri)
      ..headers.addAll(headers)
      ..followRedirects = false
      ..maxRedirects = 0;
    final streamed = await _getCoverArtApiHttpClient()
        .send(request)
        .timeout(timeout);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      await _cancelResponseBody(streamed.stream);
      return _BoundedImageResponse(
        statusCode: streamed.statusCode,
        headers: streamed.headers,
        bodyBytes: Uint8List(0),
      );
    }

    final declaredLength = int.tryParse(
      streamed.headers['content-length'] ?? '',
    );
    if (declaredLength != null && declaredLength > _maxDownloadedImageBytes) {
      await _cancelResponseBody(streamed.stream);
      throw const _ImageTooLargeException();
    }

    final bodyBytes = await _readBoundedResponseBody(
      streamed.stream,
      timeout: timeout,
    );
    return _BoundedImageResponse(
      statusCode: streamed.statusCode,
      headers: streamed.headers,
      bodyBytes: bodyBytes,
    );
  }

  Future<Uint8List> _readBoundedResponseBody(
    Stream<List<int>> stream, {
    required Duration timeout,
  }) async {
    final builder = BytesBuilder(copy: false);
    var totalBytes = 0;
    await for (final chunk in stream.timeout(timeout)) {
      totalBytes += chunk.length;
      if (totalBytes > _maxDownloadedImageBytes) {
        throw const _ImageTooLargeException();
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<void> _cancelResponseBody(Stream<List<int>> stream) async {
    final subscription = stream.listen((_) {});
    await subscription.cancel();
  }

  bool _isTrustedSteamGridImageUri(Uri uri) {
    if (!uri.hasScheme || uri.scheme.toLowerCase() != 'https') {
      return false;
    }

    final host = uri.host.toLowerCase();
    if (host.isEmpty ||
        host == 'localhost' ||
        _ipv4HostPattern.hasMatch(host)) {
      return false;
    }

    return host == 'steamgriddb.com' || host.endsWith('.steamgriddb.com');
  }
}

class _BoundedImageResponse {
  const _BoundedImageResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bodyBytes;
}

class _ImageTooLargeException implements Exception {
  const _ImageTooLargeException();
}
