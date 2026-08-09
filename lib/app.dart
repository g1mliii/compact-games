import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:compact_games/l10n/app_localizations.dart';
import 'core/lifecycle/app_window_visibility.dart';
import 'core/localization/app_locale.dart';
import 'core/navigation/app_routes.dart';
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
import 'providers/shell/shell_action_provider.dart';
import 'providers/system/route_state_provider.dart';
import 'providers/system/tray_status_sync_provider.dart';
import 'providers/update/update_check_coordinator.dart';
import 'services/shell_action_dispatcher.dart';
import 'services/prepare_uninstall_dispatcher.dart';
import 'services/shell_launch_args.dart';
import 'services/tray_service.dart';
import 'services/unsupported_report_sync_service.dart';

/// Cached theme — buildAppTheme() is pure with no dynamic inputs,
/// so it only needs to run once.
final ThemeData _appTheme = buildAppTheme();
final GlobalKey<NavigatorState> _appNavigatorKey = GlobalKey<NavigatorState>();

final bool _usesCustomDesktopFrame =
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

class CompactGamesApp extends StatelessWidget {
  const CompactGamesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CompactGamesRoot();
  }
}

class _CompactGamesRoot extends ConsumerStatefulWidget {
  const _CompactGamesRoot();

  @override
  ConsumerState<_CompactGamesRoot> createState() => _CompactGamesRootState();
}

class _CompactGamesRootState extends ConsumerState<_CompactGamesRoot> {
  late bool _isHiddenToTray;

  /// Route to rebuild the navigator stack with when the window is restored.
  /// Captured before the UI unmounts so hiding to the tray does not silently
  /// send the user back to the home screen.
  String _restoreRoute = AppRoutes.home;

  @override
  void initState() {
    super.initState();
    _isHiddenToTray = appWindowVisibilityController.isHiddenToTray;
    appWindowVisibilityController.addListener(_onVisibilityChanged);
  }

  @override
  void dispose() {
    appWindowVisibilityController.removeListener(_onVisibilityChanged);
    super.dispose();
  }

  void _onVisibilityChanged() {
    final isHidden = appWindowVisibilityController.isHiddenToTray;
    if (isHidden == _isHiddenToTray) {
      return;
    }
    if (isHidden) {
      _restoreRoute = ref.read(routeStateObserverProvider).currentRouteName;
    }
    setState(() {
      _isHiddenToTray = isHidden;
    });
    if (!isHidden) {
      ref.read(updateCheckCoordinatorProvider).onWindowVisible();
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeObserver = ref.read(routeStateObserverProvider);
    final locale = ref.watch(effectiveLocaleProvider);
    return Column(
      children: [
        // Effect-only watcher — zero pixels, never causes child rebuilds.
        // Deliberately a sibling of the UI subtree so background automation,
        // watcher and tray-status effects keep running while the window is
        // unmounted in the tray.
        const _EffectProviderHost(),
        Expanded(
          // While hidden in the tray the entire UI is unmounted rather than
          // kept offstage. Offstage retains every element, render object and
          // decoded image, which is what kept idle tray memory high; dropping
          // the subtree lets the framework release them and makes the
          // `trayHide` image-cache purge actually reclaim.
          child: _isHiddenToTray
              ? const SizedBox.shrink()
              : MaterialApp(
                  title: AppConstants.appName,
                  debugShowCheckedModeBanner: false,
                  theme: _appTheme,
                  locale: locale,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: appSupportedLocales,
                  navigatorObservers: [routeObserver],
                  navigatorKey: _appNavigatorKey,
                  builder: _appBuilder,
                  onGenerateInitialRoutes: _buildInitialRoutes,
                  onGenerateRoute: AppRoutes.onGenerateRoute,
                ),
        ),
      ],
    );
  }

  /// Rebuilds the navigator stack on (re)mount. Anything deeper than home is
  /// restored on top of home so the back button still works.
  List<Route<dynamic>> _buildInitialRoutes(String _) {
    final home = AppRoutes.onGenerateRoute(
      const RouteSettings(name: AppRoutes.home),
    );
    if (_restoreRoute == AppRoutes.home || _restoreRoute == '/') {
      return <Route<dynamic>>[home];
    }
    return <Route<dynamic>>[
      home,
      AppRoutes.onGenerateRoute(RouteSettings(name: _restoreRoute)),
    ];
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
  StreamSubscription<ShellActionRequest>? _shellActionSub;
  StreamSubscription<void>? _prepareUninstallSub;
  Future<void> _shellActionChain = Future<void>.value();
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
    _shellActionSub = ShellActionDispatcher.instance.requests.listen(
      _handleShellActionRequest,
    );
    _prepareUninstallSub = PrepareUninstallDispatcher.instance.requests.listen(
      (_) => _openPrepareUninstall(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final container = ProviderScope.containerOf(context, listen: false);
      UnsupportedReportSyncService.instance.notePotentialChange(container);
      // Instantiating the process-wide update coordinator arms its interval and
      // runs the first check. Deliberately after the first frame, so neither the
      // network call nor its disk follow-up competes with startup rendering.
      ref.read(updateCheckCoordinatorProvider);
      unawaited(() async {
        // Community-list fetch and settings load run in parallel.
        final communityFuture = ref
            .read(rustBridgeServiceProvider)
            .fetchCommunityUnsupportedList();

        try {
          await communityFuture;
        } catch (_) {
          // Best effort; cache/interval handled in Rust.
        }
      }());
    });
  }

  @override
  void dispose() {
    unawaited(_watcherEventsSub?.cancel());
    unawaited(_automationQueueSub?.cancel());
    unawaited(_shellActionSub?.cancel());
    unawaited(_prepareUninstallSub?.cancel());
    super.dispose();
  }

  void _handleShellActionRequest(ShellActionRequest request) {
    _shellActionChain = _shellActionChain
        .catchError((_) {})
        .then((_) => ref.read(shellActionExecutorProvider).execute(request))
        .catchError((Object error) {
          debugPrint('[shell] action failed: $error');
        });
  }

  void _openPrepareUninstall() {
    unawaited(TrayService.instance.showAndFocusWindow());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _appNavigatorKey.currentState;
      if (navigator == null) return;
      if (ref.read(currentRouteNameProvider) == AppRoutes.settingsRestore) {
        return;
      }
      navigator.pushNamed(AppRoutes.settingsRestore);
    });
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
