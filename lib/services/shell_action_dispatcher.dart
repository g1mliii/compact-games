import 'dart:async';
import 'dart:collection';

import 'shell_launch_args.dart';

class ShellActionDispatcher {
  ShellActionDispatcher._();

  static final ShellActionDispatcher instance = ShellActionDispatcher._();

  final Queue<ShellActionRequest> _pending = Queue<ShellActionRequest>();
  late final StreamController<ShellActionRequest> _controller =
      StreamController<ShellActionRequest>.broadcast(
        onListen: _markListenerAttached,
        onCancel: _markListenerDetached,
      );
  bool _hasListener = false;

  Stream<ShellActionRequest> get requests => _controller.stream;

  void enqueue(ShellActionRequest request) {
    if (_controller.isClosed) {
      return;
    }
    if (!_hasListener) {
      _pending.addLast(request);
      return;
    }
    _controller.add(request);
  }

  void _markListenerAttached() {
    _hasListener = true;
    scheduleMicrotask(_flushPending);
  }

  void _markListenerDetached() {
    _hasListener = false;
  }

  void _flushPending() {
    if (!_hasListener || _controller.isClosed) {
      return;
    }
    while (_pending.isNotEmpty) {
      _controller.add(_pending.removeFirst());
    }
  }
}
