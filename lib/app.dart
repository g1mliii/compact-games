import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/navigation/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/widgets/desktop_window_frame.dart';
import 'providers/automation/automation_settings_sync.dart';

class PressPlayApp extends StatelessWidget {
  const PressPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: Consumer(
        builder: (context, ref, child) {
          // Eagerly watch so automation config is pushed to Rust
          // whenever settings change.
          ref.watch(automationSettingsSyncProvider);
          return child!;
        },
        child: MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          builder: (context, child) {
            final content = child ?? const SizedBox.shrink();
            if (!_usesCustomDesktopFrame) {
              return content;
            }
            return DesktopWindowFrame(child: content);
          },
          initialRoute: AppRoutes.home,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
  }
}

final bool _usesCustomDesktopFrame =
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
