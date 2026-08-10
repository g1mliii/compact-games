import 'package:compact_games/features/games/presentation/widgets/home_cover_art_nudge.dart';
import 'package:compact_games/features/games/presentation/widgets/home_update_banner.dart';
import 'package:compact_games/providers/compression/compression_progress_provider.dart';
import 'package:compact_games/providers/compression/compression_state.dart';
import 'package:compact_games/providers/update/update_provider.dart';
import 'package:compact_games/providers/update/update_status_presentation.dart';
import 'package:compact_games/src/rust/api/update.dart' as rust_update;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  testWidgets('available update downloads inline and can be dismissed', (
    tester,
  ) async {
    var downloadCalls = 0;
    await _pumpBanner(
      tester,
      state: UpdateState(status: UpdateStatus.available, info: _updateInfo()),
      onDownload: () async {
        downloadCalls += 1;
      },
    );

    expect(find.byKey(homeUpdateBannerKey), findsOneWidget);
    expect(find.text('Update available: v0.2.5'), findsOneWidget);

    await tester.tap(find.byKey(homeUpdateActionKey));
    await tester.pump();
    expect(downloadCalls, 1);

    await tester.tap(find.byKey(homeUpdateDismissKey));
    await tester.pump();
    expect(find.byKey(homeUpdateBannerKey), findsNothing);
  });

  testWidgets('downloading update shows progress without actions', (
    tester,
  ) async {
    await _pumpBanner(
      tester,
      state: UpdateState(status: UpdateStatus.downloading, info: _updateInfo()),
    );

    expect(find.byKey(homeUpdateBannerKey), findsOneWidget);
    expect(find.byKey(homeUpdateProgressKey), findsOneWidget);
    expect(find.byKey(homeUpdateActionKey), findsNothing);
    expect(find.byKey(homeUpdateDismissKey), findsNothing);
  });

  testWidgets('known download error exposes retry and dismissal', (
    tester,
  ) async {
    var downloadCalls = 0;
    await _pumpBanner(
      tester,
      state: UpdateState(
        status: UpdateStatus.error,
        info: _updateInfo(),
        error: 'checksum mismatch',
        errorFromDownload: true,
      ),
      onDownload: () async {
        downloadCalls += 1;
      },
    );

    expect(find.text('Update failed'), findsOneWidget);
    await tester.tap(find.byKey(homeUpdateActionKey));
    await tester.pump();
    expect(downloadCalls, 1);
    expect(find.byKey(homeUpdateDismissKey), findsOneWidget);
  });

  testWidgets('downloaded update installs inline and can be dismissed', (
    tester,
  ) async {
    var installCalls = 0;
    await _pumpBanner(
      tester,
      state: UpdateState(
        status: UpdateStatus.downloaded,
        info: _updateInfo(),
        installerPath: r'C:\updates\CompactGames-Setup-0.2.5.exe',
      ),
      onInstall: () async {
        installCalls += 1;
      },
    );

    expect(find.text('Update downloaded and ready to install'), findsOneWidget);
    final installAction = find.byKey(homeUpdateActionKey);
    expect(
      find.descendant(
        of: installAction,
        matching: find.byIcon(updateInstallRestartIcon),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: installAction,
        matching: find.byIcon(LucideIcons.rocket),
      ),
      findsNothing,
    );
    await tester.tap(installAction);
    await tester.pump();
    expect(installCalls, 1);

    // Otherwise the banner outranks every other home surface until restart.
    await tester.tap(find.byKey(homeUpdateDismissKey));
    await tester.pump();
    expect(find.byKey(homeUpdateBannerKey), findsNothing);
  });

  testWidgets('dismissing an available update still surfaces its failure', (
    tester,
  ) async {
    final notifier = _TestUpdateNotifier(
      UpdateState(status: UpdateStatus.available, info: _updateInfo()),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateProvider.overrideWith(() => notifier),
          selfUpdatesEnabledProvider.overrideWithValue(true),
          activeCompressionUiModelProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: Scaffold(body: HomeUpdateBanner())),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(homeUpdateDismissKey));
    await tester.pump();
    expect(find.byKey(homeUpdateBannerKey), findsNothing);

    notifier.emit(
      UpdateState(
        status: UpdateStatus.error,
        info: _updateInfo(),
        error: 'checksum mismatch',
        errorFromDownload: true,
      ),
    );
    await tester.pump();

    expect(find.byKey(homeUpdateBannerKey), findsOneWidget);
    expect(find.text('Update failed'), findsOneWidget);
  });

  testWidgets('active compression has priority over update banner', (
    tester,
  ) async {
    await _pumpBanner(
      tester,
      state: UpdateState(status: UpdateStatus.available, info: _updateInfo()),
      compression: const CompressionActivityUiModel(
        type: CompressionJobType.compression,
        gameName: 'Test Game',
        filesProcessed: 1,
        filesTotal: 10,
        percent: 10,
        bytesDelta: 1024,
        hasKnownFileTotal: true,
        isFileCountApproximate: false,
        canCancel: true,
      ),
    );

    expect(find.byKey(homeUpdateBannerKey), findsNothing);
  });

  testWidgets('update banner has priority over cover-art nudge', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateProvider.overrideWith(
            () => _TestUpdateNotifier(
              UpdateState(status: UpdateStatus.available, info: _updateInfo()),
            ),
          ),
          activeCompressionUiModelProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Column(children: [HomeUpdateBanner(), HomeCoverArtNudge()]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(homeUpdateBannerKey), findsOneWidget);
    expect(find.textContaining('cover art'), findsNothing);
  });

  testWidgets('Steam-managed builds never show the standalone banner', (
    tester,
  ) async {
    await _pumpBanner(
      tester,
      state: UpdateState(status: UpdateStatus.available, info: _updateInfo()),
      selfUpdatesEnabled: false,
    );

    expect(find.byKey(homeUpdateBannerKey), findsNothing);
  });
}

Future<void> _pumpBanner(
  WidgetTester tester, {
  required UpdateState state,
  Future<void> Function()? onDownload,
  Future<void> Function()? onInstall,
  CompressionActivityUiModel? compression,
  bool selfUpdatesEnabled = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        updateProvider.overrideWith(
          () => _TestUpdateNotifier(
            state,
            onDownload: onDownload,
            onInstall: onInstall,
          ),
        ),
        selfUpdatesEnabledProvider.overrideWithValue(selfUpdatesEnabled),
        activeCompressionUiModelProvider.overrideWithValue(compression),
      ],
      child: const MaterialApp(home: Scaffold(body: HomeUpdateBanner())),
    ),
  );
  await tester.pump();
  await tester.pump();
}

rust_update.UpdateCheckResult _updateInfo() {
  return rust_update.UpdateCheckResult(
    updateAvailable: true,
    manifestAvailable: true,
    latestVersion: '0.2.5',
    downloadUrl: 'https://example.invalid/CompactGames-Setup-0.2.5.exe',
    releaseNotes: 'Small fixes',
    checksumSha256: 'abc123',
    publishedAt: '2026-08-08T00:00:00Z',
  );
}

class _TestUpdateNotifier extends UpdateNotifier {
  _TestUpdateNotifier(this.initialState, {this.onDownload, this.onInstall});

  final UpdateState initialState;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onInstall;

  @override
  Future<UpdateState> build() async => initialState;

  void emit(UpdateState next) {
    state = AsyncValue.data(next);
  }

  @override
  Future<void> downloadUpdate() async {
    await onDownload?.call();
  }

  @override
  Future<void> launchInstaller() async {
    await onInstall?.call();
  }
}
