import 'dart:io';

import 'package:compact_games/services/uninstall_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory appDirectory;

  setUp(() async {
    appDirectory = await Directory.systemTemp.createTemp(
      'compact_games_uninstall_test_',
    );
  });

  tearDown(() async {
    if (await appDirectory.exists()) {
      await appDirectory.delete(recursive: true);
    }
  });

  test(
    'launches the installed uninstaller before requesting app exit',
    () async {
      final first = File(
        '${appDirectory.path}${Platform.pathSeparator}unins000.exe',
      );
      final second = File(
        '${appDirectory.path}${Platform.pathSeparator}unins001.exe',
      );
      await first.create();
      await second.create();
      final lifecycle = <String>[];
      String? launchedPath;
      final service = UninstallService(
        isWindows: true,
        appDirectoryResolver: () => appDirectory,
        launcher: (path) async {
          lifecycle.add('uninstaller');
          launchedPath = path;
        },
        exitRequest: () async {
          lifecycle.add('exit');
        },
      );

      expect(await service.launch(), isTrue);
      expect(launchedPath, first.path);
      expect(lifecycle, <String>['uninstaller', 'exit']);
    },
  );

  test('does not exit when no installed uninstaller is found', () async {
    var launchCalls = 0;
    var exitCalls = 0;
    final service = UninstallService(
      isWindows: true,
      appDirectoryResolver: () => appDirectory,
      launcher: (_) async {
        launchCalls += 1;
      },
      exitRequest: () async {
        exitCalls += 1;
      },
    );

    expect(await service.launch(), isFalse);
    expect(launchCalls, 0);
    expect(exitCalls, 0);
  });
}
