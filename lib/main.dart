import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/performance/pressplay_shader_warm_up.dart';
import 'core/performance/ui_memory_lifecycle.dart';
import 'services/rust_bridge_service.dart';
import 'services/tray_service.dart';
import 'services/window_close_coordinator.dart';
import 'src/rust/frb_generated.dart';

final _windowListener = _PressPlayWindowListener();
final _memoryObserver = _PressPlayMemoryObserver();
final _windowCloseCoordinator = WindowCloseCoordinator(
  tray: _TrayLifecycleWindowAdapter(TrayService.instance),
  window: const _WindowLifecycleWindowManagerAdapter(),
  appShutdown: _RustShutdownAdapter(RustBridgeService.instance),
  trimMemory: UiMemoryLifecycle.trim,
  cleanupLifecycleHooks: _cleanupLifecycleHooks,
  requestAppExit: _requestAppExit,
);

Future<void> main() async {
  if (!kIsWeb && _enableShaderWarmUp) {
    PaintingBinding.shaderWarmUp = const PressPlayShaderWarmUp();
  }
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance
    ..removeObserver(_memoryObserver)
    ..addObserver(_memoryObserver);

  // Initialize Flutter-Rust bridge and Rust core
  await _initRustBridge();
  RustBridgeService.instance.initApp();

  await windowManager.ensureInitialized();
  windowManager.removeListener(_windowListener);
  windowManager.addListener(_windowListener);
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    await windowManager.setPreventClose(true);
  }

  final titleBarStyle =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
      ? TitleBarStyle.hidden
      : TitleBarStyle.normal;

  final windowOptions = WindowOptions(
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
    titleBarStyle: titleBarStyle,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    try {
      await TrayService.instance.init();
    } catch (e) {
      debugPrint('[tray] Init failed (non-fatal): $e');
    }
  });

  runApp(const PressPlayApp());
}

const bool _enableShaderWarmUp = bool.fromEnvironment(
  'PRESSPLAY_SHADER_WARM_UP',
  defaultValue: true,
);

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
    unawaited(_windowCloseCoordinator.onWindowClose());
  }

  @override
  void onWindowMinimize() {
    _windowCloseCoordinator.onWindowMinimize();
  }
}

class _PressPlayMemoryObserver with WidgetsBindingObserver {
  bool _trimmedForBackground = false;

  @override
  void didHaveMemoryPressure() {
    UiMemoryLifecycle.trim(UiMemoryTrimLevel.pressure);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _trimmedForBackground = false;
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_trimmedForBackground) {
          return;
        }
        _trimmedForBackground = true;
        UiMemoryLifecycle.trim(UiMemoryTrimLevel.background);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }
}

void _cleanupLifecycleHooks() {
  windowManager.removeListener(_windowListener);
  WidgetsBinding.instance.removeObserver(_memoryObserver);
}

Future<void> _requestAppExit() {
  return SystemNavigator.pop();
}

class _TrayLifecycleWindowAdapter implements TrayLifecycleAdapter {
  _TrayLifecycleWindowAdapter(this._trayService);

  final TrayService _trayService;

  @override
  bool get quitRequested => _trayService.quitRequested;

  @override
  bool get minimizeToTray => _trayService.minimizeToTray;

  @override
  bool get isInitialized => _trayService.isInitialized;

  @override
  Future<void> dispose() {
    return _trayService.dispose();
  }
}

class _WindowLifecycleWindowManagerAdapter implements WindowLifecycleAdapter {
  const _WindowLifecycleWindowManagerAdapter();

  @override
  Future<void> hide() {
    return windowManager.hide();
  }

  @override
  Future<void> setPreventClose(bool value) {
    return windowManager.setPreventClose(value);
  }

  @override
  Future<void> destroy() {
    return windowManager.destroy();
  }

  @override
  Future<void> close() {
    return windowManager.close();
  }
}

class _RustShutdownAdapter implements AppShutdownAdapter {
  _RustShutdownAdapter(this._rustBridgeService);

  final RustBridgeService _rustBridgeService;

  @override
  Future<void> shutdownApp() {
    return _rustBridgeService.shutdownApp();
  }
}
