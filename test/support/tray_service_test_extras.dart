part of '../tray_service_test.dart';

void _defineTrayServiceStressTests() {
  test(
    'serialized tray apply keeps latest status under slow menu API',
    () async {
      final fakeTray = _DelayedTrayPlatformAdapter(
        menuDelayByCall: <int, Duration>{
          // Delay first post-init menu update to force overlap pressure.
          1: const Duration(milliseconds: 80),
        },
      );
      final fakeWindow = _FakeWindowPlatformAdapter();
      final service = TrayService.instance;
      service.configureForTest(
        trayPlatform: fakeTray,
        windowPlatform: fakeWindow,
        debounceDuration: const Duration(milliseconds: 1),
        iconPathOverride: r'C:\test\pressplay_tray.ico',
      );

      await service.init();

      service.update(
        const TrayStatus(
          mode: TrayStatusMode.compressing,
          activeGameName: 'Slow Menu Game',
          progressPercent: 12,
          autoCompressionEnabled: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.update(
        const TrayStatus(
          mode: TrayStatusMode.idle,
          autoCompressionEnabled: true,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(fakeTray.lastTooltip, 'PressPlay');
    },
  );

  test(
    'synthetic tray interaction soak keeps menu and tooltip writes bounded',
    () async {
      final fakeTray = _FakeTrayPlatformAdapter();
      final fakeWindow = _FakeWindowPlatformAdapter();
      final service = TrayService.instance;
      service.configureForTest(
        trayPlatform: fakeTray,
        windowPlatform: fakeWindow,
        debounceDuration: const Duration(milliseconds: 1),
        iconPathOverride: r'C:\test\pressplay_tray.ico',
      );

      await service.init();

      for (var cycle = 0; cycle < 300; cycle += 1) {
        for (var pct = 0; pct < 100; pct += 1) {
          service.update(
            TrayStatus(
              mode: TrayStatusMode.compressing,
              activeGameName: 'Soak Game',
              progressPercent: pct,
            ),
          );
        }
        await service.flushPendingUpdateForTest();
        fakeTray.triggerMenuClick('show');
      }

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fakeTray.setContextMenuCalls, 2);
      expect(fakeTray.setToolTipCalls, 2);
      expect(fakeWindow.showCalls, 300);
      expect(fakeWindow.focusCalls, 300);
    },
  );
}

class _FakeTrayPlatformAdapter implements TrayPlatformAdapter {
  int addListenerCalls = 0;
  int removeListenerCalls = 0;
  int setIconCalls = 0;
  int setToolTipCalls = 0;
  int setContextMenuCalls = 0;
  int popUpContextMenuCalls = 0;
  int destroyCalls = 0;
  String? lastTooltip;
  final List<String> tooltipHistory = <String>[];
  Menu? lastMenu;
  final List<TrayListener> _listeners = <TrayListener>[];

  @override
  void addListener(TrayListener listener) {
    addListenerCalls += 1;
    _listeners.add(listener);
  }

  @override
  void removeListener(TrayListener listener) {
    removeListenerCalls += 1;
    _listeners.remove(listener);
  }

  @override
  Future<void> setIcon(String iconPath) async {
    setIconCalls += 1;
  }

  @override
  Future<void> setToolTip(String tooltip) async {
    setToolTipCalls += 1;
    lastTooltip = tooltip;
    tooltipHistory.add(tooltip);
  }

  @override
  Future<void> setContextMenu(Menu menu) async {
    setContextMenuCalls += 1;
    lastMenu = menu;
  }

  @override
  Future<void> popUpContextMenu() async {
    popUpContextMenuCalls += 1;
  }

  @override
  Future<void> destroy() async {
    destroyCalls += 1;
  }

  void triggerMenuClick(String key) {
    final item = MenuItem(key: key, label: key);
    for (final listener in List<TrayListener>.from(_listeners)) {
      listener.onTrayMenuItemClick(item);
    }
  }

  String? menuLabelForKey(String key) {
    return menuItemForKey(key)?.label;
  }

  MenuItem? menuItemForKey(String key) {
    final menu = lastMenu;
    if (menu == null) return null;
    final items = menu.items;
    if (items == null) return null;
    for (final item in items) {
      if (item.key == key) {
        return item;
      }
    }
    return null;
  }
}

class _DelayedTrayPlatformAdapter extends _FakeTrayPlatformAdapter {
  _DelayedTrayPlatformAdapter({this.menuDelayByCall = const <int, Duration>{}});

  final Map<int, Duration> menuDelayByCall;

  @override
  Future<void> setContextMenu(Menu menu) async {
    final delay = menuDelayByCall[setContextMenuCalls];
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    await super.setContextMenu(menu);
  }
}

class _FakeWindowPlatformAdapter implements WindowPlatformAdapter {
  int showCalls = 0;
  int focusCalls = 0;
  int closeCalls = 0;

  @override
  Future<void> show() async {
    showCalls += 1;
  }

  @override
  Future<void> focus() async {
    focusCalls += 1;
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}
