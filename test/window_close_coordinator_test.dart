import 'package:flutter_test/flutter_test.dart';
import 'package:compact_games/core/performance/ui_memory_lifecycle.dart';
import 'package:compact_games/services/window_close_coordinator.dart';

void main() {
  test('close hides to tray when minimize-to-tray is enabled', () async {
    final tray = _FakeTrayLifecycleAdapter(
      quitRequested: false,
      minimizeToTray: true,
      isInitialized: true,
    );
    final window = _FakeWindowLifecycleAdapter();
    final shutdown = _FakeShutdownAdapter();
    final trims = <UiMemoryTrimLevel>[];
    var cleanupCalls = 0;
    var appExitCalls = 0;

    final coordinator = WindowCloseCoordinator(
      tray: tray,
      window: window,
      appShutdown: shutdown,
      trimMemory: trims.add,
      cleanupLifecycleHooks: () {
        cleanupCalls += 1;
      },
      requestAppExit: () async {
        appExitCalls += 1;
      },
    );

    await coordinator.onWindowClose();

    expect(window.hideCalls, 1);
    expect(shutdown.shutdownCalls, 0);
    expect(tray.disposeCalls, 0);
    expect(trims, <UiMemoryTrimLevel>[UiMemoryTrimLevel.trayHide]);
    expect(cleanupCalls, 0);
    expect(appExitCalls, 0);
  });

  test(
    'quit path bypasses minimize interception and closes deterministically',
    () async {
      final tray = _FakeTrayLifecycleAdapter(
        quitRequested: true,
        minimizeToTray: true,
        isInitialized: true,
      );
      final window = _FakeWindowLifecycleAdapter();
      final shutdown = _FakeShutdownAdapter();
      final trims = <UiMemoryTrimLevel>[];
      var cleanupCalls = 0;
      var appExitCalls = 0;

      final coordinator = WindowCloseCoordinator(
        tray: tray,
        window: window,
        appShutdown: shutdown,
        trimMemory: trims.add,
        cleanupLifecycleHooks: () {
          cleanupCalls += 1;
        },
        requestAppExit: () async {
          appExitCalls += 1;
        },
      );

      await coordinator.onWindowClose();

      expect(shutdown.shutdownCalls, 1);
      expect(tray.disposeCalls, 1);
      expect(window.hideCalls, 0);
      expect(window.setPreventCloseCalls, 1);
      expect(window.setPreventCloseValues, <bool>[false]);
      expect(window.destroyCalls, 1);
      expect(window.closeCalls, 0);
      expect(trims, <UiMemoryTrimLevel>[UiMemoryTrimLevel.shutdown]);
      expect(cleanupCalls, 1);
      expect(appExitCalls, 0);
    },
  );

  test('hide failure falls back to deterministic shutdown', () async {
    final tray = _FakeTrayLifecycleAdapter(
      quitRequested: false,
      minimizeToTray: true,
      isInitialized: true,
    );
    final window = _FakeWindowLifecycleAdapter(throwOnHide: true);
    final shutdown = _FakeShutdownAdapter();
    final trims = <UiMemoryTrimLevel>[];
    var cleanupCalls = 0;
    var appExitCalls = 0;

    final coordinator = WindowCloseCoordinator(
      tray: tray,
      window: window,
      appShutdown: shutdown,
      trimMemory: trims.add,
      cleanupLifecycleHooks: () {
        cleanupCalls += 1;
      },
      requestAppExit: () async {
        appExitCalls += 1;
      },
    );

    await coordinator.onWindowClose();

    expect(window.hideCalls, 1);
    expect(shutdown.shutdownCalls, 1);
    expect(tray.disposeCalls, 1);
    expect(window.setPreventCloseCalls, 1);
    expect(window.setPreventCloseValues, <bool>[false]);
    expect(window.destroyCalls, 1);
    expect(window.closeCalls, 0);
    expect(trims, <UiMemoryTrimLevel>[UiMemoryTrimLevel.shutdown]);
    expect(cleanupCalls, 1);
    expect(appExitCalls, 0);
  });

  test(
    'minimize then quit loop is stable across a fresh restart cycle',
    () async {
      final firstRun = _LoopRunContext();
      await firstRun.coordinator.onWindowClose();
      expect(firstRun.window.hideCalls, 1);
      expect(firstRun.shutdown.shutdownCalls, 0);

      firstRun.tray.quitRequested = true;
      await firstRun.coordinator.onWindowClose();
      expect(firstRun.shutdown.shutdownCalls, 1);
      expect(firstRun.tray.disposeCalls, 1);
      expect(firstRun.cleanupCalls, 1);

      await firstRun.coordinator.onWindowClose();
      expect(firstRun.shutdown.shutdownCalls, 1);

      final secondRun = _LoopRunContext();
      await secondRun.coordinator.onWindowClose();
      secondRun.tray.quitRequested = true;
      await secondRun.coordinator.onWindowClose();

      expect(secondRun.window.hideCalls, 1);
      expect(secondRun.shutdown.shutdownCalls, 1);
      expect(secondRun.tray.disposeCalls, 1);
      expect(secondRun.cleanupCalls, 1);
    },
  );
}

class _LoopRunContext {
  _LoopRunContext()
    : tray = _FakeTrayLifecycleAdapter(
        quitRequested: false,
        minimizeToTray: true,
        isInitialized: true,
      ),
      window = _FakeWindowLifecycleAdapter(),
      shutdown = _FakeShutdownAdapter(),
      trims = <UiMemoryTrimLevel>[] {
    coordinator = WindowCloseCoordinator(
      tray: tray,
      window: window,
      appShutdown: shutdown,
      trimMemory: trims.add,
      cleanupLifecycleHooks: () {
        cleanupCalls += 1;
      },
      requestAppExit: () async {
        appExitCalls += 1;
      },
    );
  }

  final _FakeTrayLifecycleAdapter tray;
  final _FakeWindowLifecycleAdapter window;
  final _FakeShutdownAdapter shutdown;
  final List<UiMemoryTrimLevel> trims;
  late final WindowCloseCoordinator coordinator;
  int cleanupCalls = 0;
  int appExitCalls = 0;
}

class _FakeTrayLifecycleAdapter implements TrayLifecycleAdapter {
  _FakeTrayLifecycleAdapter({
    required this.quitRequested,
    required this.minimizeToTray,
    required this.isInitialized,
  });

  @override
  bool quitRequested;

  @override
  final bool minimizeToTray;

  @override
  final bool isInitialized;

  int disposeCalls = 0;

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}

class _FakeWindowLifecycleAdapter implements WindowLifecycleAdapter {
  _FakeWindowLifecycleAdapter({this.throwOnHide = false});

  final bool throwOnHide;
  int hideCalls = 0;
  int setPreventCloseCalls = 0;
  int destroyCalls = 0;
  int closeCalls = 0;
  final List<bool> setPreventCloseValues = <bool>[];

  @override
  Future<void> hide() async {
    hideCalls += 1;
    if (throwOnHide) {
      throw StateError('hide failed');
    }
  }

  @override
  Future<void> setPreventClose(bool value) async {
    setPreventCloseCalls += 1;
    setPreventCloseValues.add(value);
  }

  @override
  Future<void> destroy() async {
    destroyCalls += 1;
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}

class _FakeShutdownAdapter implements AppShutdownAdapter {
  int shutdownCalls = 0;

  @override
  Future<void> shutdownApp() async {
    shutdownCalls += 1;
  }
}
