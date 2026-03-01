import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressplay/providers/compression/compression_state.dart';
import 'package:pressplay/providers/system/auto_compression_status_provider.dart';
import 'package:pressplay/providers/system/tray_status_sync_provider.dart';
import 'package:pressplay/services/tray_service.dart';
import 'package:tray_manager/tray_manager.dart';

void main() {
  setUp(() {
    TrayService.instance.resetForTest();
  });

  tearDown(() async {
    await TrayService.instance.dispose();
    TrayService.instance.resetForTest();
  });

  test(
    'deriveTrayStatusMode prioritizes active compression over stream error',
    () {
      final mode = deriveTrayStatusMode(
        gameName: 'Game',
        jobStatus: CompressionJobStatus.running,
        autoRunning: false,
        autoRunningHasError: true,
      );
      expect(mode, TrayStatusMode.compressing);
    },
  );

  test('deriveTrayStatusMode emits error when automation stream fails', () {
    final mode = deriveTrayStatusMode(
      gameName: null,
      jobStatus: null,
      autoRunning: false,
      autoRunningHasError: true,
    );
    expect(mode, TrayStatusMode.error);
  });

  test('deriveTrayStatusMode emits paused when automation is stopped', () {
    final mode = deriveTrayStatusMode(
      gameName: null,
      jobStatus: null,
      autoRunning: false,
      autoRunningHasError: false,
    );
    expect(mode, TrayStatusMode.paused);
  });

  test(
    'deriveTrayStatusMode emits idle when automation is healthy and running',
    () {
      final mode = deriveTrayStatusMode(
        gameName: null,
        jobStatus: null,
        autoRunning: true,
        autoRunningHasError: false,
      );
      expect(mode, TrayStatusMode.idle);
    },
  );

  test(
    'trayStatusSyncProvider registers and unregisters tray toggle with container lifecycle',
    () async {
      final fakeTray = _FakeTrayPlatformAdapter();
      final fakeWindow = _FakeWindowPlatformAdapter();
      final service = TrayService.instance;
      service.configureForTest(
        trayPlatform: fakeTray,
        windowPlatform: fakeWindow,
        debounceDuration: const Duration(milliseconds: 5),
        iconPathOverride: r'C:\test\pressplay_tray.ico',
      );
      await service.init();
      expect(fakeTray.menuItemForKey('toggle_auto')?.disabled, isTrue);

      final container = ProviderContainer(
        overrides: [
          autoCompressionRunningProvider.overrideWith(
            (ref) => Stream<bool>.value(false),
          ),
        ],
      );

      container.read(trayStatusSyncProvider);
      await service.flushPendingUpdateForTest();
      expect(fakeTray.menuItemForKey('toggle_auto')?.disabled, isFalse);

      container.dispose();
      await service.flushPendingUpdateForTest();
      expect(fakeTray.menuItemForKey('toggle_auto')?.disabled, isTrue);
    },
  );
}

class _FakeTrayPlatformAdapter implements TrayPlatformAdapter {
  Menu? lastMenu;
  final List<TrayListener> _listeners = <TrayListener>[];

  @override
  void addListener(TrayListener listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(TrayListener listener) {
    _listeners.remove(listener);
  }

  @override
  Future<void> setIcon(String iconPath) async {}

  @override
  Future<void> setToolTip(String tooltip) async {}

  @override
  Future<void> setContextMenu(Menu menu) async {
    lastMenu = menu;
  }

  @override
  Future<void> popUpContextMenu() async {}

  @override
  Future<void> destroy() async {}

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

class _FakeWindowPlatformAdapter implements WindowPlatformAdapter {
  @override
  Future<void> show() async {}

  @override
  Future<void> focus() async {}

  @override
  Future<void> close() async {}
}
