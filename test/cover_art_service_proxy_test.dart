import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
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

    final cached = await const CoverArtService().resolveCover(
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

    expect(cached.source, CoverArtSource.steamGridDbApi);
    expect(requests.length, 2);
  });

  test(
    'tagged API disk cache skips revalidation until explicitly refreshed',
    () async {
      final game = GameInfo(
        name: 'Persisted API Cover',
        path: r'C:\\Games\\persisted_api_cover',
        platform: Platform.custom,
        sizeBytes: 1,
      );
      await _writeCachedCover(
        tempDir,
        game.path,
        _fakePngHeader(width: 600, height: 900),
      );
      await _writeCachedCoverSource(
        tempDir,
        game.path,
        CoverArtSource.steamGridDbApi,
      );
      final requests = <Uri>[];
      debugSetCoverArtApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url);
          if (request.url.host == 'proxy.example.test') {
            return _jsonResponse({
              'url': 'https://cdn2.steamgriddb.com/grid/refreshed.jpg',
            });
          }
          return http.Response.bytes(
            <int>[9, 8, 7, 6],
            200,
            headers: const <String, String>{'content-type': 'image/jpeg'},
          );
        }),
      );

      const service = CoverArtService();
      final result = await service.resolveCover(
        game,
        coverArtProviderMode: CoverArtProviderMode.bundledProxy,
        coverArtProxyConfig: const CoverArtProxyConfig(
          url: 'https://proxy.example.test',
          token: 'proxy-token',
        ),
      );

      expect(result.source, CoverArtSource.steamGridDbApi);
      expect(requests, isEmpty);

      service.invalidateCoverForGame(game.path);
      final refreshed = await service.resolveCover(
        game,
        coverArtProviderMode: CoverArtProviderMode.bundledProxy,
        coverArtProxyConfig: const CoverArtProxyConfig(
          url: 'https://proxy.example.test',
          token: 'proxy-token',
        ),
      );

      expect(refreshed.source, CoverArtSource.steamGridDbApi);
      expect(requests.length, 2);
    },
  );

  test(
    'configured proxy replaces stale disk cache before local fallback',
    () async {
      final game = GameInfo(
        name: 'Bad Cache Game',
        path: r'C:\Games\bad_cache_game',
        platform: Platform.custom,
        sizeBytes: 1,
      );
      final cacheFile = await _writeCachedCover(
        tempDir,
        game.path,
        _fakePngHeader(width: 32, height: 32),
      );
      const apiBytes = <int>[99, 100, 101, 102];
      final requests = <Uri>[];
      debugSetCoverArtApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url);
          if (request.url.host == 'proxy.example.test') {
            expect(request.url.path, '/sgdb/by-name');
            return _jsonResponse({
              'url': 'https://cdn2.steamgriddb.com/grid/api-cover.jpg',
              'source': 'steamgriddb',
            });
          }
          if (request.url.host == 'cdn2.steamgriddb.com') {
            return http.Response.bytes(
              apiBytes,
              200,
              headers: const <String, String>{'content-type': 'image/jpeg'},
            );
          }
          throw StateError('Unexpected request to ${request.url}');
        }),
      );

      final result = await const CoverArtService().resolveCover(
        game,
        coverArtProviderMode: CoverArtProviderMode.bundledProxy,
        coverArtProxyConfig: const CoverArtProxyConfig(
          url: 'https://proxy.example.test',
          token: 'proxy-token',
        ),
      );

      expect(result.source, CoverArtSource.steamGridDbApi);
      expect(requests.map((uri) => uri.host), <String>[
        'proxy.example.test',
        'cdn2.steamgriddb.com',
      ]);
      expect(await cacheFile.readAsBytes(), apiBytes);
    },
  );

  test(
    'Steam library fallback scans nested appid assets before tiny root thumbnail',
    () async {
      final fixture = await _writeSteamLibraryFixture(tempDir);

      final result = await const CoverArtService().resolveCover(
        GameInfo(
          name: 'Battlefield 6',
          path: fixture.gamePath,
          platform: Platform.steam,
          sizeBytes: 1,
        ),
        coverArtProviderMode: CoverArtProviderMode.userKey,
      );

      final cacheFile = _cachedCoverFile(tempDir, fixture.gamePath);
      expect(result.source, CoverArtSource.steamLibraryCache);
      expect(await cacheFile.readAsBytes(), fixture.preferredBytes);
    },
  );

  test('configured proxy replaces a preferred Steam library cover', () async {
    final fixture = await _writeSteamLibraryFixture(tempDir);
    final requests = <Uri>[];
    const apiBytes = <int>[65, 66, 67, 68];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'proxy.example.test') {
          return _jsonResponse({
            'url': 'https://cdn2.steamgriddb.com/grid/api-cover.jpg',
            'source': 'steamgriddb',
          });
        }
        if (request.url.host == 'cdn2.steamgriddb.com') {
          return http.Response.bytes(
            apiBytes,
            200,
            headers: const <String, String>{'content-type': 'image/jpeg'},
          );
        }
        throw StateError('Unexpected request to ${request.url}');
      }),
    );

    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Battlefield 6',
        path: fixture.gamePath,
        platform: Platform.steam,
        sizeBytes: 1,
      ),
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      ),
    );

    final cacheFile = _cachedCoverFile(tempDir, fixture.gamePath);
    expect(result.source, CoverArtSource.steamGridDbApi);
    expect(requests.map((uri) => uri.host), <String>[
      'proxy.example.test',
      'cdn2.steamgriddb.com',
    ]);
    expect(await cacheFile.readAsBytes(), apiBytes);
  });

  test('configured proxy replaces a preferred disk cache', () async {
    final game = GameInfo(
      name: 'Cyberpunk 2077',
      path: r'D:\Games\Cyberpunk 2077',
      platform: Platform.custom,
      sizeBytes: 1,
    );
    final cacheFile = await _writeCachedCover(
      tempDir,
      game.path,
      _fakePngHeader(width: 600, height: 900),
    );
    const apiBytes = <int>[71, 72, 73, 74];
    final requestedNames = <String>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        if (request.url.host == 'proxy.example.test') {
          requestedNames.add(request.url.queryParameters['name']!);
          return _jsonResponse({
            'url': 'https://cdn2.steamgriddb.com/grid/api-cover.jpg',
            'source': 'steamgriddb',
          });
        }
        if (request.url.host == 'cdn2.steamgriddb.com') {
          return http.Response.bytes(
            apiBytes,
            200,
            headers: const <String, String>{'content-type': 'image/jpeg'},
          );
        }
        throw StateError('Unexpected request to ${request.url}');
      }),
    );

    final result = await const CoverArtService().resolveCover(
      game,
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      ),
    );

    expect(result.source, CoverArtSource.steamGridDbApi);
    expect(requestedNames, <String>['Cyberpunk 2077']);
    expect(await cacheFile.readAsBytes(), apiBytes);
  });

  test(
    'configured proxy reuses a fallback until explicit invalidation',
    () async {
      final game = GameInfo(
        name: 'Sample Cache Game',
        path: r'D:\Games\Sample Cache Game',
        platform: Platform.custom,
        sizeBytes: 1,
      );
      await _writeCachedCover(
        tempDir,
        game.path,
        _fakePngHeader(width: 600, height: 900),
      );
      const proxyConfig = CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      );
      final service = const CoverArtService();

      debugSetCoverArtApiHttpClientForTesting(
        MockClient((request) async {
          expect(request.url.host, 'proxy.example.test');
          return _jsonResponse({'error': 'unavailable'}, 503);
        }),
      );
      final fallback = await service.resolveCover(
        game,
        coverArtProviderMode: CoverArtProviderMode.bundledProxy,
        coverArtProxyConfig: proxyConfig,
      );
      expect(fallback.source, CoverArtSource.cache);

      const apiBytes = <int>[81, 82, 83, 84];
      debugSetCoverArtApiHttpClientForTesting(
        MockClient((request) async {
          if (request.url.host == 'proxy.example.test') {
            expect(request.url.path, '/sgdb/by-name');
            expect(request.url.queryParameters['name'], 'Sample Cache Game');
            return _jsonResponse({
              'url': 'https://cdn2.steamgriddb.com/grid/sample-cache-game.jpg',
              'source': 'steamgriddb',
            });
          }
          if (request.url.host == 'cdn2.steamgriddb.com') {
            return http.Response.bytes(
              apiBytes,
              200,
              headers: const <String, String>{'content-type': 'image/jpeg'},
            );
          }
          throw StateError('Unexpected request to ${request.url}');
        }),
      );

      final reused = await service.resolveCover(
        game,
        coverArtProviderMode: CoverArtProviderMode.bundledProxy,
        coverArtProxyConfig: proxyConfig,
      );

      expect(reused.source, CoverArtSource.cache);

      service.invalidateCoverForGame(game.path);
      final refreshed = await service.resolveCover(
        game,
        coverArtProviderMode: CoverArtProviderMode.bundledProxy,
        coverArtProxyConfig: proxyConfig,
      );

      expect(refreshed.source, CoverArtSource.steamGridDbApi);
    },
  );

  test('confirmed proxy misses discard a legacy custom cover cache', () async {
    final game = GameInfo(
      name: 'Sample Missing Game',
      path: r'D:\\Games\\Sample Missing Game',
      platform: Platform.custom,
      sizeBytes: 1,
    );
    final cacheFile = await _writeCachedCover(
      tempDir,
      game.path,
      _fakePngHeader(width: 600, height: 900),
    );
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.host, 'proxy.example.test');
        return _jsonResponse({'error': 'Not found'}, 404);
      }),
    );

    final result = await const CoverArtService().resolveCover(
      game,
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      ),
    );

    expect(result.source, CoverArtSource.none);
    expect(await cacheFile.exists(), isFalse);
  });

  test(
    'custom install retries by primary executable title after name miss',
    () async {
      final games = <GameInfo>[
        GameInfo(
          name: 'Cyberpunk 2077 Wrapper',
          path: r'D:\Games\Cyberpunk 2077 Wrapper',
          platform: Platform.custom,
          sizeBytes: 1,
        ),
        GameInfo(
          name: 'Sample Game Alias',
          path: r'D:\Games\Sample Game Alias',
          platform: Platform.custom,
          sizeBytes: 1,
        ),
      ];
      const executablePaths = <String, String>{
        r'D:\Games\Cyberpunk 2077 Wrapper':
            r'D:\Games\Cyberpunk 2077 Wrapper\Cyberpunk_2077.exe',
        r'D:\Games\Sample Game Alias':
            r'D:\Games\Sample Game Alias\SampleGame.exe',
      };
      final requestedNames = <String>[];
      debugSetCoverArtApiHttpClientForTesting(
        MockClient((request) async {
          if (request.url.host == 'proxy.example.test') {
            final name = request.url.queryParameters['name']!;
            requestedNames.add(name);
            if (name == 'Cyberpunk 2077 Wrapper' ||
                name == 'Sample Game Alias') {
              return _jsonResponse({'error': 'Not found'}, 404);
            }
            return _jsonResponse({
              'url': 'https://cdn2.steamgriddb.com/grid/${name.hashCode}.jpg',
              'source': 'steamgriddb',
            });
          }
          if (request.url.host == 'cdn2.steamgriddb.com') {
            return http.Response.bytes(
              <int>[91, 92, 93, 94],
              200,
              headers: const <String, String>{'content-type': 'image/jpeg'},
            );
          }
          throw StateError('Unexpected request to ${request.url}');
        }),
      );

      for (final game in games) {
        final result = await const CoverArtService().resolveCover(
          game,
          coverArtProviderMode: CoverArtProviderMode.bundledProxy,
          coverArtProxyConfig: const CoverArtProxyConfig(
            url: 'https://proxy.example.test',
            token: 'proxy-token',
          ),
          rustBridge: _PrimaryExeRustBridgeService(executablePaths),
        );
        expect(result.source, CoverArtSource.steamGridDbApi);
      }

      expect(requestedNames, <String>[
        'Cyberpunk 2077 Wrapper',
        'Cyberpunk 2077',
        'Sample Game Alias',
        'Sample Game',
      ]);
    },
  );

  test('user-key miss falls back to an exact Steam store portrait', () async {
    final requests = <Uri>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'www.steamgriddb.com') {
          return _jsonResponse({'data': <Object>[]});
        }
        if (request.url.host == 'store.steampowered.com') {
          expect(request.url.path, '/api/storesearch/');
          expect(request.url.queryParameters['term'], 'Recent Launch');
          return _jsonResponse({
            'items': [
              {'id': 4242, 'name': 'Recent Launch'},
            ],
          });
        }
        if (request.url.host == 'api.steampowered.com') {
          expect(request.url.path, '/IStoreBrowseService/GetItems/v1/');
          return _jsonResponse({
            'response': {
              'store_items': [
                {
                  'appid': 4242,
                  'assets': {
                    'asset_url_format': r'steam/apps/4242/${FILENAME}?t=123',
                    'library_capsule_2x': 'portrait/library_capsule_2x.jpg',
                  },
                },
              ],
            },
          });
        }
        if (request.url.host == 'shared.akamai.steamstatic.com') {
          expect(
            request.url.path,
            '/store_item_assets/steam/apps/4242/portrait/'
            'library_capsule_2x.jpg',
          );
          return http.Response.bytes(
            <int>[31, 32, 33, 34],
            200,
            headers: const <String, String>{'content-type': 'image/jpeg'},
          );
        }
        throw StateError('Unexpected request to ${request.url}');
      }),
    );

    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Recent Launch',
        path: r'D:\Games\recent_launch',
        platform: Platform.custom,
        sizeBytes: 1,
      ),
      steamGridDbApiKey: 'user-key',
      coverArtProviderMode: CoverArtProviderMode.userKey,
    );

    expect(result.source, CoverArtSource.steamStoreApi);
    expect(result.uri, startsWith('file:'));
    expect(
      requests.map((uri) => uri.host),
      containsAll(<String>[
        'www.steamgriddb.com',
        'store.steampowered.com',
        'api.steampowered.com',
        'shared.akamai.steamstatic.com',
      ]),
    );
  });

  test(
    'bundled proxy miss falls back to an official Steam portrait for a safe title prefix',
    () async {
      final requests = <Uri>[];
      debugSetCoverArtApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url);
          if (request.url.host == 'proxy.example.test') {
            expect(request.url.path, '/sgdb/by-name');
            expect(request.url.queryParameters['name'], 'Restory');
            return _jsonResponse({'error': 'Not found'}, 404);
          }
          if (request.url.host == 'store.steampowered.com') {
            expect(request.url.path, '/api/storesearch/');
            expect(request.url.queryParameters['term'], 'Restory');
            return _jsonResponse({
              'items': [
                {'id': 3812600, 'name': 'ReStory: Chill Electronics Repairs'},
              ],
            });
          }
          if (request.url.host == 'api.steampowered.com') {
            return _jsonResponse({
              'response': {
                'store_items': [
                  {
                    'appid': 3812600,
                    'assets': {
                      'asset_url_format':
                          r'steam/apps/3812600/${FILENAME}?t=123',
                      'library_capsule_2x': 'portrait/library_capsule_2x.jpg',
                    },
                  },
                ],
              },
            });
          }
          if (request.url.host == 'shared.akamai.steamstatic.com') {
            return http.Response.bytes(
              <int>[51, 52, 53, 54],
              200,
              headers: const <String, String>{'content-type': 'image/jpeg'},
            );
          }
          throw StateError('Unexpected request to ${request.url}');
        }),
      );

      final result = await const CoverArtService().resolveCover(
        GameInfo(
          name: 'Restory',
          path: r'C:\Games\Restory',
          platform: Platform.custom,
          sizeBytes: 1,
        ),
        coverArtProviderMode: CoverArtProviderMode.bundledProxy,
        coverArtProxyConfig: const CoverArtProxyConfig(
          url: 'https://proxy.example.test',
          token: 'proxy-token',
        ),
      );

      expect(result.source, CoverArtSource.steamStoreApi);
      expect(result.uri, startsWith('file:'));
      expect(
        requests.map((uri) => uri.host),
        containsAll(<String>[
          'proxy.example.test',
          'store.steampowered.com',
          'api.steampowered.com',
          'shared.akamai.steamstatic.com',
        ]),
      );
    },
  );

  test(
    'Steam store fallback accepts the closest multiword catalog title',
    () async {
      final storeTerms = <String>[];
      debugSetCoverArtApiHttpClientForTesting(
        MockClient((request) async {
          if (request.url.host == 'www.steamgriddb.com') {
            return _jsonResponse({'data': <Object>[]});
          }
          if (request.url.host == 'store.steampowered.com') {
            final term = request.url.queryParameters['term']!;
            storeTerms.add(term);
            return _jsonResponse({
              'items': [
                {'id': 4444, 'name': 'Sunny Smile Caf\u00e9 Soundtrack'},
                {'id': 4343, 'name': 'Sunny Smile Caf\u00e9'},
                {'id': 4545, 'name': 'Sunny Smile Caf\u00e9 Artbook'},
              ],
            });
          }
          if (request.url.host == 'api.steampowered.com') {
            return _jsonResponse({
              'response': {
                'store_items': [
                  {
                    'appid': 4343,
                    'assets': {
                      'asset_url_format': r'steam/apps/4343/${FILENAME}?t=456',
                      'library_capsule': 'portrait/library_capsule.jpg',
                    },
                  },
                ],
              },
            });
          }
          if (request.url.host == 'shared.akamai.steamstatic.com') {
            return http.Response.bytes(
              <int>[41, 42, 43, 44],
              200,
              headers: const <String, String>{'content-type': 'image/jpeg'},
            );
          }
          throw StateError('Unexpected request to ${request.url}');
        }),
      );

      final result = await const CoverArtService().resolveCover(
        GameInfo(
          name: 'Sunny Smile',
          path: r'D:\Games\sunny_smile',
          platform: Platform.custom,
          sizeBytes: 1,
        ),
        steamGridDbApiKey: 'user-key',
        coverArtProviderMode: CoverArtProviderMode.userKey,
      );

      expect(result.source, CoverArtSource.steamStoreApi);
      expect(storeTerms, <String>['Sunny Smile']);
    },
  );

  test('Steam store fallback rejects unrelated catalog results', () async {
    final requests = <Uri>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'www.steamgriddb.com') {
          return _jsonResponse({'data': <Object>[]});
        }
        if (request.url.host == 'store.steampowered.com') {
          return _jsonResponse({
            'items': [
              {'id': 4646, 'name': 'Different Adventure'},
              {'id': 4747, 'name': 'Unrelated Sample'},
            ],
          });
        }
        throw StateError('Unexpected request to ${request.url}');
      }),
    );

    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Sample Adventure',
        path: r'D:\Games\sample_adventure_store_miss',
        platform: Platform.custom,
        sizeBytes: 1,
      ),
      steamGridDbApiKey: 'user-key',
      coverArtProviderMode: CoverArtProviderMode.userKey,
    );

    expect(result.source, CoverArtSource.none);
    expect(requests.map((uri) => uri.host), <String>[
      'www.steamgriddb.com',
      'store.steampowered.com',
    ]);
  });

  test(
    'bad cached cover falls back to preferred nested Steam asset when proxy is unavailable',
    () async {
      final fixture = await _writeSteamLibraryFixture(tempDir);
      final cacheFile = await _writeCachedCover(
        tempDir,
        fixture.gamePath,
        _fakePngHeader(width: 32, height: 32),
      );
      final requests = <Uri>[];
      debugSetCoverArtApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url);
          if (request.url.host == 'proxy.example.test') {
            return _jsonResponse({'error': 'unavailable'}, 503);
          }
          throw StateError('Unexpected request to ${request.url}');
        }),
      );

      final result = await const CoverArtService().resolveCover(
        GameInfo(
          name: 'Battlefield 6',
          path: fixture.gamePath,
          platform: Platform.steam,
          sizeBytes: 1,
        ),
        coverArtProviderMode: CoverArtProviderMode.bundledProxy,
        coverArtProxyConfig: const CoverArtProxyConfig(
          url: 'https://proxy.example.test',
          token: 'proxy-token',
        ),
      );

      expect(requests.single.host, 'proxy.example.test');
      expect(result.source, CoverArtSource.steamLibraryCache);
      expect(await cacheFile.readAsBytes(), fixture.preferredBytes);
    },
  );

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

  test('proxy 404 still tries the user key and the Steam store', () async {
    final requests = <Uri>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'proxy.example.test') {
          return _jsonResponse({'error': 'Not found'}, 404);
        }
        if (request.url.host == 'www.steamgriddb.com') {
          return _jsonResponse({'data': <Object>[]});
        }
        if (request.url.host == 'store.steampowered.com') {
          return _jsonResponse({'items': <Object>[]});
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
    expect(requests.map((uri) => uri.host), <String>[
      'proxy.example.test',
      'www.steamgriddb.com',
      'store.steampowered.com',
    ]);
  });

  test(
    'a user key does not suppress the Steam store fallback in bundled mode',
    () async {
      final requests = <Uri>[];
      debugSetCoverArtApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url);
          if (request.url.host == 'proxy.example.test') {
            expect(request.url.queryParameters['name'], 'Starbreed');
            return _jsonResponse({'error': 'Not found'}, 404);
          }
          if (request.url.host == 'www.steamgriddb.com') {
            return _jsonResponse({'data': <Object>[]});
          }
          if (request.url.host == 'store.steampowered.com') {
            expect(request.url.queryParameters['term'], 'Starbreed');
            return _jsonResponse({
              'items': [
                {'id': 2694020, 'name': 'Starbreed'},
                {'id': 4932900, 'name': 'Starbreed Artbook'},
              ],
            });
          }
          if (request.url.host == 'api.steampowered.com') {
            return _jsonResponse({
              'response': {
                'store_items': [
                  {
                    'appid': 2694020,
                    'assets': {
                      'asset_url_format':
                          r'steam/apps/2694020/${FILENAME}?t=123',
                      'library_capsule_2x': 'portrait/library_capsule_2x.jpg',
                    },
                  },
                ],
              },
            });
          }
          if (request.url.host == 'shared.akamai.steamstatic.com') {
            return http.Response.bytes(
              <int>[61, 62, 63, 64],
              200,
              headers: const <String, String>{'content-type': 'image/jpeg'},
            );
          }
          throw StateError('Unexpected request to ${request.url}');
        }),
      );

      final result = await const CoverArtService().resolveCover(
        GameInfo(
          name: 'Starbreed',
          path: r'C:\Games\Starbreed\Starbreed - SteamGG.NET',
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

      expect(result.source, CoverArtSource.steamStoreApi);
      expect(
        requests.map((uri) => uri.host),
        containsAll(<String>[
          'proxy.example.test',
          'www.steamgriddb.com',
          'store.steampowered.com',
          'shared.akamai.steamstatic.com',
        ]),
      );
    },
  );

  test('a failing user key still falls through to the bundled proxy', () async {
    final requests = <Uri>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'www.steamgriddb.com') {
          return _jsonResponse({'error': 'Unauthorized'}, 401);
        }
        if (request.url.host == 'proxy.example.test') {
          return _jsonResponse({
            'url': 'https://cdn2.steamgriddb.com/grid/rescued.jpg',
            'source': 'steamgriddb',
          });
        }
        if (request.url.host == 'cdn2.steamgriddb.com') {
          return http.Response.bytes(
            <int>[91, 92, 93, 94],
            200,
            headers: const <String, String>{'content-type': 'image/jpeg'},
          );
        }
        throw StateError('Unexpected request to ${request.url}');
      }),
    );

    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Expired Key Game',
        path: r'C:\Games\expired_user_key',
        platform: Platform.custom,
        sizeBytes: 1,
      ),
      steamGridDbApiKey: 'revoked-key',
      coverArtProviderMode: CoverArtProviderMode.userKey,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      ),
    );

    expect(result.source, CoverArtSource.steamGridDbApi);
    final hosts = requests.map((uri) => uri.host).toList();
    expect(hosts.first, 'www.steamgriddb.com');
    expect(hosts, contains('proxy.example.test'));
  });

  test('user-key mode with a blank key still uses the bundled proxy', () async {
    final requests = <Uri>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'proxy.example.test') {
          return _jsonResponse({
            'url': 'https://cdn2.steamgriddb.com/grid/blank-key.jpg',
            'source': 'steamgriddb',
          });
        }
        if (request.url.host == 'cdn2.steamgriddb.com') {
          return http.Response.bytes(
            <int>[95, 96, 97, 98],
            200,
            headers: const <String, String>{'content-type': 'image/jpeg'},
          );
        }
        throw StateError('Unexpected request to ${request.url}');
      }),
    );

    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Blank Key Game',
        path: r'C:\Games\blank_user_key',
        platform: Platform.custom,
        sizeBytes: 1,
      ),
      steamGridDbApiKey: '   ',
      coverArtProviderMode: CoverArtProviderMode.userKey,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      ),
    );

    expect(result.source, CoverArtSource.steamGridDbApi);
    expect(requests.map((uri) => uri.host), contains('proxy.example.test'));
  });

  test('a Steam game with no local art reaches the Steam store', () async {
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        if (request.url.host == 'proxy.example.test') {
          return _jsonResponse({'error': 'Not found'}, 404);
        }
        if (request.url.host == 'api.steampowered.com') {
          return _jsonResponse({
            'response': {
              'store_items': [
                {
                  'appid': 2694020,
                  'assets': {
                    'asset_url_format': r'steam/apps/2694020/${FILENAME}?t=123',
                    'library_capsule_2x': 'portrait/library_capsule_2x.jpg',
                  },
                },
              ],
            },
          });
        }
        if (request.url.host == 'shared.akamai.steamstatic.com') {
          return http.Response.bytes(
            <int>[11, 12, 13, 14],
            200,
            headers: const <String, String>{'content-type': 'image/jpeg'},
          );
        }
        throw StateError('Unexpected request to ${request.url}');
      }),
    );

    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Starbreed',
        path: r'C:\Steam\steamapps\common\Starbreed',
        platform: Platform.steam,
        sizeBytes: 1,
        steamAppId: 2694020,
      ),
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      ),
    );

    expect(result.source, CoverArtSource.steamStoreApi);
  });

  test('an unconfigured provider still reaches the Steam store', () async {
    final requests = <Uri>[];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'store.steampowered.com') {
          return _jsonResponse({
            'items': [
              {'id': 3812600, 'name': 'ReStory: Chill Electronics Repairs'},
            ],
          });
        }
        if (request.url.host == 'api.steampowered.com') {
          return _jsonResponse({
            'response': {
              'store_items': [
                {
                  'appid': 3812600,
                  'assets': {
                    'asset_url_format': r'steam/apps/3812600/${FILENAME}?t=123',
                    'library_capsule_2x': 'portrait/library_capsule_2x.jpg',
                  },
                },
              ],
            },
          });
        }
        if (request.url.host == 'shared.akamai.steamstatic.com') {
          return http.Response.bytes(
            <int>[71, 72, 73, 74],
            200,
            headers: const <String, String>{'content-type': 'image/jpeg'},
          );
        }
        throw StateError('Unexpected request to ${request.url}');
      }),
    );

    final result = await const CoverArtService().resolveCover(
      GameInfo(
        name: 'Restory',
        path: r'C:\Games\Restory',
        platform: Platform.custom,
        sizeBytes: 1,
      ),
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(),
    );

    expect(result.source, CoverArtSource.steamStoreApi);
    expect(
      requests.map((uri) => uri.host),
      isNot(contains('proxy.example.test')),
    );
  });

  test('a stale EXE-icon cache is replaced once the store answers', () async {
    final game = GameInfo(
      name: 'Restory',
      path: r'C:\Games\Restory',
      platform: Platform.custom,
      sizeBytes: 1,
    );
    final cacheFile = await _writeCachedCover(
      tempDir,
      game.path,
      _fakePngHeader(width: 128, height: 128),
    );
    await _writeCachedCoverSource(tempDir, game.path, CoverArtSource.exeIcon);
    const capsuleBytes = <int>[81, 82, 83, 84];
    debugSetCoverArtApiHttpClientForTesting(
      MockClient((request) async {
        if (request.url.host == 'proxy.example.test') {
          return _jsonResponse({'error': 'Not found'}, 404);
        }
        if (request.url.host == 'store.steampowered.com') {
          return _jsonResponse({
            'items': [
              {'id': 3812600, 'name': 'ReStory: Chill Electronics Repairs'},
            ],
          });
        }
        if (request.url.host == 'api.steampowered.com') {
          return _jsonResponse({
            'response': {
              'store_items': [
                {
                  'appid': 3812600,
                  'assets': {
                    'asset_url_format': r'steam/apps/3812600/${FILENAME}?t=123',
                    'library_capsule_2x': 'portrait/library_capsule_2x.jpg',
                  },
                },
              ],
            },
          });
        }
        if (request.url.host == 'shared.akamai.steamstatic.com') {
          return http.Response.bytes(
            capsuleBytes,
            200,
            headers: const <String, String>{'content-type': 'image/jpeg'},
          );
        }
        throw StateError('Unexpected request to ${request.url}');
      }),
    );

    final result = await const CoverArtService().resolveCover(
      game,
      coverArtProviderMode: CoverArtProviderMode.bundledProxy,
      coverArtProxyConfig: const CoverArtProxyConfig(
        url: 'https://proxy.example.test',
        token: 'proxy-token',
      ),
    );

    expect(result.source, CoverArtSource.steamStoreApi);
    expect(await cacheFile.readAsBytes(), capsuleBytes);
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

class _PrimaryExeRustBridgeService extends NoOpRustBridgeService {
  const _PrimaryExeRustBridgeService(this.executablePaths);

  final Map<String, String> executablePaths;

  @override
  Future<String?> discoverPrimaryExe(String folder) async =>
      executablePaths[folder];
}

class _SteamLibraryFixture {
  const _SteamLibraryFixture({
    required this.gamePath,
    required this.preferredBytes,
  });

  final String gamePath;
  final List<int> preferredBytes;
}

Future<_SteamLibraryFixture> _writeSteamLibraryFixture(
  Directory tempDir,
) async {
  final steamApps = Directory(p.join(tempDir.path, 'Steam', 'steamapps'));
  final commonDir = Directory(p.join(steamApps.path, 'common'));
  final gameDir = Directory(p.join(commonDir.path, 'Battlefield 6'));
  await gameDir.create(recursive: true);
  await File(p.join(steamApps.path, 'appmanifest_2807960.acf')).writeAsString(
    '"AppState"\n'
    '{\n'
    '  "appid" "2807960"\n'
    '  "name" "Battlefield 6"\n'
    '  "installdir" "Battlefield 6"\n'
    '}\n',
  );

  final libraryCache = Directory(
    p.join(tempDir.path, 'Steam', 'appcache', 'librarycache', '2807960'),
  );
  await libraryCache.create(recursive: true);
  await File(
    p.join(libraryCache.path, '8b06f13e9fd82e1a436ffdca4e1de118ee4a9ed2.jpg'),
  ).writeAsBytes(_fakePngHeader(width: 32, height: 32));

  final preferredBytes = _fakePngHeader(width: 300, height: 450);
  final capsuleDir = Directory(
    p.join(libraryCache.path, '64fffd4bdc67e07b180cc695edcbcb8d1e96f1a6'),
  );
  await capsuleDir.create(recursive: true);
  await File(
    p.join(capsuleDir.path, 'library_capsule.jpg'),
  ).writeAsBytes(preferredBytes);

  return _SteamLibraryFixture(
    gamePath: gameDir.path,
    preferredBytes: preferredBytes,
  );
}

Future<File> _writeCachedCover(
  Directory tempDir,
  String gamePath,
  List<int> bytes,
) async {
  final file = _cachedCoverFile(tempDir, gamePath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  return file;
}

Future<void> _writeCachedCoverSource(
  Directory tempDir,
  String gamePath,
  CoverArtSource source,
) {
  final cover = _cachedCoverFile(tempDir, gamePath);
  return File(p.setExtension(cover.path, '.source')).writeAsString(source.name);
}

File _cachedCoverFile(Directory tempDir, String gamePath) {
  return File(
    p.join(
      tempDir.path,
      'Compact Games',
      'covers',
      '${_cacheKeyForPath(gamePath)}.img',
    ),
  );
}

String _cacheKeyForPath(String path) {
  return base64UrlEncode(utf8.encode(path.toLowerCase())).replaceAll('=', '');
}

List<int> _fakePngHeader({required int width, required int height}) {
  final bytes = List<int>.filled(32, 0);
  bytes.setRange(0, 8, const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  bytes.setRange(12, 16, const <int>[73, 72, 68, 82]);
  _writeUint32BE(bytes, 16, width);
  _writeUint32BE(bytes, 20, height);
  return bytes;
}

void _writeUint32BE(List<int> bytes, int offset, int value) {
  bytes[offset] = (value >> 24) & 0xff;
  bytes[offset + 1] = (value >> 16) & 0xff;
  bytes[offset + 2] = (value >> 8) & 0xff;
  bytes[offset + 3] = value & 0xff;
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
