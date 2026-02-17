import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'core/constants/app_constants.dart';
import 'services/rust_bridge_service.dart';
import 'src/rust/frb_generated.dart';

final _windowListener = _PressPlayWindowListener();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Flutter-Rust bridge and Rust core
  await _initRustBridge();
  RustBridgeService.instance.initApp();

  await windowManager.ensureInitialized();
  windowManager.addListener(_windowListener);

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

const bool _preferDebugRustDll = bool.fromEnvironment(
  'PRESSPLAY_PREFER_DEBUG_RUST_DLL',
  defaultValue: false,
);

Future<void> _initRustBridge() async {
  final candidates = _rustLibraryCandidates();
  Object? lastError;

  for (final path in candidates) {
    try {
      await RustLib.init(externalLibrary: ExternalLibrary.open(path));
      debugPrint('[rust] Loaded library: $path');
      return;
    } catch (e) {
      lastError = e;
      _safeDisposeRustLib();
      debugPrint('[rust] Failed loading $path: $e');
    }
  }

  throw StateError(
    'Failed to initialize Rust library. Tried: ${candidates.join(', ')}. Last error: $lastError',
  );
}

void _safeDisposeRustLib() {
  try {
    RustLib.dispose();
  } catch (_) {
    // Ignore dispose failures when init never completed.
  }
}

List<String> _rustLibraryCandidates() {
  const releaseDll = 'rust/target/release/pressplay_core.dll';
  const debugDll = 'rust/target/debug/pressplay_core.dll';

  if (kReleaseMode) {
    return const [releaseDll];
  }

  return _preferDebugRustDll
      ? const [debugDll, releaseDll]
      : const [releaseDll, debugDll];
}

class _PressPlayWindowListener extends WindowListener {
  @override
  void onWindowClose() {
    RustBridgeService.instance.persistCompressionHistory();
  }
}
