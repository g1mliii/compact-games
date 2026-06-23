part of 'cover_art_service.dart';

const Duration _proxyJsonRequestTimeout = Duration(seconds: 4);

enum _CoverProxyLookupStatus { found, notFound, unavailable }

class _CoverProxyLookupResult {
  const _CoverProxyLookupResult._(this.status, this.path);

  final _CoverProxyLookupStatus status;
  final String? path;

  const _CoverProxyLookupResult.found(String path)
    : this._(_CoverProxyLookupStatus.found, path);
  const _CoverProxyLookupResult.notFound()
    : this._(_CoverProxyLookupStatus.notFound, null);
  const _CoverProxyLookupResult.unavailable()
    : this._(_CoverProxyLookupStatus.unavailable, null);
}

extension _CoverArtServiceProxy on CoverArtService {
  Future<_CoverProxyLookupResult> _resolveSteamGridDbCoverViaProxy(
    GameInfo game, {
    required String cacheKey,
    required CoverArtProxyConfig proxyConfig,
  }) async {
    if (!proxyConfig.isConfigured) {
      return const _CoverProxyLookupResult.unavailable();
    }

    try {
      Uri? uri;
      if (game.platform == Platform.steam) {
        final steamAppId =
            game.steamAppId?.toString() ??
            await _resolveSteamAppIdFromGamePath(game.path);
        if (steamAppId != null && steamAppId.isNotEmpty) {
          uri = _proxyUri(proxyConfig, '/sgdb/grid', <String, String>{
            'steam_app_id': steamAppId,
            'dimension': 'tall',
          });
        }
      }

      uri ??= _proxyUri(proxyConfig, '/sgdb/by-name', <String, String>{
        'name': game.name,
        'dimension': 'tall',
      });
      if (uri == null) {
        return const _CoverProxyLookupResult.unavailable();
      }

      final response = await _withApiPermit(
        () => _getCoverArtApiHttpClient()
            .get(
              uri!,
              headers: <String, String>{
                'Accept': 'application/json',
                'User-Agent': 'CompactGames/0.1',
                'X-Compact-Games-Token': proxyConfig.token.trim(),
              },
            )
            .timeout(_proxyJsonRequestTimeout),
      );

      if (response.statusCode == 404) {
        return const _CoverProxyLookupResult.notFound();
      }
      if (response.statusCode != 200 || response.body.isEmpty) {
        return const _CoverProxyLookupResult.unavailable();
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        return const _CoverProxyLookupResult.unavailable();
      }
      if (decoded is! Map<String, dynamic>) {
        return const _CoverProxyLookupResult.unavailable();
      }

      final imageUrl = decoded['url'] as String?;
      if (imageUrl == null || imageUrl.isEmpty) {
        return const _CoverProxyLookupResult.unavailable();
      }
      final path = await _downloadRemoteImageIntoCache(cacheKey, imageUrl);
      if (path == null) {
        return const _CoverProxyLookupResult.unavailable();
      }
      return _CoverProxyLookupResult.found(path);
    } catch (e) {
      if (e is TimeoutException ||
          e is SocketException ||
          e is HttpException ||
          e is http.ClientException ||
          e is _RetryableApiException) {
        return const _CoverProxyLookupResult.unavailable();
      }
      rethrow;
    }
  }

  Uri? _proxyUri(
    CoverArtProxyConfig proxyConfig,
    String endpoint,
    Map<String, String> queryParameters,
  ) {
    final base = Uri.tryParse(proxyConfig.url.trim());
    if (base == null ||
        !base.hasScheme ||
        (base.scheme != 'https' &&
            (base.scheme != 'http' || !_isLoopbackHost(base.host))) ||
        base.host.isEmpty) {
      return null;
    }

    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final merged = <String, List<String>>{
      ...base.queryParametersAll,
      for (final entry in queryParameters.entries)
        entry.key: [entry.value],
    };
    return base.replace(
      path: '$prefix$endpoint',
      queryParameters: merged.isEmpty ? null : merged,
    );
  }

  bool _isLoopbackHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1';
  }
}
