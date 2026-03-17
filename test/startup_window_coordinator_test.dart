import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressplay/services/startup_window_coordinator.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  test(
    'startup window shows inactive on Windows and initializes tray after show',
    () async {
      final window = _FakeStartupWindowAdapter();
      final tray = _FakeStartupTrayAdapter(
        onInit: () =>
            window.showInactiveCallsAtTrayInit = window.showInactiveCalls,
      );
      final listener = _FakeWindowListener();
      final options = WindowOptions(
        size: const Size(1280, 720),
        minimumSize: const Size(960, 640),
        center: true,
        title: 'PressPlay',
        titleBarStyle: TitleBarStyle.hidden,
      );
      final trayErrors = <Object>[];

      await initializeStartupWindow(
        window: window,
        tray: tray,
        listener: listener,
        options: options,
        isWeb: false,
        targetPlatform: TargetPlatform.windows,
        onTrayInitError: trayErrors.add,
      );

      expect(window.ensureInitializedCalls, 1);
      expect(window.removeListenerCalls, 1);
      expect(window.addListenerCalls, 1);
      expect(window.setPreventCloseValues, <bool>[true]);
      expect(window.waitUntilReadyToShowCalls, 1);
      expect(window.showInactiveCalls, 1);
      expect(tray.initCalls, 1);
      expect(window.showInactiveCallsAtTrayInit, 1);
      expect(trayErrors, isEmpty);
    },
  );

  test('startup window skips prevent-close outside Windows', () async {
    final window = _FakeStartupWindowAdapter();
    final tray = _FakeStartupTrayAdapter();
    final listener = _FakeWindowListener();

    await initializeStartupWindow(
      window: window,
      tray: tray,
      listener: listener,
      options: const WindowOptions(),
      isWeb: false,
      targetPlatform: TargetPlatform.macOS,
    );

    expect(window.setPreventCloseValues, isEmpty);
    expect(window.showInactiveCalls, 1);
    expect(tray.initCalls, 1);
  });

  test('startup tray init failure is reported but not rethrown', () async {
    final window = _FakeStartupWindowAdapter();
    final tray = _FakeStartupTrayAdapter(throwOnInit: true);
    final errors = <Object>[];

    await initializeStartupWindow(
      window: window,
      tray: tray,
      listener: _FakeWindowListener(),
      options: const WindowOptions(),
      isWeb: false,
      targetPlatform: TargetPlatform.windows,
      onTrayInitError: errors.add,
    );

    expect(window.showInactiveCalls, 1);
    expect(tray.initCalls, 1);
    expect(errors, hasLength(1));
  });
}

class _FakeWindowListener extends WindowListener {}

class _FakeStartupWindowAdapter implements StartupWindowAdapter {
  int ensureInitializedCalls = 0;
  int addListenerCalls = 0;
  int removeListenerCalls = 0;
  int waitUntilReadyToShowCalls = 0;
  int showInactiveCalls = 0;
  int showInactiveCallsAtTrayInit = 0;
  final List<bool> setPreventCloseValues = <bool>[];

  @override
  Future<void> ensureInitialized() async {
    ensureInitializedCalls += 1;
  }

  @override
  void addListener(WindowListener listener) {
    addListenerCalls += 1;
  }

  @override
  void removeListener(WindowListener listener) {
    removeListenerCalls += 1;
  }

  @override
  Future<void> setPreventClose(bool value) async {
    setPreventCloseValues.add(value);
  }

  @override
  Future<void> waitUntilReadyToShow(
    WindowOptions options,
    Future<void> Function() callback,
  ) async {
    waitUntilReadyToShowCalls += 1;
    await callback();
  }

  @override
  Future<void> showInactive() async {
    showInactiveCalls += 1;
  }
}

class _FakeStartupTrayAdapter implements StartupTrayAdapter {
  _FakeStartupTrayAdapter({this.throwOnInit = false, this.onInit});

  final bool throwOnInit;
  final VoidCallback? onInit;
  int initCalls = 0;

  @override
  Future<void> init() async {
    initCalls += 1;
    onInit?.call();
    if (throwOnInit) {
      throw StateError('tray init failed');
    }
  }
}
