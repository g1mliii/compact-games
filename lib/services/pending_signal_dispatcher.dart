import 'dart:async';
import 'dart:collection';

/// Broadcast dispatcher that buffers signals emitted before the UI attaches.
///
/// Shell handoffs arrive during startup, often before the widget tree has
/// mounted a listener. Dropping them would silently lose the launch intent, so
/// signals are held until the first listener attaches and replayed then.
class PendingSignalDispatcher<T> {
  PendingSignalDispatcher({this.coalescePending = false});

  /// When true, only the first buffered signal is replayed. Use for signals
  /// that carry no payload, where N identical replays are indistinguishable
  /// from one.
  final bool coalescePending;

  final Queue<T> _pending = Queue<T>();
  late final StreamController<T> _controller = StreamController<T>.broadcast(
    onListen: _markListenerAttached,
    onCancel: _markListenerDetached,
  );
  bool _hasListener = false;

  Stream<T> get requests => _controller.stream;

  void enqueue(T signal) {
    if (_controller.isClosed) {
      return;
    }
    if (!_hasListener) {
      if (coalescePending && _pending.isNotEmpty) {
        return;
      }
      _pending.addLast(signal);
      return;
    }
    _controller.add(signal);
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
