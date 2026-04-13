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
import 'core/lifecycle/app_window_visibility.dart';
import 'core/performance/compact_games_shader_warm_up.dart';
import 'core/performance/ui_memory_lifecycle.dart';
import 'services/rust_bridge_service.dart';
import 'services/rust_library_candidates.dart';
import 'services/startup_window_coordinator.dart';
import 'services/tray_service.dart';
import 'services/window_close_coordinator.dart';
import 'src/rust/frb_generated.dart';

final _windowListener = _CompactGamesWindowListener();
final _memoryObserver = _CompactGamesMemoryObserver();
final _windowCloseCoordinator = WindowCloseCoordinator(
  tray: _TrayLifecycleWindowAdapter(TrayService.instance),
  window: const _WindowLifecycleWindowManagerAdapter(),
  appShutdown: _RustShutdownAdapter(RustBridgeService.instance),
  trimMemory: UiMemoryLifecycle.trim,
  cleanupLifecycleHooks: _cleanupLifecycleHooks,
  requestAppExit: _requestAppExit,
  onHiddenToTray: appWindowVisibilityController.markHiddenToTray,
);
const _startupWindow = WindowManagerStartupAdapter();
final _startupTray = TrayStartupAdapter(TrayService.instance);

Future<void> main() async {
  if (!kIsWeb && _enableShaderWarmUp) {
    PaintingBinding.shaderWarmUp = const CompactGamesShaderWarmUp();
  }
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    // Baseline debug paint can persist across debug sessions and looks like
    // a green underline under text-heavy widgets such as the activity card.
    debugPaintBaselinesEnabled = false;
  }

  // Cap decoded image memory to stay under budget.
  UiMemoryLifecycle.configureImageCache();

  WidgetsBinding.instance
    ..removeObserver(_memoryObserver)
    ..addObserver(_memoryObserver);

  // Initialize Flutter-Rust bridge and Rust core
  await _initRustBridge();
  RustBridgeService.instance.initApp();

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

  await initializeStartupWindow(
    window: _startupWindow,
    tray: _startupTray,
    listener: _windowListener,
    options: windowOptions,
    isWeb: kIsWeb,
    targetPlatform: defaultTargetPlatform,
    onTrayInitError: (error) {
      debugPrint('[tray] Init failed (non-fatal): $error');
    },
  );
  TrayService.instance.registerShowWindowHook(() {
    UiMemoryLifecycle.configureImageCache();
    appWindowVisibilityController.markVisible();
  });

  runApp(const _RustBridgeReloadHost(child: CompactGamesApp()));
}

const bool _enableShaderWarmUp = bool.fromEnvironment(
  'COMPACT_GAMES_SHADER_WARM_UP',
  defaultValue: true,
);

const bool _preferDebugRustDll = bool.fromEnvironment(
  'COMPACT_GAMES_PREFER_DEBUG_RUST_DLL',
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
  return buildRustLibraryCandidates(
    isReleaseMode: kReleaseMode,
    isProfileMode: kProfileMode,
    preferDebugRustDll: _preferDebugRustDll,
  );
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

class _CompactGamesWindowListener extends WindowListener {
  @override
  void onWindowClose() {
    unawaited(_windowCloseCoordinator.onWindowClose());
  }

  @override
  void onWindowMinimize() {
    _windowCloseCoordinator.onWindowMinimize();
  }
}

class _CompactGamesMemoryObserver with WidgetsBindingObserver {
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
        UiMemoryLifecycle.configureImageCache();
        appWindowVisibilityController.markVisible();
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
