import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pressplay/l10n/app_localizations.dart';
import 'core/localization/app_locale.dart';
import 'core/navigation/app_routes.dart';
import 'core/performance/perf_overlay.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/widgets/desktop_window_frame.dart';
import 'features/games/presentation/widgets/compression_activity_overlay.dart';
import 'providers/automation/automation_settings_sync.dart';
import 'models/watcher_event.dart';
import 'providers/games/game_list_provider.dart';
import 'providers/localization/locale_provider.dart';
import 'providers/system/route_state_provider.dart';
import 'providers/system/tray_status_sync_provider.dart';
import 'services/unsupported_report_sync_service.dart';

/// Cached theme — buildAppTheme() is pure with no dynamic inputs,
/// so it only needs to run once.
final ThemeData _appTheme = buildAppTheme();

final bool _usesCustomDesktopFrame =
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

class PressPlayApp extends StatelessWidget {
  const PressPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PressPlayRoot();
  }
}

class _PressPlayRoot extends ConsumerWidget {
  const _PressPlayRoot();

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final container = ProviderScope.containerOf(context, listen: false);
      UnsupportedReportSyncService.instance.notePotentialChange(container);
      unawaited(() async {
        try {
          await ref.read(rustBridgeServiceProvider).fetchCommunityUnsupportedList();
        } catch (_) {
          // Best effort; cache/interval handled in Rust.
        }
      }());
    });
  }

  @override
  void dispose() {
    unawaited(_watcherEventsSub?.cancel());
    super.dispose();
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
