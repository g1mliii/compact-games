import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compact_games/features/settings/presentation/sections/about_section.dart';
import 'package:compact_games/models/app_settings.dart';
import 'package:compact_games/providers/settings/settings_persistence.dart';
import 'package:compact_games/providers/settings/settings_provider.dart';
import 'package:compact_games/providers/update/update_provider.dart';
import 'package:compact_games/src/rust/api/update.dart' as rust_update;

void main() {
  testWidgets('About section keeps a retry check action after update errors', (
    WidgetTester tester,
  ) async {
    var checkCalls = 0;
    final persistence = _MemorySettingsPersistence(
      const AppSettings(autoCheckUpdates: true),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsPersistenceProvider.overrideWithValue(persistence),
          updateProvider.overrideWith(
            () => _TestUpdateNotifier(
              initialState: const UpdateState(
                status: UpdateStatus.error,
                error: 'network failed',
              ),
              onCheck: () async {
                checkCalls += 1;
              },
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: AboutSection())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Update failed'), findsOneWidget);
    expect(find.text('Retry Check'), findsOneWidget);

    await tester.tap(find.text('Retry Check'));
    await tester.pump();

    expect(checkCalls, 1);
  });

  testWidgets(
    'About section keeps a retry download action after download errors',
    (WidgetTester tester) async {
      var downloadCalls = 0;
      final persistence = _MemorySettingsPersistence(
        const AppSettings(autoCheckUpdates: true),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsPersistenceProvider.overrideWithValue(persistence),
            updateProvider.overrideWith(
              () => _TestUpdateNotifier(
                initialState: const UpdateState(
                  status: UpdateStatus.error,
                  info: rust_update.UpdateCheckResult(
                    updateAvailable: true,
                    latestVersion: '0.2.0',
                    downloadUrl:
                        'https://example.invalid/CompactGames-Setup-0.2.0.exe',
                    releaseNotes: '',
                    checksumSha256: '',
                    publishedAt: '',
                  ),
                  error: 'checksum mismatch',
                ),
                onDownload: () async {
                  downloadCalls += 1;
                },
              ),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: AboutSection())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retry Download'), findsOneWidget);

      await tester.tap(find.text('Retry Download'));
      await tester.pump();

      expect(downloadCalls, 1);
    },
  );

  test(
    'launchInstaller flushes settings and exits through injected close path',
    () async {
      final persistence = _MemorySettingsPersistence(
        const AppSettings(autoCheckUpdates: true),
      );
      var launchedInstallerPath = '';
      var exitCalls = 0;

      final container = ProviderContainer(
        overrides: [
          settingsPersistenceProvider.overrideWithValue(persistence),
          installerLauncherProvider.overrideWithValue((installerPath) async {
            launchedInstallerPath = installerPath;
          }),
          updateExitRequestProvider.overrideWithValue(() async {
            exitCalls += 1;
          }),
          updateProvider.overrideWith(
            () => _TestUpdateNotifier(
              initialState: UpdateState(
                status: UpdateStatus.downloaded,
                installerPath: r'C:\updates\CompactGames-Setup-0.2.0.exe',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      await container.read(updateProvider.future);
      container.read(settingsProvider.notifier).setAutoCheckUpdates(false);

      await container.read(updateProvider.notifier).launchInstaller();

      expect(launchedInstallerPath, r'C:\updates\CompactGames-Setup-0.2.0.exe');
      expect(exitCalls, 1);
      expect(persistence.savedSettings?.autoCheckUpdates, isFalse);
    },
  );
}

class _MemorySettingsPersistence implements SettingsPersistence {
  _MemorySettingsPersistence(this._current);

  AppSettings _current;
  AppSettings? savedSettings;

  @override
  Future<AppSettings> load() async {
    return _current;
  }

  @override
  Future<void> save(AppSettings settings) async {
    _current = settings;
    savedSettings = settings;
  }
}

class _TestUpdateNotifier extends UpdateNotifier {
  _TestUpdateNotifier({
    required this.initialState,
    this.onCheck,
    this.onDownload,
  });

  final UpdateState initialState;
  final Future<void> Function()? onCheck;
  final Future<void> Function()? onDownload;

  @override
  Future<UpdateState> build() async {
    return initialState;
  }

  @override
  Future<void> checkForUpdate() async {
    await onCheck?.call();
  }

  @override
  Future<void> downloadUpdate() async {
    await onDownload?.call();
  }
}
