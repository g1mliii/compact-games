import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/performance/perf_monitor.dart';
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
  PerfMonitor.markStartupBegin();
  if (!kIsWeb && _enableShaderWarmUp) {
    PaintingBinding.shaderWarmUp = const PressPlayShaderWarmUp();
  }
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    // Baseline debug paint can persist across debug sessions and looks like
    // a green underline under text-heavy widgets such as the activity card.
    debugPaintBaselinesEnabled = false;
  }

  // Cap decoded image memory at 50MB / 300 entries to stay under budget.
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSizeBytes = 50 * 1024 * 1024;
  imageCache.maximumSize = 300;

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
    // Avoid stealing foreground focus from active fullscreen/borderless games
    // when the app starts in the background.
    await windowManager.show(inactive: true);
    try {
      await TrayService.instance.init();
    } catch (e) {
      debugPrint('[tray] Init failed (non-fatal): $e');
    }
  });

  runApp(const _RustBridgeReloadHost(child: PressPlayApp()));
  PerfMonitor.markStartupEnd();
}

const bool _enableShaderWarmUp = bool.fromEnvironment(
  'PRESSPLAY_SHADER_WARM_UP',
  defaultValue: true,
);

const bool _preferDebugRustDll = bool.fromEnvironment(
  'PRESSPLAY_PREFER_DEBUG_RUST_DLL',
  defaultValue: true,
);

Future<void>? _debugHotReloadRustRestart;

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

Future<void> _reloadRustBridgeForHotReload() async {
  if (kReleaseMode || kIsWeb) {
    return;
  }

  final existing = _debugHotReloadRustRestart;
  if (existing != null) {
    return existing;
  }

  final future = () async {
    debugPrint('[rust] Hot reload detected; reloading Rust bridge');
    try {
      await RustBridgeService.instance.shutdownApp();
    } catch (e) {
      debugPrint('[rust] Hot reload shutdown failed: $e');
    }

    try {
      await _initRustBridge();
      RustBridgeService.instance.initApp();
    } catch (e) {
      debugPrint('[rust] Hot reload bridge reload failed: $e');
    }
  }();

  _debugHotReloadRustRestart = future;
  try {
    await future;
  } finally {
    if (identical(_debugHotReloadRustRestart, future)) {
      _debugHotReloadRustRestart = null;
    }
  }
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

class _RustBridgeReloadHost extends StatefulWidget {
  const _RustBridgeReloadHost({required this.child});

  final Widget child;

  @override
  State<_RustBridgeReloadHost> createState() => _RustBridgeReloadHostState();
}

class _RustBridgeReloadHostState extends State<_RustBridgeReloadHost> {
  int _providerScopeGeneration = 0;

  @override
  void reassemble() {
    super.reassemble();
    if (kDebugMode) {
      unawaited(() async {
        await _reloadRustBridgeForHotReload();
        if (!mounted) {
          return;
        }
        setState(() {
          _providerScopeGeneration += 1;
        });
      }());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: ValueKey<int>(_providerScopeGeneration),
      child: widget.child,
    );
  }
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
