part of 'cover_art_service.dart';

final RegExp _ipv4HostPattern = RegExp(
  r'^(?:\d{1,3}\.){3}\d{1,3}$',
  caseSensitive: false,
);

extension _CoverArtServiceApiSecurity on CoverArtService {
  Future<http.Response?> _sendStrictImageGetWithRetries({
    required Uri uri,
    required Duration timeout,
    required Map<String, String> headers,
  }) {
    return _withApiRetries<http.Response>(() async {
      final response = await _withApiPermit(
        () => _sendGetNoRedirect(uri: uri, timeout: timeout, headers: headers),
      );
      if (response.statusCode == 429 || response.statusCode >= 500) {
        throw const _RetryableApiException();
      }
      return response;
    });
  }

  Future<http.Response> _sendGetNoRedirect({
    required Uri uri,
    required Duration timeout,
    required Map<String, String> headers,
  }) async {
    final request = http.Request('GET', uri)
      ..headers.addAll(headers)
      ..followRedirects = false
      ..maxRedirects = 0;
    final streamed = await _coverArtApiHttpClient.send(request).timeout(timeout);
    return http.Response.fromStream(streamed);
  }

  bool _isTrustedSteamGridImageUri(Uri uri) {
    if (!uri.hasScheme || uri.scheme.toLowerCase() != 'https') {
      return false;
    }

    final host = uri.host.toLowerCase();
    if (host.isEmpty || host == 'localhost' || _ipv4HostPattern.hasMatch(host)) {
      return false;
    }

    return host == 'steamgriddb.com' || host.endsWith('.steamgriddb.com');
  }
}
