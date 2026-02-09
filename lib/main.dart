import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'core/constants/app_constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(
      AppConstants.defaultWindowWidth,
      AppConstants.defaultWindowHeight,
    ),
    minimumSize: Size(
      AppConstants.minWindowWidth,
      AppConstants.minWindowHeight,
    ),
    center: true,
    title: AppConstants.appName,
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const PressPlayApp());
}
