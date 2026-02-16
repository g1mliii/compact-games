import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'core/constants/app_constants.dart';
import 'services/rust_bridge_service.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Flutter-Rust bridge and Rust core
  await RustLib.init();
  RustBridgeService.instance.initApp();

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
