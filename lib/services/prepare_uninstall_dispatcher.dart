import 'dart:async';

class PrepareUninstallDispatcher {
  PrepareUninstallDispatcher._();

  static final PrepareUninstallDispatcher instance =
      PrepareUninstallDispatcher._();

  late final StreamController<void> _controller =
      StreamController<void>.broadcast(onListen: _attach, onCancel: _detach);
  bool _hasListener = false;
  bool _pending = false;

  Stream<void> get requests => _controller.stream;

  void enqueue() {
    if (_controller.isClosed) return;
    if (!_hasListener) {
      _pending = true;
      return;
    }
    _controller.add(null);
  }

  void _attach() {
    _hasListener = true;
    if (_pending) {
      _pending = false;
      scheduleMicrotask(() => _controller.add(null));
    }
  }

  void _detach() {
    _hasListener = false;
  }
}
