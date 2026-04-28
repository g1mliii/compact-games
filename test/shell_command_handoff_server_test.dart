import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:compact_games/services/shell_command_handoff_server.dart';
import 'package:compact_games/services/shell_launch_args.dart';

void main() {
  test(
    'normal launch handoff asks running app to show existing window',
    () async {
      final tokenFile = _handoffTokenFile();
      if (tokenFile == null) {
        return;
      }

      final previousToken = await _readExistingToken(tokenFile);
      var showRequests = 0;
      try {
        final started = await ShellCommandHandoffServer.instance.start(
          onRequest: (_) {},
          onShowWindow: () {
            showRequests += 1;
          },
        );
        if (!started) {
          return;
        }

        final handedOff =
            await ShellCommandHandoffServer.handoffLaunchToRunningApp();

        expect(handedOff, isTrue);
        expect(showRequests, 1);
      } finally {
        await ShellCommandHandoffServer.instance.dispose();
        await _restoreToken(tokenFile, previousToken);
      }
    },
  );

  test(
    'shell action handoff forwards request without showing window',
    () async {
      final tokenFile = _handoffTokenFile();
      if (tokenFile == null) {
        return;
      }

      final previousToken = await _readExistingToken(tokenFile);
      final requests = <ShellActionRequest>[];
      var showRequests = 0;
      try {
        final started = await ShellCommandHandoffServer.instance.start(
          onRequest: requests.add,
          onShowWindow: () {
            showRequests += 1;
          },
        );
        if (!started) {
          return;
        }

        final handedOff =
            await ShellCommandHandoffServer.handoffLaunchToRunningApp(
              request: const ShellActionRequest(
                kind: ShellActionKind.compress,
                path: r'C:\Games\Example',
              ),
            );

        expect(handedOff, isTrue);
        expect(showRequests, 0);
        expect(requests, hasLength(1));
        expect(requests.single.kind, ShellActionKind.compress);
        expect(requests.single.path, r'C:\Games\Example');
      } finally {
        await ShellCommandHandoffServer.instance.dispose();
        await _restoreToken(tokenFile, previousToken);
      }
    },
  );

  test('failed server start preserves existing handoff token', () async {
    final tokenFile = _handoffTokenFile();
    if (tokenFile == null) {
      return;
    }

    ServerSocket? blocker;
    var hadPreviousToken = false;
    String? previousToken;
    try {
      blocker = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        49731,
        shared: false,
      );

      hadPreviousToken = await tokenFile.exists();
      if (hadPreviousToken) {
        previousToken = await tokenFile.readAsString();
      }
      await tokenFile.parent.create(recursive: true);
      await tokenFile.writeAsString('existing-token', flush: true);

      final started = await ShellCommandHandoffServer.instance.start(
        onRequest: (_) {},
        onShowWindow: () {},
      );

      expect(started, isFalse);
      expect(await tokenFile.readAsString(), 'existing-token');
    } on SocketException {
      return;
    } finally {
      await blocker?.close();
      if (hadPreviousToken) {
        await tokenFile.writeAsString(previousToken ?? '', flush: true);
      } else {
        try {
          if (await tokenFile.exists()) {
            await tokenFile.delete();
          }
        } catch (_) {}
      }
    }
  });
}

File? _handoffTokenFile() {
  final localAppData = Platform.environment['LOCALAPPDATA'];
  if (localAppData == null || localAppData.isEmpty) return null;
  return File(p.join(localAppData, 'compact_games', 'shell-handoff.token'));
}

Future<String?> _readExistingToken(File tokenFile) async {
  try {
    if (!await tokenFile.exists()) {
      return null;
    }
    return tokenFile.readAsString();
  } catch (_) {
    return null;
  }
}

Future<void> _restoreToken(File tokenFile, String? previousToken) async {
  if (previousToken != null) {
    await tokenFile.parent.create(recursive: true);
    await tokenFile.writeAsString(previousToken, flush: true);
    return;
  }
  try {
    if (await tokenFile.exists()) {
      await tokenFile.delete();
    }
  } catch (_) {}
}
