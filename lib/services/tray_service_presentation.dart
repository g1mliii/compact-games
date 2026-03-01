part of 'tray_service.dart';

String trayMenuSignature({
  required TrayStatus status,
  required bool hasToggleHandler,
  required bool toggleInFlight,
}) {
  if (status.mode == TrayStatusMode.compressing &&
      status.activeGameName != null) {
    return 'c:${status.activeGameName}|a:${status.autoCompressionEnabled}|h:$hasToggleHandler|f:$toggleInFlight';
  }
  return '${status.mode.name}|a:${status.autoCompressionEnabled}|h:$hasToggleHandler|f:$toggleInFlight';
}

List<MenuItem> buildTrayMenuItems({
  required TrayStatus status,
  required bool hasToggleHandler,
  required bool toggleInFlight,
}) {
  final items = <MenuItem>[
    MenuItem(key: 'header', label: 'PressPlay', disabled: true),
    MenuItem.separator(),
  ];

  if (status.mode == TrayStatusMode.compressing &&
      status.activeGameName != null) {
    final label = 'Compressing: ${status.activeGameName}';
    items.add(MenuItem(key: 'status', label: label, disabled: true));
    items.add(MenuItem.separator());
  }

  items.addAll([
    MenuItem(key: 'show', label: 'Open PressPlay'),
    MenuItem(
      key: 'toggle_auto',
      label: status.autoCompressionEnabled
          ? 'Pause Auto-Compression'
          : 'Resume Auto-Compression',
      disabled: !hasToggleHandler || toggleInFlight,
    ),
    MenuItem.separator(),
    MenuItem(key: 'quit', label: 'Quit'),
  ]);
  return items;
}

String trayTooltipForStatus(TrayStatus status) {
  switch (status.mode) {
    case TrayStatusMode.compressing:
      final pct = status.progressPercent;
      return pct != null
          ? 'PressPlay — Compressing ${status.activeGameName} ($pct%)'
          : 'PressPlay — Compressing ${status.activeGameName}';
    case TrayStatusMode.paused:
      return 'PressPlay — Paused';
    case TrayStatusMode.error:
      return 'PressPlay — Error';
    case TrayStatusMode.idle:
      return 'PressPlay';
  }
}
