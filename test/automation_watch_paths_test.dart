import 'package:flutter_test/flutter_test.dart';
import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/providers/automation/automation_settings_sync.dart';

void main() {
  test(
    'discovered automation watch paths stay stable across metadata-only game updates',
    () {
      final before = AutomationDiscoveredWatchPaths.fromGames([
        GameInfo(
          name: 'Counter-Strike 2',
          path:
              r'C:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive',
          platform: Platform.steam,
          sizeBytes: 40,
        ),
      ]);
      final after = AutomationDiscoveredWatchPaths.fromGames([
        GameInfo(
          name: 'Counter-Strike 2',
          path:
              r'C:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive',
          platform: Platform.steam,
          sizeBytes: 40,
          isCompressed: true,
          compressedSize: 30,
        ),
      ]);

      expect(after, before);
      expect(after.paths, before.paths);
    },
  );

  test(
    'automation watch paths include discovered games and dedupe equivalents',
    () {
      final watchPaths = buildAutomationWatchPaths(
        customFolders: const [
          r'C:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive\',
        ],
        games: [
          GameInfo(
            name: 'Counter-Strike 2',
            path:
                r'c:/SteamLibrary/steamapps/common/Counter-Strike Global Offensive',
            platform: Platform.steam,
            sizeBytes: 40,
          ),
          GameInfo(
            name: 'Hades',
            path: r'D:\Games\Hades',
            platform: Platform.epicGames,
            sizeBytes: 20,
          ),
        ],
      );

      expect(watchPaths, const [
        r'C:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive\',
        r'D:\Games\Hades',
      ]);
    },
  );

  test(
    'automation watch paths skip unsupported, excluded, and application entries',
    () {
      final watchPaths = buildAutomationWatchPaths(
        customFolders: const [],
        games: [
          GameInfo(
            name: 'Unsupported',
            path: r'C:\Games\Unsupported',
            platform: Platform.steam,
            sizeBytes: 10,
            isUnsupported: true,
          ),
          GameInfo(
            name: 'Excluded',
            path: r'C:\Games\Excluded',
            platform: Platform.steam,
            sizeBytes: 10,
            excluded: true,
          ),
          GameInfo(
            name: 'Utility App',
            path: r'C:\Apps\Tool',
            platform: Platform.application,
            sizeBytes: 10,
          ),
        ],
      );

      expect(watchPaths, isEmpty);
    },
  );
}
