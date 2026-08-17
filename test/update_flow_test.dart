import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:compact_games/features/settings/presentation/sections/about_section.dart';
import 'package:compact_games/models/app_settings.dart';
import 'package:compact_games/l10n/app_localizations.dart';
import 'package:compact_games/l10n/app_localizations_en.dart';
import 'package:compact_games/providers/update/update_status_presentation.dart';
import 'package:compact_games/providers/games/game_list_provider.dart';
import 'package:compact_games/providers/settings/settings_persistence.dart';
import 'package:compact_games/providers/settings/settings_provider.dart';
import 'package:compact_games/providers/system/platform_shell_provider.dart';
import 'package:compact_games/providers/update/update_provider.dart';
import 'package:compact_games/services/platform_shell_service.dart';
import 'package:compact_games/services/rust_bridge_service.dart';
import 'package:compact_games/services/update_installer_cache.dart';
import 'package:compact_games/src/rust/api/update.dart' as rust_update;

import 'support/noop_rust_bridge_service.dart';

void main() {
  testWidgets('About section opens the public website and privacy policy', (
    WidgetTester tester,
  ) async {
    final shell = _RecordingUriShellService();
    final persistence = _MemorySettingsPersistence(
      const AppSettings(autoCheckUpdates: true),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsPersistenceProvider.overrideWithValue(persistence),
          platformShellServiceProvider.overrideWithValue(shell),
        ],
        child: const MaterialApp(home: Scaffold(body: AboutSection())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Website'));
    await tester.tap(find.text('Privacy policy'));

    expect(shell.openedUris, <String>[
      'https://compactgames.app/',
      'https://compactgames.app/privacy.html',
    ]);
  });

  testWidgets(
    'Steam builds show Steam-managed updates without updater actions',
    (WidgetTester tester) async {
      final persistence = _MemorySettingsPersistence(
        const AppSettings(autoCheckUpdates: true),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsPersistenceProvider.overrideWithValue(persistence),
            selfUpdatesEnabledProvider.overrideWithValue(false),
          ],
          child: const MaterialApp(home: Scaffold(body: AboutSection())),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Updates are managed automatically by Steam.'),
        findsOneWidget,
      );
      expect(find.text('Check for updates'), findsNothing);
      expect(find.text('Check for updates automatically'), findsNothing);
    },
  );

  testWidgets('About section confirms a check that found no update', (
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
              initialState: const UpdateState(status: UpdateStatus.upToDate),
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

    // The whole point: a completed check says so instead of silently returning
    // to the bare "Check for updates" button it started from.
    expect(find.text('You are on the latest version'), findsOneWidget);

    // A release can be cut minutes later, so re-checking stays available.
    await tester.tap(find.text('Check again'));
    await tester.pump();
    expect(checkCalls, 1);
  });

  test('a check that finds nothing lands on upToDate, not idle', () async {
    final bridge = _RecordingCheckBridge();
    final container = _realNotifierContainer(bridge: bridge);

    await container.read(updateProvider.future);
    expect(container.read(updateProvider).value?.status, UpdateStatus.idle);

    final startedAt = DateTime.now();
    await container.read(updateProvider.notifier).checkForUpdate();
    final elapsed = DateTime.now().difference(startedAt);

    expect(container.read(updateProvider).value?.status, UpdateStatus.upToDate);
    expect(bridge.forceRefreshArguments, <bool>[true]);
    // A fast check can return inside one frame; without the floor the spinner
    // would never become visible and the button would look inert.
    expect(elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 500)));
  });

  test('background checks are not held back by the spinner floor', () async {
    final bridge = _RecordingCheckBridge();
    final container = _realNotifierContainer(bridge: bridge);

    await container.read(updateProvider.future);

    final startedAt = DateTime.now();
    await container
        .read(updateProvider.notifier)
        .checkForUpdate(automatic: true);
    final elapsed = DateTime.now().difference(startedAt);

    expect(container.read(updateProvider).value?.status, UpdateStatus.upToDate);
    expect(bridge.forceRefreshArguments, <bool>[false]);
    expect(elapsed, lessThan(const Duration(milliseconds: 400)));
  });

  test('an unreachable manifest is never reported as up to date', () async {
    // Rust answers a missing latest.json with updateAvailable: false, which is
    // indistinguishable from a real no-update result without this flag.
    final container = _realNotifierContainer(
      bridge: const _ManifestUnavailableBridge(),
    );
    await container.read(updateProvider.future);

    await container.read(updateProvider.notifier).checkForUpdate();

    final state = container.read(updateProvider).value!;
    expect(state.status, UpdateStatus.error);
    expect(state.status, isNot(UpdateStatus.upToDate));
    // "Could not find out" must not be dressed up as "you are current".
    expect(state.errorFromDownload, isFalse);
  });

  test('a failed check is not reported as a failed download', () async {
    final container = _realNotifierContainer(
      bridge: const _ThrowingCheckBridge(),
    );
    await container.read(updateProvider.future);
    final notifier = container.read(updateProvider.notifier);

    // Seed the state the way a successful earlier check would: info is set and
    // is never cleared, which is what used to misclassify the failure below.
    notifier.state = AsyncValue.data(
      UpdateState(
        status: UpdateStatus.available,
        info: rust_update.UpdateCheckResult(
          updateAvailable: true,
          manifestAvailable: true,
          latestVersion: '0.2.7',
          downloadUrl: 'https://example.invalid/CompactGames-Setup-0.2.7.exe',
          releaseNotes: '',
          checksumSha256: '',
          publishedAt: '',
        ),
      ),
    );

    await notifier.checkForUpdate();

    final state = container.read(updateProvider).value!;
    expect(state.status, UpdateStatus.error);
    expect(state.errorFromDownload, isFalse);

    final presentation = describeUpdateStatus(state, _en);
    expect(presentation.message, "Couldn't check for updates");
    expect(presentation.action?.label, 'Retry check');
  });

  test('up to date clears the release left by an earlier check', () async {
    final container = _realNotifierContainer();
    await container.read(updateProvider.future);
    final notifier = container.read(updateProvider.notifier);

    notifier.state = AsyncValue.data(
      UpdateState(
        status: UpdateStatus.available,
        info: rust_update.UpdateCheckResult(
          updateAvailable: true,
          manifestAvailable: true,
          latestVersion: '0.2.7',
          downloadUrl: 'https://example.invalid/CompactGames-Setup-0.2.7.exe',
          releaseNotes: '',
          checksumSha256: '',
          publishedAt: '',
        ),
      ),
    );

    await notifier.checkForUpdate();

    final state = container.read(updateProvider).value!;
    expect(state.status, UpdateStatus.upToDate);
    // A release that is no longer offered must not linger and be mistaken for
    // something downloadable.
    expect(state.info, isNull);
    expect(state.installerPath, isNull);
  });

  test('disabled self-updates make update checks a no-op', () async {
    final container = ProviderContainer(
      overrides: [selfUpdatesEnabledProvider.overrideWithValue(false)],
    );
    addTearDown(container.dispose);

    await container.read(updateProvider.future);
    await container.read(updateProvider.notifier).checkForUpdate();

    expect(container.read(updateProvider).value?.status, UpdateStatus.idle);
  });

  test('only in-flight work blocks a new update check', () {
    final info = rust_update.UpdateCheckResult(
      updateAvailable: true,
      manifestAvailable: true,
      latestVersion: '0.2.5',
      downloadUrl: 'https://example.invalid/CompactGames-Setup-0.2.5.exe',
      releaseNotes: '',
      checksumSha256: '',
      publishedAt: '',
    );

    // A re-published or superseded release must stay reachable, so every
    // settled state can start another check.
    for (final state in <UpdateState>[
      const UpdateState(),
      const UpdateState(status: UpdateStatus.error, error: 'offline'),
      UpdateState(status: UpdateStatus.available, info: info),
      UpdateState(status: UpdateStatus.downloaded, info: info),
      UpdateState(status: UpdateStatus.error, info: info, error: 'download'),
    ]) {
      expect(canStartUpdateCheck(state), isTrue, reason: '${state.status}');
    }

    for (final state in <UpdateState>[
      UpdateState(status: UpdateStatus.checking, info: info),
      UpdateState(status: UpdateStatus.downloading, info: info),
    ]) {
      expect(canStartUpdateCheck(state), isFalse, reason: '${state.status}');
    }
  });

  test('automatic checks additionally leave a ready installer alone', () {
    final info = rust_update.UpdateCheckResult(
      updateAvailable: true,
      manifestAvailable: true,
      latestVersion: '0.2.5',
      downloadUrl: 'https://example.invalid/CompactGames-Setup-0.2.5.exe',
      releaseNotes: '',
      checksumSha256: '',
      publishedAt: '',
    );

    expect(canStartAutomaticUpdateCheck(const UpdateState()), isTrue);
    expect(
      canStartAutomaticUpdateCheck(
        UpdateState(status: UpdateStatus.available, info: info),
      ),
      isTrue,
    );
    expect(
      canStartAutomaticUpdateCheck(
        UpdateState(status: UpdateStatus.error, info: info, error: 'download'),
      ),
      isTrue,
    );
    expect(
      canStartAutomaticUpdateCheck(
        UpdateState(
          status: UpdateStatus.downloaded,
          info: info,
          installerPath: r'C:\updates\CompactGames-Setup-0.2.5.exe',
        ),
      ),
      isFalse,
    );
  });

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

    // No release metadata means the check itself never landed, so the title
    // names that rather than blaming a download that was never attempted.
    expect(find.text("Couldn't check for updates"), findsOneWidget);
    expect(find.text('Retry check'), findsOneWidget);

    await tester.tap(find.text('Retry check'));
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
                    manifestAvailable: true,
                    latestVersion: '0.2.0',
                    downloadUrl:
                        'https://example.invalid/CompactGames-Setup-0.2.0.exe',
                    releaseNotes: '',
                    checksumSha256: '',
                    publishedAt: '',
                  ),
                  error: 'checksum mismatch',
                  errorFromDownload: true,
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

      expect(find.text('Retry download'), findsOneWidget);

      await tester.tap(find.text('Retry download'));
      await tester.pump();

      expect(downloadCalls, 1);
    },
  );

  test(
    'launchInstaller flushes settings before starting installer and exits',
    () async {
      final persistence = _MemorySettingsPersistence(
        const AppSettings(autoCheckUpdates: true),
      );
      var launchedInstallerPath = '';
      var exitCalls = 0;
      final lifecycle = <String>[];

      final container = ProviderContainer(
        overrides: [
          settingsPersistenceProvider.overrideWithValue(persistence),
          installerLauncherProvider.overrideWithValue((installerPath) async {
            lifecycle.add('installer');
            launchedInstallerPath = installerPath;
          }),
          updateExitRequestProvider.overrideWithValue(() async {
            lifecycle.add('exit');
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

      persistence.onSave = () => lifecycle.add('settings');

      await container.read(updateProvider.notifier).launchInstaller();

      expect(launchedInstallerPath, r'C:\updates\CompactGames-Setup-0.2.0.exe');
      expect(exitCalls, 1);
      expect(persistence.savedSettings?.autoCheckUpdates, isFalse);
      expect(lifecycle, <String>['settings', 'installer', 'exit']);
    },
  );
}

class _RecordingUriShellService extends PlatformShellService {
  final openedUris = <String>[];

  @override
  Future<bool> launchUri(String uri) async {
    openedUris.add(uri);
    return true;
  }
}

/// Container running the *real* [UpdateNotifier] against a stub bridge, so the
/// tests below exercise the actual check pipeline rather than a fake notifier.
ProviderContainer _realNotifierContainer({RustBridgeService? bridge}) {
  final container = ProviderContainer(
    overrides: [
      settingsPersistenceProvider.overrideWithValue(
        _MemorySettingsPersistence(const AppSettings(autoCheckUpdates: true)),
      ),
      rustBridgeServiceProvider.overrideWithValue(
        bridge ?? const NoOpRustBridgeService(),
      ),
      updateInstallerCacheProvider.overrideWithValue(
        UpdateInstallerCache(
          directoryResolver: () async =>
              Directory(p.join(Directory.systemTemp.path, 'cg-no-such-dir')),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

final AppLocalizations _en = AppLocalizationsEn();

/// Answers as Rust does when `latest.json` cannot be fetched: no update, and no
/// manifest to have learned that from.
class _ManifestUnavailableBridge extends NoOpRustBridgeService {
  const _ManifestUnavailableBridge();

  @override
  Future<rust_update.UpdateCheckResult> checkForUpdate({
    required String currentVersion,
    bool forceRefresh = false,
  }) async => rust_update.UpdateCheckResult(
    updateAvailable: false,
    manifestAvailable: false,
    latestVersion: currentVersion,
    downloadUrl: '',
    releaseNotes: '',
    checksumSha256: '',
    publishedAt: '',
  );
}

class _ThrowingCheckBridge extends NoOpRustBridgeService {
  const _ThrowingCheckBridge();

  @override
  Future<rust_update.UpdateCheckResult> checkForUpdate({
    required String currentVersion,
    bool forceRefresh = false,
  }) async => throw StateError('offline');
}

class _RecordingCheckBridge extends NoOpRustBridgeService {
  final List<bool> forceRefreshArguments = <bool>[];

  @override
  Future<rust_update.UpdateCheckResult> checkForUpdate({
    required String currentVersion,
    bool forceRefresh = false,
  }) {
    forceRefreshArguments.add(forceRefresh);
    return super.checkForUpdate(
      currentVersion: currentVersion,
      forceRefresh: forceRefresh,
    );
  }
}

class _MemorySettingsPersistence implements SettingsPersistence {
  _MemorySettingsPersistence(this._current);

  AppSettings _current;
  AppSettings? savedSettings;
  void Function()? onSave;

  @override
  Future<AppSettings> load() async {
    return _current;
  }

  @override
  Future<void> save(AppSettings settings) async {
    _current = settings;
    savedSettings = settings;
    onSave?.call();
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
  Future<void> checkForUpdate({bool automatic = false}) async {
    await onCheck?.call();
  }

  @override
  Future<void> downloadUpdate() async {
    await onDownload?.call();
  }
}
