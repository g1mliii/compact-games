import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'ui_memory_lifecycle.dart';

/// Debug-only performance metrics collector.
///
/// Tracks FPS (rolling 60-frame average), startup duration, and image cache
/// usage. Gated behind [kDebugMode] — all methods are no-ops in release.
class PerfMonitor {
  PerfMonitor._();
  static final PerfMonitor instance = PerfMonitor._();

  static final Stopwatch _startupWatch = Stopwatch();
  Duration? _startupDuration;

  final Queue<Duration> _frameTimes = Queue<Duration>();
  static const int _maxFrameSamples = 60;
  bool _timingsCallbackRegistered = false;

  /// Call at the very top of `main()`.
  static void markStartupBegin() {
    if (!kDebugMode) return;
    _startupWatch
      ..reset()
      ..start();
  }

  /// Call right after `runApp()`.
  static void markStartupEnd() {
    if (!kDebugMode) return;
    _startupWatch.stop();
    instance._startupDuration = _startupWatch.elapsed;
  }

  /// Start collecting frame timing data.
  void beginFrameTracking() {
    if (!kDebugMode) return;
    if (_timingsCallbackRegistered) return;
    _timingsCallbackRegistered = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// Stop collecting frame timing data and clear rolling samples.
  void stopFrameTracking() {
    if (!kDebugMode) return;
    if (!_timingsCallbackRegistered) return;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _timingsCallbackRegistered = false;
    _frameTimes.clear();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frameTimes.addLast(timing.totalSpan);
      while (_frameTimes.length > _maxFrameSamples) {
        _frameTimes.removeFirst();
      }
    }
  }

  /// Current metrics snapshot for the debug overlay.
  PerfSnapshot snapshot() {
    final avgFrameTime = _averageFrameTime();
    final fps = avgFrameTime.inMicroseconds > 0
        ? 1000000.0 / avgFrameTime.inMicroseconds
        : 0.0;

    return PerfSnapshot(
      fps: fps,
      avgFrameTimeMs: avgFrameTime.inMicroseconds / 1000.0,
      imageCacheBytes: UiMemoryLifecycle.currentImageCacheBytes,
      imageCacheCount: UiMemoryLifecycle.currentImageCacheCount,
      startupDuration: _startupDuration,
    );
  }

  Duration _averageFrameTime() {
    if (_frameTimes.isEmpty) return Duration.zero;
    final totalUs = _frameTimes.fold<int>(
      0,
      (sum, d) => sum + d.inMicroseconds,
    );
    return Duration(microseconds: totalUs ~/ _frameTimes.length);
  }
}

class PerfSnapshot {
  const PerfSnapshot({
    required this.fps,
    required this.avgFrameTimeMs,
    required this.imageCacheBytes,
    required this.imageCacheCount,
    this.startupDuration,
  });

  final double fps;
  final double avgFrameTimeMs;
  final int imageCacheBytes;
  final int imageCacheCount;
  final Duration? startupDuration;
}
