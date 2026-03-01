import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/navigation/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/widgets/desktop_window_frame.dart';
import 'providers/automation/automation_settings_sync.dart';
import 'providers/system/tray_status_sync_provider.dart';

/// Cached theme — buildAppTheme() is pure with no dynamic inputs,
/// so it only needs to run once.
final ThemeData _appTheme = buildAppTheme();

final bool _usesCustomDesktopFrame =
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

class PressPlayApp extends StatelessWidget {
  const PressPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: Column(
        children: [
          // Effect-only watcher — zero pixels, never causes child rebuilds.
          const _EffectProviderHost(),
          Expanded(
            child: MaterialApp(
              title: AppConstants.appName,
              debugShowCheckedModeBanner: false,
              theme: _appTheme,
              builder: _usesCustomDesktopFrame ? _wrapDesktopFrame : null,
              initialRoute: AppRoutes.home,
              onGenerateRoute: AppRoutes.onGenerateRoute,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _wrapDesktopFrame(BuildContext context, Widget? child) {
    return DesktopWindowFrame(child: child ?? const SizedBox.shrink());
  }
}

/// Invisible widget that eagerly watches effect providers.
/// Separated from the MaterialApp tree so provider re-evaluations
/// never trigger MaterialApp or its children to rebuild.
class _EffectProviderHost extends ConsumerWidget {
  const _EffectProviderHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(automationSettingsSyncProvider);
    ref.watch(trayStatusSyncProvider);
    return const SizedBox.shrink();
  }
}
