import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'perf_monitor.dart';

/// Debug-only draggable performance overlay toggled with F12.
///
/// Shows FPS, frame time, image cache usage, and startup duration.
/// Wrapped in [RepaintBoundary] to avoid affecting app paint performance.
class PerfOverlayManager extends StatefulWidget {
  const PerfOverlayManager({super.key, required this.child});
  final Widget child;

  @override
  State<PerfOverlayManager> createState() => _PerfOverlayManagerState();
}

class _PerfOverlayManagerState extends State<PerfOverlayManager> {
  bool _visible = false;
  late final FocusNode _focusNode = FocusNode(debugLabel: 'PerfOverlayToggle');

  @override
  void dispose() {
    PerfMonitor.instance.stopFrameTracking();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return widget.child;
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;

    return Directionality(
      textDirection: textDirection,
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          alignment: Alignment.topLeft,
          children: [widget.child, if (_visible) const _PerfOverlayPanel()],
        ),
      ),
    );
  }

  void _onKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f12) {
      setState(() => _visible = !_visible);
    }
  }
}

class _PerfOverlayPanel extends StatefulWidget {
  const _PerfOverlayPanel();

  @override
  State<_PerfOverlayPanel> createState() => _PerfOverlayPanelState();
}

class _PerfOverlayPanelState extends State<_PerfOverlayPanel> {
  late final Timer _timer;
  PerfSnapshot _snap = PerfMonitor.instance.snapshot();
  Offset _position = const Offset(12, 48);

  @override
  void initState() {
    super.initState();
    PerfMonitor.instance.beginFrameTracking();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _snap = PerfMonitor.instance.snapshot());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    PerfMonitor.instance.stopFrameTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cacheMb = (_snap.imageCacheBytes / (1024 * 1024)).toStringAsFixed(1);
    final startup = _snap.startupDuration;
    final startupStr = startup != null ? '${startup.inMilliseconds}ms' : '...';

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: RepaintBoundary(
        child: GestureDetector(
          onPanUpdate: (d) {
            setState(() => _position += d.delta);
          },
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
                color: Colors.white70,
                height: 1.5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'FPS: ${_snap.fps.toStringAsFixed(1)}  '
                    '(${_snap.avgFrameTimeMs.toStringAsFixed(1)}ms)',
                    style: TextStyle(
                      color: _snap.fps >= 55
                          ? Colors.greenAccent
                          : _snap.fps >= 30
                          ? Colors.orangeAccent
                          : Colors.redAccent,
                    ),
                  ),
                  Text('IMG: $cacheMb MB  (${_snap.imageCacheCount} items)'),
                  Text('Startup: $startupStr'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
