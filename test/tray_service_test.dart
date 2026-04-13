import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:compact_games/services/tray_service.dart';
import 'package:tray_manager/tray_manager.dart';

part 'support/tray_service_test_extras.dart';

void main() {
  setUp(() {
    TrayService.instance.resetForTest();
  });

  tearDown(() async {
    await TrayService.instance.dispose();
    TrayService.instance.resetForTest();
  });

  test('init/dispose are idempotent and register one tray listener', () async {
    final fakeTray = _FakeTrayPlatformAdapter();
    final fakeWindow = _FakeWindowPlatformAdapter();
    final service = TrayService.instance;
    service.configureForTest(
      trayPlatform: fakeTray,
      windowPlatform: fakeWindow,
      debounceDuration: const Duration(milliseconds: 5),
      iconPathOverride: r'C:\test\compact_games_tray.ico',
    );

    await service.init();
    await service.init();

    expect(fakeTray.addListenerCalls, 1);
    expect(fakeTray.setIconCalls, 1);
    expect(fakeTray.setContextMenuCalls, 1);
    expect(service.isInitialized, isTrue);

    await service.dispose();
    await service.dispose();

    expect(fakeTray.removeListenerCalls, 1);
    expect(fakeTray.destroyCalls, 1);
    expect(service.isInitialized, isFalse);
  });

  test(
    'tray menu commands dispatch once per click under duplicate init',
    () async {
      final fakeTray = _FakeTrayPlatformAdapter();
      final fakeWindow = _FakeWindowPlatformAdapter();
      final service = TrayService.instance;
      service.configureForTest(
        trayPlatform: fakeTray,
        windowPlatform: fakeWindow,
        debounceDuration: const Duration(milliseconds: 5),
        iconPathOverride: r'C:\test\compact_games_tray.ico',
      );

      await service.init();
      await service.init();

      for (var i = 0; i < 20; i += 1) {
        fakeTray.triggerMenuClick('show');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeWindow.showCalls, 20);
      expect(fakeWindow.focusCalls, 20);

      for (var i = 0; i < 15; i += 1) {
        fakeTray.triggerMenuClick('quit');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeWindow.closeCalls, 15);
      expect(service.quitRequested, isTrue);
    },
  );

  test('show window command runs lifecycle hook before focus', () async {
    final fakeTray = _FakeTrayPlatformAdapter();
    final fakeWindow = _FakeWindowPlatformAdapter();
    final service = TrayService.instance;
    var showHookCalls = 0;
    service.configureForTest(
      trayPlatform: fakeTray,
      windowPlatform: fakeWindow,
      debounceDuration: const Duration(milliseconds: 5),
      iconPathOverride: r'C:\test\compact_games_tray.ico',
      onShowWindow: () {
        showHookCalls += 1;
      },
    );

    await service.init();
    fakeTray.triggerMenuClick('show');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(showHookCalls, 1);
    expect(fakeWindow.showCalls, 1);
    expect(fakeWindow.focusCalls, 1);
  });

  test('dispose cancels pending coalesced status update', () async {
    final fakeTray = _FakeTrayPlatformAdapter();
    final fakeWindow = _FakeWindowPlatformAdapter();
    final service = TrayService.instance;
    service.configureForTest(
      trayPlatform: fakeTray,
      windowPlatform: fakeWindow,
      debounceDuration: const Duration(milliseconds: 50),
      iconPathOverride: r'C:\test\compact_games_tray.ico',
    );

    await service.init();
    final tooltipCallsBefore = fakeTray.setToolTipCalls;
    final menuCallsBefore = fakeTray.setContextMenuCalls;

    service.update(
      const TrayStatus(
        mode: TrayStatusMode.compressing,
        activeGameName: 'Pending Debounce',
        progressPercent: 42,
      ),
    );
    await service.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(fakeTray.setToolTipCalls, tooltipCallsBefore);
    expect(fakeTray.setContextMenuCalls, menuCallsBefore);
  });

  test(
    'debounce coalescing keeps latest queued status when updates revert quickly',
    () async {
      final fakeTray = _FakeTrayPlatformAdapter();
      final fakeWindow = _FakeWindowPlatformAdapter();
      final service = TrayService.instance;
      service.configureForTest(
        trayPlatform: fakeTray,
        windowPlatform: fakeWindow,
        debounceDuration: const Duration(milliseconds: 50),
        iconPathOverride: r'C:\test\compact_games_tray.ico',
      );

      await service.init();
      final menuCallsBefore = fakeTray.setContextMenuCalls;

      service.update(
        const TrayStatus(
          mode: TrayStatusMode.compressing,
          activeGameName: 'Race Game',
          progressPercent: 8,
        ),
      );
      service.update(const TrayStatus(mode: TrayStatusMode.idle));
      await service.flushPendingUpdateForTest();

      expect(fakeTray.setContextMenuCalls, menuCallsBefore);
      expect(fakeTray.lastTooltip, 'Compact Games');
    },
  );

  test('status queued before init is applied during init', () async {
    final fakeTray = _FakeTrayPlatformAdapter();
    final fakeWindow = _FakeWindowPlatformAdapter();
    final service = TrayService.instance;
    service.configureForTest(
      trayPlatform: fakeTray,
      windowPlatform: fakeWindow,
      debounceDuration: const Duration(milliseconds: 5),
      iconPathOverride: r'C:\test\compact_games_tray.ico',
    );

    service.update(
      const TrayStatus(
        mode: TrayStatusMode.compressing,
        activeGameName: 'Boot Game',
        progressPercent: 7,
      ),
    );

    await service.init();

    expect(fakeTray.setContextMenuCalls, 1);
    expect(fakeTray.menuLabelForKey('status'), 'Compressing: Boot Game');
    expect(fakeTray.lastTooltip, 'Compact Games - Compressing Boot Game (7%)');
  });

  test(
    'menu-only status changes do not trigger redundant tooltip writes',
    () async {
      final fakeTray = _FakeTrayPlatformAdapter();
      final fakeWindow = _FakeWindowPlatformAdapter();
      final service = TrayService.instance;
      service.configureForTest(
        trayPlatform: fakeTray,
        windowPlatform: fakeWindow,
        debounceDuration: const Duration(milliseconds: 5),
        iconPathOverride: r'C:\test\compact_games_tray.ico',
      );

      await service.init();
      expect(fakeTray.setToolTipCalls, 1);
      expect(fakeTray.lastTooltip, 'Compact Games');

      service.update(
        const TrayStatus(
          mode: TrayStatusMode.idle,
          autoCompressionEnabled: true,
        ),
      );
      await service.flushPendingUpdateForTest();

      expect(fakeTray.setToolTipCalls, 1);
      expect(fakeTray.lastTooltip, 'Compact Games');
      expect(fakeTray.menuLabelForKey('toggle_auto'), 'Pause Auto-Compression');

      service.update(
        const TrayStatus(
          mode: TrayStatusMode.paused,
          autoCompressionEnabled: true,
        ),
      );
      await service.flushPendingUpdateForTest();

      expect(fakeTray.setToolTipCalls, 2);
      expect(fakeTray.lastTooltip, 'Compact Games - Paused');
    },
  );

  test(
    'localized menu label changes rebuild the tray menu even when status mode is unchanged',
    () async {
      final fakeTray = _FakeTrayPlatformAdapter();
      final fakeWindow = _FakeWindowPlatformAdapter();
      final service = TrayService.instance;
      service.configureForTest(
        trayPlatform: fakeTray,
        windowPlatform: fakeWindow,
        debounceDuration: const Duration(milliseconds: 5),
        iconPathOverride: r'C:\test\compact_games_tray.ico',
      );

      await service.init();
      final menuCallsBefore = fakeTray.setContextMenuCalls;
      final tooltipCallsBefore = fakeTray.setToolTipCalls;

      service.update(
        const TrayStatus(
          mode: TrayStatusMode.idle,
          autoCompressionEnabled: true,
          strings: TrayStrings(
            openAppLabel: 'Abrir Compact Games',
            pauseAutoCompressionLabel: 'Pausar compresion automatica',
            resumeAutoCompressionLabel: 'Reanudar compresion automatica',
            quitLabel: 'Salir',
          ),
        ),
      );
      await service.flushPendingUpdateForTest();

      expect(fakeTray.setContextMenuCalls, menuCallsBefore + 1);
      expect(fakeTray.setToolTipCalls, tooltipCallsBefore);
      expect(fakeTray.menuLabelForKey('show'), 'Abrir Compact Games');
      expect(
        fakeTray.menuLabelForKey('toggle_auto'),
        'Pausar compresion automatica',
      );
      expect(fakeTray.menuLabelForKey('quit'), 'Salir');
      expect(fakeTray.lastTooltip, 'Compact Games');
    },
  );

  test(
    'toggle auto-compression tray action is debounced while in flight',
    () async {
      final fakeTray = _FakeTrayPlatformAdapter();
      final fakeWindow = _FakeWindowPlatformAdapter();
      final service = TrayService.instance;
      final requests = <bool>[];
      final releaseToggle = Completer<void>();
      service.configureForTest(
        trayPlatform: fakeTray,
        windowPlatform: fakeWindow,
        debounceDuration: const Duration(milliseconds: 5),
        iconPathOverride: r'C:\test\compact_games_tray.ico',
        setAutoCompressionEnabled: (enabled) async {
          requests.add(enabled);
          await releaseToggle.future;
        },
      );

      await service.init();
      service.update(
        const TrayStatus(
          mode: TrayStatusMode.idle,
          autoCompressionEnabled: true,
        ),
      );
      await service.flushPendingUpdateForTest();
      expect(fakeTray.menuLabelForKey('toggle_auto'), 'Pause Auto-Compression');

      fakeTray.triggerMenuClick('toggle_auto');
      fakeTray.triggerMenuClick('toggle_auto');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(requests, <bool>[false]);

      releaseToggle.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      service.update(
        const TrayStatus(
          mode: TrayStatusMode.paused,
          autoCompressionEnabled: false,
        ),
      );
      await service.flushPendingUpdateForTest();
      expect(
        fakeTray.menuLabelForKey('toggle_auto'),
        'Resume Auto-Compression',
      );
    },
  );

  test('auto-toggle callback registration follows latest owner', () async {
    final fakeTray = _FakeTrayPlatformAdapter();
    final fakeWindow = _FakeWindowPlatformAdapter();
    final service = TrayService.instance;
    final ownerA = Object();
    final ownerB = Object();
    final requestsA = <bool>[];
    final requestsB = <bool>[];
    service.configureForTest(
      trayPlatform: fakeTray,
      windowPlatform: fakeWindow,
      debounceDuration: const Duration(milliseconds: 5),
      iconPathOverride: r'C:\test\compact_games_tray.ico',
    );

    await service.init();
    service.update(
      const TrayStatus(mode: TrayStatusMode.idle, autoCompressionEnabled: true),
    );
    await service.flushPendingUpdateForTest();

    service.registerAutoCompressionToggle(
      owner: ownerA,
      setEnabled: (enabled) async {
        requestsA.add(enabled);
      },
    );
    service.registerAutoCompressionToggle(
      owner: ownerB,
      setEnabled: (enabled) async {
        requestsB.add(enabled);
      },
    );
    await service.flushPendingUpdateForTest();

    fakeTray.triggerMenuClick('toggle_auto');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(requestsA, isEmpty);
    expect(requestsB, <bool>[false]);

    service.unregisterAutoCompressionToggle(ownerA);
    await service.flushPendingUpdateForTest();
    expect(fakeTray.menuItemForKey('toggle_auto')?.disabled, isFalse);

    service.unregisterAutoCompressionToggle(ownerB);
    await service.flushPendingUpdateForTest();
    expect(fakeTray.menuItemForKey('toggle_auto')?.disabled, isTrue);
  });

  test('dispose clears auto-toggle callback references', () async {
    final fakeTray = _FakeTrayPlatformAdapter();
    final fakeWindow = _FakeWindowPlatformAdapter();
    final service = TrayService.instance;
    final owner = Object();
    final requests = <bool>[];
    service.configureForTest(
      trayPlatform: fakeTray,
      windowPlatform: fakeWindow,
      debounceDuration: const Duration(milliseconds: 5),
      iconPathOverride: r'C:\test\compact_games_tray.ico',
    );

    await service.init();
    service.update(
      const TrayStatus(mode: TrayStatusMode.idle, autoCompressionEnabled: true),
    );
    service.registerAutoCompressionToggle(
      owner: owner,
      setEnabled: (enabled) async {
        requests.add(enabled);
      },
    );
    await service.flushPendingUpdateForTest();
    expect(fakeTray.menuItemForKey('toggle_auto')?.disabled, isFalse);

    fakeTray.triggerMenuClick('toggle_auto');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(requests, <bool>[false]);

    await service.dispose();
    await service.init();
    service.update(
      const TrayStatus(mode: TrayStatusMode.idle, autoCompressionEnabled: true),
    );
    await service.flushPendingUpdateForTest();

    expect(fakeTray.menuItemForKey('toggle_auto')?.disabled, isTrue);

    fakeTray.triggerMenuClick('toggle_auto');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(requests, <bool>[false]);
  });

  test(
    'coalesced update tick does not starve sustained progress updates',
    () async {
      final fakeTray = _FakeTrayPlatformAdapter();
      final fakeWindow = _FakeWindowPlatformAdapter();
      final service = TrayService.instance;
      service.configureForTest(
        trayPlatform: fakeTray,
        windowPlatform: fakeWindow,
        debounceDuration: const Duration(milliseconds: 30),
        iconPathOverride: r'C:\test\compact_games_tray.ico',
      );

      await service.init();
      final baselineTooltips = fakeTray.setToolTipCalls;
      final started = DateTime.now();
      var pct = 0;
      while (DateTime.now().difference(started) <
          const Duration(milliseconds: 220)) {
        service.update(
          TrayStatus(
            mode: TrayStatusMode.compressing,
            activeGameName: 'Long Run',
            progressPercent: pct % 100,
          ),
        );
        pct += 1;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await Future<void>.delayed(const Duration(milliseconds: 120));
      final emittedDuringStream = fakeTray.setToolTipCalls - baselineTooltips;
      expect(emittedDuringStream, greaterThanOrEqualTo(4));
    },
  );
  _defineTrayServiceStressTests();
}
