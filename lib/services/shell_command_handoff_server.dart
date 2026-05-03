import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'shell_launch_args.dart';

const int _shellHandoffPort = 49731;
const String _shellHandoffMagic = 'compact-games-shell-action-v1';
const String _shellHandoffTokenDir = 'compact_games';
const String _shellHandoffTokenFile = 'shell-handoff.token';

abstract final class _HandoffProtocol {
  static const String magicKey = 'magic';
  static const String tokenKey = 'token';
  static const String requestKey = 'request';
  static const String commandKey = 'command';
  static const String ok = 'ok';
  static const String error = 'error';
}

class ShellCommandHandoffServer {
  ShellCommandHandoffServer._();

  static final ShellCommandHandoffServer instance =
      ShellCommandHandoffServer._();

  ServerSocket? _server;
  String? _token;

  Future<bool> start({
    required void Function(ShellActionRequest request) onRequest,
    required VoidCallback onShowWindow,
  }) async {
    if (_server != null) {
      return true;
    }

    ServerSocket? server;
    var tokenWritten = false;
    try {
      final token = _generateToken();
      server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _shellHandoffPort,
        shared: false,
      );
      await _writeTokenFile(token);
      tokenWritten = true;
      _server = server;
      _token = token;
      server.listen((socket) {
        unawaited(_handleClient(socket, onRequest, onShowWindow));
      });
      return true;
    } catch (error) {
      try {
        await server?.close();
      } catch (_) {}
      debugPrint('[shell] handoff server unavailable: $error');
      if (tokenWritten) {
        await _deleteTokenFile();
      }
      _token = null;
      return false;
    }
  }

  Future<void> dispose() async {
    final server = _server;
    _server = null;
    _token = null;
    await server?.close();
    await _deleteTokenFile();
  }

  static Future<bool> handoffLaunchToRunningApp({
    ShellActionRequest? request,
  }) async {
    return _handoffToRunningApp(<String, Object?>{
      _HandoffProtocol.commandKey: request == null ? 'show' : 'shellAction',
      if (request != null) _HandoffProtocol.requestKey: request.toJson(),
    });
  }

  static Future<bool> handoffToRunningApp(ShellActionRequest request) async {
    return handoffLaunchToRunningApp(request: request);
  }

  static Future<bool> _handoffToRunningApp(Map<String, Object?> payload) async {
    final token = await _readTokenFile();
    if (token == null) {
      // No running instance has advertised a token, or we lack permission
      // to read it. Caller will fall through to launching its own app.
      return false;
    }

    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _shellHandoffPort,
        timeout: const Duration(milliseconds: 250),
      );
      // Subscribe to the response stream BEFORE writing the request so we
      // don't lose the first line on fast localhost round-trips.
      final response = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(milliseconds: 500));
      socket.writeln(
        jsonEncode(<String, Object?>{
          _HandoffProtocol.magicKey: _shellHandoffMagic,
          _HandoffProtocol.tokenKey: token,
          ...payload,
        }),
      );
      await socket.flush();
      return (await response) == _HandoffProtocol.ok;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  Future<void> _handleClient(
    Socket socket,
    void Function(ShellActionRequest request) onRequest,
    VoidCallback onShowWindow,
  ) async {
    try {
      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 1));
      final decoded = jsonDecode(line);
      if (decoded is! Map ||
          decoded[_HandoffProtocol.magicKey] != _shellHandoffMagic) {
        socket.writeln(_HandoffProtocol.error);
        return;
      }
      final providedToken = decoded[_HandoffProtocol.tokenKey];
      if (providedToken is! String ||
          !_constantTimeEquals(providedToken, _token)) {
        // Wrong/missing token — likely a stranger probing the port. Drop
        // without acknowledging so we don't help an attacker enumerate.
        socket.writeln(_HandoffProtocol.error);
        return;
      }
      final command = decoded[_HandoffProtocol.commandKey];
      if (command == 'show') {
        onShowWindow();
      } else {
        final request =
            ShellActionRequest.fromJson(decoded[_HandoffProtocol.requestKey]);
        if (request == null) {
          socket.writeln(_HandoffProtocol.error);
          return;
        }
        // ok confirms the request was accepted into the in-process queue,
        // not that the underlying compress/decompress job succeeded — those
        // run asynchronously after this socket is closed.
        onRequest(request);
      }
      socket.writeln(_HandoffProtocol.ok);
    } catch (error) {
      debugPrint('[shell] handoff request failed: $error');
      socket.writeln(_HandoffProtocol.error);
    } finally {
      await socket.flush().catchError((_) {});
      await socket.close().catchError((_) {});
    }
  }

  static String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _constantTimeEquals(String a, String? b) {
    if (b == null || a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static File? _tokenFile() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) return null;
    return File(
      p.join(localAppData, _shellHandoffTokenDir, _shellHandoffTokenFile),
    );
  }

  static Future<void> _writeTokenFile(String token) async {
    final file = _tokenFile();
    if (file == null) {
      throw const FileSystemException(
        'LOCALAPPDATA is not set; cannot persist shell handoff token',
      );
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(token, flush: true);
  }

  static Future<String?> _readTokenFile() async {
    final file = _tokenFile();
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      final value = (await file.readAsString()).trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteTokenFile() async {
    final file = _tokenFile();
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best effort — a stale token is harmless because the next server
      // start overwrites it before binding the port.
    }
  }
}
