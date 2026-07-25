import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

final uninstallServiceProvider = Provider<UninstallService>((ref) {
  return const UninstallService();
});

class UninstallService {
  const UninstallService();

  Future<bool> launch() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return false;
    }
    final appDirectory = Directory(p.dirname(Platform.resolvedExecutable));
    final candidates =
        appDirectory
            .listSync(followLinks: false)
            .whereType<File>()
            .where(
              (file) => RegExp(
                r'^unins\d+\.exe$',
                caseSensitive: false,
              ).hasMatch(p.basename(file.path)),
            )
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    if (candidates.isEmpty) {
      return false;
    }
    await Process.start(
      candidates.first.path,
      const <String>[],
      mode: ProcessStartMode.detached,
    );
    return true;
  }
}
