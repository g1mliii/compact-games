import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:compact_games/l10n/app_localizations.dart';
import 'core/localization/app_locale.dart';
import 'core/navigation/app_routes.dart';
import 'core/performance/perf_overlay.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/widgets/desktop_window_frame.dart';
import 'features/games/presentation/widgets/compression_activity_overlay.dart';
import 'providers/automation/automation_settings_sync.dart';
import 'providers/compression/completed_game_refresh.dart';
import 'models/watcher_event.dart';
import 'models/automation_state.dart';
import 'providers/games/game_list_provider.dart';
import 'providers/localization/locale_provider.dart';
import 'providers/system/route_state_provider.dart';
import 'providers/settings/settings_provider.dart';
import 'providers/system/tray_status_sync_provider.dart';
import 'providers/update/update_provider.dart';
import 'services/unsupported_report_sync_service.dart';

/// Cached theme — buildAppTheme() is pure with no dynamic inputs,
/// so it only needs to run once.
final ThemeData _appTheme = buildAppTheme();

final bool _usesCustomDesktopFrame =
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

class CompactGamesApp extends StatelessWidget {
  const CompactGamesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CompactGamesRoot();
  }
}

class _CompactGamesRoot extends ConsumerWidget {
  const _CompactGamesRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeObserver = ref.read(routeStateObserverProvider);
    final locale = ref.watch(effectiveLocaleProvider);
    return Column(
      children: [
        // Effect-only watcher — zero pixels, never causes child rebuilds.
        const _EffectProviderHost(),
        Expanded(
          child: PerfOverlayManager(
            child: MaterialApp(
              title: AppConstants.appName,
              debugShowCheckedModeBanner: false,
              theme: _appTheme,
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: appSupportedLocales,
              navigatorObservers: [routeObserver],
              builder: _appBuilder,
              initialRoute: AppRoutes.home,
              onGenerateRoute: AppRoutes.onGenerateRoute,
            ),
          ),
        ),
      ],
    );
  }

  Widget _appBuilder(BuildContext context, Widget? child) {
    final content = _AppRouteShell(child: child ?? const SizedBox.shrink());
    if (_usesCustomDesktopFrame) {
      return DesktopWindowFrame(child: content);
    }
    return content;
  }
}

/// Invisible widget that eagerly watches effect providers.
/// Separated from the MaterialApp tree so provider re-evaluations
/// never trigger MaterialApp or its children to rebuild.
class _EffectProviderHost extends ConsumerStatefulWidget {
  const _EffectProviderHost();

  @override
  ConsumerState<_EffectProviderHost> createState() =>
      _EffectProviderHostState();
}

class _EffectProviderHostState extends ConsumerState<_EffectProviderHost> {
  StreamSubscription<WatcherEvent>? _watcherEventsSub;
  StreamSubscription<List<AutomationJob>>? _automationQueueSub;
  Map<String, AutomationJobStatus> _automationStatusesByKey =
      <String, AutomationJobStatus>{};

  @override
  void initState() {
    super.initState();
    try {
      _watcherEventsSub = ref
          .read(rustBridgeServiceProvider)
          .watchWatcherEvents()
          .listen((event) {
            if (event.type != WatcherEventType.uninstalled) {
              return;
            }
            ref
                .read(gameListProvider.notifier)
                .removeGameByPath(event.gamePath);
          });
    } catch (_) {
      // Tests and partially initialized startup paths may not have FRB ready.
      _watcherEventsSub = null;
    }
    try {
      _automationQueueSub = ref
          .read(rustBridgeServiceProvider)
          .watchAutomationQueue()
          .listen(_handleAutomationQueueUpdate);
    } catch (_) {
      _automationQueueSub = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final container = ProviderScope.containerOf(context, listen: false);
      UnsupportedReportSyncService.instance.notePotentialChange(container);
      unawaited(() async {
        // Community-list fetch and settings load run in parallel.
        final communityFuture = ref
            .read(rustBridgeServiceProvider)
            .fetchCommunityUnsupportedList();

        // Await settings so autoCheckUpdates is always respected, even on
        // first launch when settings haven't resolved before this callback.
        var autoCheckUpdates = true;
        try {
          autoCheckUpdates =
              (await ref.read(settingsProvider.future)).settings.autoCheckUpdates;
        } catch (_) {}

        try {
          await communityFuture;
        } catch (_) {
          // Best effort; cache/interval handled in Rust.
        }

        // Auto-check for app updates after both complete.
        try {
          if (autoCheckUpdates) {
            await ref.read(updateProvider.notifier).checkForUpdate();
          }
        } catch (_) {
          // Best effort; rate-limited in Rust.
        }
      }());
    });
  }

  @override
  void dispose() {
    unawaited(_watcherEventsSub?.cancel());
    unawaited(_automationQueueSub?.cancel());
    super.dispose();
  }

  void _handleAutomationQueueUpdate(List<AutomationJob> jobs) {
    final previousStatuses = _automationStatusesByKey;
    final nextStatuses = <String, AutomationJobStatus>{};

    for (final job in jobs) {
      final key = _automationJobKey(job);
      nextStatuses[key] = job.status;

      final previousStatus = previousStatuses[key];
      if (job.status != AutomationJobStatus.completed ||
          previousStatus == null ||
          previousStatus == AutomationJobStatus.completed) {
        continue;
      }

      unawaited(
        refreshCompletedCompressionGame(
          read: ref.read,
          gamePath: job.gamePath,
          completedAt: DateTime.now(),
        ),
      );
    }

    _automationStatusesByKey = nextStatuses;
  }

  String _automationJobKey(AutomationJob job) {
    return '${job.gamePath.toLowerCase()}|${job.kind.name}|${job.queuedAt.microsecondsSinceEpoch}';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(automationSettingsSyncProvider);
    ref.watch(trayStatusSyncProvider);
    return const SizedBox.shrink();
  }
}

class _AppRouteShell extends StatelessWidget {
  const _AppRouteShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: child),
        const RepaintBoundary(child: CompressionActivityOverlay()),
      ],
    );
  }
}
