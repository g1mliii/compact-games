enum ShellActionKind {
  compress('compress'),
  decompress('decompress');

  const ShellActionKind(this.wireName);

  final String wireName;

  static ShellActionKind? fromWireName(String value) {
    final normalized = value.trim().toLowerCase();
    for (final kind in ShellActionKind.values) {
      if (kind.wireName == normalized) {
        return kind;
      }
    }
    return null;
  }
}

class ShellActionRequest {
  const ShellActionRequest({required this.kind, required this.path});

  final ShellActionKind kind;
  final String path;

  Map<String, Object?> toJson() {
    return <String, Object?>{'kind': kind.wireName, 'path': path};
  }

  static ShellActionRequest? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final kindValue = value['kind'];
    final pathValue = value['path'];
    if (kindValue is! String || pathValue is! String) {
      return null;
    }
    final kind = ShellActionKind.fromWireName(kindValue);
    final path = pathValue.trim();
    if (kind == null || path.isEmpty) {
      return null;
    }
    return ShellActionRequest(kind: kind, path: path);
  }
}

class ShellLaunchArgs {
  const ShellLaunchArgs({
    required this.startHiddenInTray,
    required this.shellAction,
  });

  final bool startHiddenInTray;
  final ShellActionRequest? shellAction;

  static ShellLaunchArgs parse(List<String> args) {
    final minimized = args.contains('--minimized');
    final actionValue = _optionValue(args, '--shell-action');
    final pathValue = _optionValue(args, '--path');
    final actionKind = actionValue == null
        ? null
        : ShellActionKind.fromWireName(actionValue);
    final path = pathValue?.trim();
    final request = actionKind != null && path != null && path.isNotEmpty
        ? ShellActionRequest(kind: actionKind, path: path)
        : null;

    // Only start hidden when we actually have a shell action to execute.
    // If `--shell-action garbage` was passed (or `--path` is missing) we
    // would otherwise launch a tray-only ghost process that never enqueues
    // anything.
    return ShellLaunchArgs(
      startHiddenInTray: minimized || request != null,
      shellAction: request,
    );
  }
}

String? _optionValue(List<String> args, String option) {
  final prefix = '$option=';
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == option) {
      final nextIndex = i + 1;
      if (nextIndex >= args.length) {
        return null;
      }
      return args[nextIndex];
    }
    if (arg.startsWith(prefix)) {
      return arg.substring(prefix.length);
    }
  }
  return null;
}
