part of 'tray_service.dart';

String trayMenuSignature({
  required TrayStatus status,
  required bool hasToggleHandler,
  required bool toggleInFlight,
}) {
  final localizedMenuSignature = Object.hash(
    status.strings.appName,
    status.strings.openAppLabel,
    status.strings.pauseAutoCompressionLabel,
    status.strings.resumeAutoCompressionLabel,
    status.strings.quitLabel,
    status.strings.compressingLabel,
  );
  if (status.mode == TrayStatusMode.compressing &&
      status.activeGameName != null) {
    return 'c:${status.activeGameName}|a:${status.autoCompressionEnabled}|h:$hasToggleHandler|f:$toggleInFlight|s:$localizedMenuSignature';
  }
  return '${status.mode.name}|a:${status.autoCompressionEnabled}|h:$hasToggleHandler|f:$toggleInFlight|s:$localizedMenuSignature';
}

List<MenuItem> buildTrayMenuItems({
  required TrayStatus status,
  required bool hasToggleHandler,
  required bool toggleInFlight,
}) {
  final strings = status.strings;
  final items = <MenuItem>[
    MenuItem(key: 'header', label: strings.appName, disabled: true),
    MenuItem.separator(),
  ];

  if (status.mode == TrayStatusMode.compressing &&
      status.activeGameName != null) {
    final label = '${strings.compressingLabel}: ${status.activeGameName}';
    items.add(MenuItem(key: 'status', label: label, disabled: true));
    items.add(MenuItem.separator());
  }

  items.addAll([
    MenuItem(key: 'show', label: strings.openAppLabel),
    MenuItem(
      key: 'toggle_auto',
      label: status.autoCompressionEnabled
          ? strings.pauseAutoCompressionLabel
          : strings.resumeAutoCompressionLabel,
      disabled: !hasToggleHandler || toggleInFlight,
    ),
    MenuItem.separator(),
    MenuItem(key: 'quit', label: strings.quitLabel),
  ]);
  return items;
}

String trayTooltipForStatus(TrayStatus status) {
  final strings = status.strings;
  switch (status.mode) {
    case TrayStatusMode.compressing:
      final pct = status.progressPercent;
      return pct != null
          ? '${strings.appName} - ${strings.compressingLabel} ${status.activeGameName} ($pct%)'
          : '${strings.appName} - ${strings.compressingLabel} ${status.activeGameName}';
    case TrayStatusMode.paused:
      return '${strings.appName} - ${strings.pausedStatusLabel}';
    case TrayStatusMode.error:
      return '${strings.appName} - ${strings.errorStatusLabel}';
    case TrayStatusMode.idle:
      return strings.appName;
  }
}
