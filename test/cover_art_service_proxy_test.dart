import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:compact_games/core/config/cover_art_proxy_config.dart';
import 'package:compact_games/models/app_settings.dart';
import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/services/cover_art_service.dart';

import 'support/noop_rust_bridge_service.dart';

void main() {
  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp(
      'compact_games_cover_test_',
    );
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    CoverArtService.shutdownSharedResources();
  });

  tearDown(() async {
    await debugWaitForCoverArtCacheEvictionForTesting();
    debugSetCoverArtApiHttpClientForTesting(null);
    CoverArtService.shutdownSharedResources();
    PathProviderPlatform.instance = originalPathProvider;
    await tempDir.delete(recursive: true);
  });

  test('bundled proxy success downloads returned SteamGridDB image', () async {
    final requests = <Uri>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'proxy.example.test') {
          expect(request.headers['X-Compact-Games-Token'], 'proxy-token');
          expect(request.url.path, '/sgdb/grid');
          expect(request.url.queryParameters['steam_app_id'], '730');
          expect(request.url.queryParameters['dimension'], 'tall');
          return _jsonResponse({
            'url': 'https://cdn2.steamgriddb.com/grid/cover.jpg',
            'source': 'steamgriddb',
          });
        }
        expect(request.url.host, 'cdn2.steamgriddb.com');
        return http.Response.bytes(
          <int>[1, 2, 3, 4],
          200,
          headers: const <String, String>{'content-type': 'image/jpeg'},
        );
      }),
    );

    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Counter-Strike 2',
        path: r'C:\Steam\steamapps\common\Counter-Strike Global Offensive',
        platform: Platform.steam,
        sizeBytes: 1,
        steamAppId: 730,
      ),
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      ),
    );

    expect(result.source, CoverArtSource.steamGridDbApi);
    expect(result.uri, startsWith('file:'));
    expect(requests.length, 2);
  });

  test('application entries use bundled proxy by name', () async {
    final requests = <Uri>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'proxy.example.test') {
          expect(request.headers['X-Compact-Games-Token'], 'proxy-token');
          expect(request.url.path, '/sgdb/by-name');
          expect(request.url.queryParameters['name'], 'Death Stranding');
          expect(request.url.queryParameters['dimension'], 'tall');
          return _jsonResponse({
            'url': 'https://cdn2.steamgriddb.com/grid/application-cover.jpg',
            'source': 'steamgriddb',
          });
        }
        expect(request.url.host, 'cdn2.steamgriddb.com');
        return http.Response.bytes(
          <int>[9, 8, 7, 6],
          200,
          headers: const <String, String>{'content-type': 'image/jpeg'},
        );
      }),
    );

    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Death Stranding',
        path: r'C:\Games\manual_death_stranding',
        platform: Platform.application,
        sizeBytes: 1,
      ),
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      ),
    );

    expect(result.source, CoverArtSource.steamGridDbApi);
    expect(result.uri, startsWith('file:'));
    expect(requests.map((uri) => uri.path), <String>[
      '/sgdb/by-name',
      '/grid/application-cover.jpg',
    ]);
  });

  test('proxy 404 is treated as no result without user-key fallback', () async {
    final requests = <Uri>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'proxy.example.test') {
          return _jsonResponse({'error': 'Not found'}, 404);
        }
        throw StateError('Unexpected fallback request to ${request.url}');
      }),
    );

    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Unknown Game',
        path: r'C:\Games\unknown_proxy_404',
        platform: Platform.custom,
        sizeBytes: 1,
      ),
      steamGridDbApiKey: 'user-key',
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      ),
    );

    expect(result.source, CoverArtSource.none);
    expect(requests.single.host, 'proxy.example.test');
  });

  test('exe discovery failures resolve to placeholder cover', () async {
    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Bridge Shutdown Game',
        path: r'C:\Games\bridge_shutdown_game',
        platform: Platform.application,
        sizeBytes: 1,
      ),
      coverArtProviderMode: CoverArtProviderMode.userKey,
      rustBridge: const _ThrowingDiscoverRustBridgeService(),
    );

    expect(result.source, CoverArtSource.none);
    expect(result.uri, isNull);
  });

  test('proxy 503 falls back to the user SteamGridDB key', () async {
    final requests = <Uri>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'proxy.example.test') {
          return _jsonResponse({'error': 'unavailable'}, 503);
        }
        if (request.url.path == '/api/v2/search/autocomplete/Fallback%20Game') {
          expect(request.headers['Authorization'], 'user-key');
          return _jsonResponse({
            'data': [
              {'id': 42, 'name': 'Fallback Game'},
            ],
          });
        }
        if (request.url.path == '/api/v2/grids/game/42') {
          return _jsonResponse({
            'data': [
              {
                'url': 'https://cdn2.steamgriddb.com/grid/fallback.jpg',
                'width': 600,
                'height': 900,
              },
            ],
          });
        }
        if (request.url.host == 'cdn2.steamgriddb.com') {
          return http.Response.bytes(
            <int>[5, 6, 7, 8],
            200,
            headers: const <String, String>{'content-type': 'image/jpeg'},
          );
        }
        throw StateError('Unexpected request to ${request.url}');
      }),
    );

    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Fallback Game',
        path: r'C:\Games\fallback_proxy_503',
        platform: Platform.custom,
        sizeBytes: 1,
      ),
      steamGridDbApiKey: 'user-key',
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      ),
    );

    expect(result.source, CoverArtSource.steamGridDbApi);
    expect(requests.map((uri) => uri.host), contains('www.steamgriddb.com'));
    expect(requests.map((uri) => uri.host), contains('cdn2.steamgriddb.com'));
  });

  test('proxy client failures fall back to the user SteamGridDB key', () async {
    final requests = <Uri>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'proxy.example.test') {
          throw http.ClientException('connection closed', request.url);
        }
        if (request.url.path ==
            '/api/v2/search/autocomplete/Client%20Failure%20Fallback') {
          expect(request.headers['Authorization'], 'user-key');
          return _jsonResponse({
            'data': [
              {'id': 52, 'name': 'Client Failure Fallback'},
            ],
          });
        }
        if (request.url.path == '/api/v2/grids/game/52') {
          return _jsonResponse({
            'data': [
              {
                'url': 'https://cdn2.steamgriddb.com/grid/client-fallback.jpg',
                'width': 600,
                'height': 900,
              },
            ],
          });
        }
        if (request.url.host == 'cdn2.steamgriddb.com') {
          return http.Response.bytes(
            <int>[21, 22, 23, 24],
            200,
            headers: const <String, String>{'content-type': 'image/jpeg'},
          );
        }
        throw StateError('Unexpected request to ${request.url}');
      }),
    );

    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Client Failure Fallback',
        path: r'C:\Games\client_failure_proxy_fallback',
        platform: Platform.custom,
        sizeBytes: 1,
      ),
      steamGridDbApiKey: 'user-key',
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      ),
    );

    expect(result.source, CoverArtSource.steamGridDbApi);
    expect(requests.map((uri) => uri.host), contains('proxy.example.test'));
    expect(requests.map((uri) => uri.host), contains('www.steamgriddb.com'));
  });

  test('missing proxy config falls back to the user key cleanly', () async {
    final requests = <Uri>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.path ==
            '/api/v2/search/autocomplete/Local%20Dev%20Game') {
          return _jsonResponse({
            'data': [
              {'id': 7, 'name': 'Local Dev Game'},
            ],
          });
        }
        if (request.url.path == '/api/v2/grids/game/7') {
          return _jsonResponse({
            'data': [
              {
                'url': 'https://cdn2.steamgriddb.com/grid/local-dev.jpg',
                'width': 600,
                'height': 900,
              },
            ],
          });
        }
        if (request.url.host == 'cdn2.steamgriddb.com') {
          return http.Response.bytes(
            <int>[9, 10, 11, 12],
            200,
            headers: const <String, String>{'content-type': 'image/jpeg'},
          );
        }
        throw StateError('Unexpected request to ${request.url}');
      }),
    );

    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Local Dev Game',
        path: r'C:\Games\missing_proxy_config',
        platform: Platform.custom,
        sizeBytes: 1,
      ),
      steamGridDbApiKey: 'user-key',
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(),
    );

    expect(result.source, CoverArtSource.steamGridDbApi);
    expect(requests.every((uri) => uri.host != 'proxy.example.test'), isTrue);
  });

  test('cover memory cache separates provider mode and proxy config', () async {
    final game = GameInfo(
      name: 'Provider Cache Game',
      path: r'C:\Games\provider_cache_game',
      platform: Platform.custom,
      sizeBytes: 1,
    );

    final withoutKey = await const CoverArtService().resolveCover(
      game,
      coverArtProviderMode: CoverArtProviderMode.userKey,
    );
    expect(withoutKey.source, CoverArtSource.none);

    final requests = <Uri>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'proxy.example.test') {
          return _jsonResponse({
            'url': 'https://cdn2.steamgriddb.com/grid/provider-cache.jpg',
            'source': 'steamgriddb',
          });
        }
        if (request.url.host == 'cdn2.steamgriddb.com') {
          return http.Response.bytes(
            <int>[31, 32, 33, 34],
            200,
            headers: const <String, String>{'content-type': 'image/jpeg'},
          );
        }
        throw StateError('Unexpected request to ${request.url}');
      }),
    );

    final withProxy = await const CoverArtService().resolveCover(
      game,
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      ),
    );

    expect(withProxy.source, CoverArtSource.steamGridDbApi);
    expect(requests.map((uri) => uri.host), contains('proxy.example.test'));
  });

  test(
    'remote http proxy config falls back without sending proxy token',
    () async {
      final requests = <Uri>[];
      debugSetCoverArtApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url);
          expect(request.url.host, isNot('proxy.example.test'));
          if (request.url.path ==
              '/api/v2/search/autocomplete/Remote%20Http%20Proxy%20Game') {
            return _jsonResponse({
              'data': [
                {'id': 9, 'name': 'Remote Http Proxy Game'},
              ],
            });
          }
          if (request.url.path == '/api/v2/grids/game/9') {
            return _jsonResponse({
              'data': [
                {
                  'url': 'https://cdn2.steamgriddb.com/grid/http-fallback.jpg',
                  'width': 600,
                  'height': 900,
                },
              ],
            });
          }
          if (request.url.host == 'cdn2.steamgriddb.com') {
            return http.Response.bytes(
              <int>[13, 14, 15, 16],
              200,
              headers: const <String, String>{'content-type': 'image/jpeg'},
            );
          }
          throw StateError('Unexpected request to ${request.url}');
        }),
      );

      final result = await const CoverArtService().resolveCover(
        GameInfo(
          name: 'Remote Http Proxy Game',
          path: r'C:\Games\remote_http_proxy_config',
          platform: Platform.custom,
          sizeBytes: 1,
        ),
        steamGridDbApiKey: 'user-key',
        coverArtProviderMode: CoverArtProviderMode.bundledProxy,
        coverArtProxyConfig: const CoverArtProxyConfig(
          url: 'http://proxy.example.test',
          token: 'proxy-token',
        ),
      );

      expect(result.source, CoverArtSource.steamGridDbApi);
      expect(
        requests.map((uri) => uri.host),
        isNot(contains('proxy.example.test')),
      );
    },
  );

  test('oversized image stream is rejected before full buffering', () async {
    final client = _OversizedImageClient();
    debugSetCoverArtApiHttpClientForTesting(client);

    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Oversized Cover Game',
        path: r'C:\Games\oversized_cover_stream',
        platform: Platform.custom,
        sizeBytes: 1,
      ),
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      ),
    );

    expect(result.source, CoverArtSource.none);
    expect(client.imageChunksEmitted, lessThan(10));
  });

  test('base URL query params are preserved when building proxy URI', () async {
    final requests = <Uri>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'proxy.example.test') {
          expect(request.url.queryParameters['env'], 'staging');
          expect(request.url.queryParameters['steam_app_id'], '440');
          expect(request.url.queryParameters['dimension'], 'tall');
          return _jsonResponse({
            'url': 'https://cdn2.steamgriddb.com/grid/base-params.jpg',
            'source': 'steamgriddb',
          });
        }
        return http.Response.bytes(
          <int>[1, 2, 3, 4],
          200,
          headers: const <String, String>{'content-type': 'image/jpeg'},
        );
      }),
    );

    await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Base Params Game',
        path: r'C:\Steam\steamapps\common\Team Fortress 2',
        platform: Platform.steam,
        sizeBytes: 1,
        steamAppId: 440,
      ),
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test?env=staging',
        token: 'proxy-token',
      ),
    );

    expect(requests.isNotEmpty, isTrue);
    final proxyRequest = requests.firstWhere(
      (uri) => uri.host == 'proxy.example.test',
    );
    expect(proxyRequest.queryParameters['env'], 'staging');
    expect(proxyRequest.queryParameters['steam_app_id'], '440');
    expect(proxyRequest.queryParameters['dimension'], 'tall');
  });

  test('cover-art API permits cap bursty proxy lookups', () async {
    final client = _TrackingCoverClient();
    debugSetCoverArtApiHttpClientForTesting(client);

    final futures = List<Future<CoverArtResult>>.generate(12, (index) {
      return const CoverArtService().resolveCover(
        GameInfo(
          name: 'Burst Cover Game $index',
          path:
              r'C:\Games\burst_cover_game_'
              '$index',
          platform: Platform.custom,
          sizeBytes: 1,
        ),
        coverArtProviderMode: CoverArtProviderMode.bundledProxy,
        coverArtProxyConfig: const CoverArtProxyConfig(
          url: 'https://proxy.example.test',
          token: 'proxy-token',
        ),
      );
    });

    final results = await Future.wait(futures);

    expect(results.map((result) => result.source).toSet(), <CoverArtSource>{
      CoverArtSource.steamGridDbApi,
    });
    expect(client.maxActiveRequests, lessThanOrEqualTo(3));
  });
}

class _ThrowingDiscoverRustBridgeService extends NoOpRustBridgeService {
  const _ThrowingDiscoverRustBridgeService();

  @override
  Future<String?> discoverPrimaryExe(String folder) async {
    throw StateError('bridge unavailable');
  }
}

http.Response _jsonResponse(Map<String, Object?> body, [int status = 200]) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

http.StreamedResponse _jsonStreamedResponse(
  Map<String, Object?> body, [
  int status = 200,
]) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    status,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

http.StreamedResponse _bytesStreamedResponse(List<int> bytes) {
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    200,
    headers: const <String, String>{'content-type': 'image/jpeg'},
  );
}

class _OversizedImageClient extends http.BaseClient {
  int imageChunksEmitted = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.host == 'proxy.example.test') {
      return _jsonStreamedResponse({
        'url': 'https://cdn2.steamgriddb.com/grid/oversized.jpg',
        'source': 'steamgriddb',
      });
    }
    if (request.url.host == 'cdn2.steamgriddb.com') {
      return http.StreamedResponse(
        _oversizedImageStream(),
        200,
        headers: const <String, String>{'content-type': 'image/jpeg'},
      );
    }
    throw StateError('Unexpected request to ${request.url}');
  }

  Stream<List<int>> _oversizedImageStream() async* {
    final chunk = List<int>.filled(1024 * 1024, 1);
    for (var index = 0; index < 10; index++) {
      imageChunksEmitted += 1;
      yield chunk;
    }
  }
}

class _TrackingCoverClient extends http.BaseClient {
  int _activeRequests = 0;
  int maxActiveRequests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _activeRequests += 1;
    if (_activeRequests > maxActiveRequests) {
      maxActiveRequests = _activeRequests;
    }
    try {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (request.url.host == 'proxy.example.test') {
        final id = Uri.encodeComponent(request.url.queryParameters['name']!);
        return _jsonStreamedResponse({
          'url': 'https://cdn2.steamgriddb.com/grid/$id.jpg',
          'source': 'steamgriddb',
        });
      }
      if (request.url.host == 'cdn2.steamgriddb.com') {
        return _bytesStreamedResponse(<int>[1, 2, 3, 4]);
      }
      throw StateError('Unexpected request to ${request.url}');
    } finally {
      _activeRequests -= 1;
    }
  }
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.applicationSupportPath);

  final String applicationSupportPath;

  @override
  Future<String?> getApplicationSupportPath() async => applicationSupportPath;
}
