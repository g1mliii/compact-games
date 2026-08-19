import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lifecycle/app_window_visibility.dart';

/// The refresh lifecycle every Library Home section shares.
///
/// The sections differ only in what they fetch and where they remember it; the
/// rules for *when* a refresh may run are identical and subtle enough that two
/// copies would drift. Kept in one place so a fix lands for every section.
mixin LibraryHomeSectionLifecycle<T> on AsyncNotifier<T> {
  var _disposed = false;

  /// Re-entrancy guard for `refresh`. Private because nothing renders it — a
  /// spinner would fight the cached content it is drawn over.
  var _refreshing = false;
  VoidCallback? _visibilityListener;

  /// Whether the provider has been torn down. Every asynchronous continuation
  /// has to check this before touching `state`.
  bool get isDisposed => _disposed;

  /// Refreshes from the network when allowed. Safe to call redundantly.
  Future<void> refresh();

  /// Clears the latched flags and arms teardown. Call first from `build`.
  ///
  /// Riverpod runs build-scoped onDispose callbacks on recomputation, not only
  /// on destruction, so the flags have to be cleared here. Otherwise the first
  /// rebuild latches them permanently and every later refresh bails.
  void armSectionLifecycle() {
    _disposed = false;
    _refreshing = false;
    ref.onDispose(() {
      _disposed = true;
      detachVisibilityListener();
    });
  }

  /// Whether [refresh] should stop immediately, either because the provider is
  /// gone or because a refresh is already in flight.
  bool get shouldSkipRefresh => _disposed || _refreshing;

  void scheduleRefreshAfterFirstPaint() {
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) {
      if (_disposed) return;
      unawaited(refresh());
    });
    // A post-frame callback only fires if another frame is scheduled; ask for
    // one so a static surface still triggers the refresh.
    binding.scheduleFrame();
  }

  /// Retries the skipped refresh the next time the window leaves the tray.
  ///
  /// One-shot and idempotent: the listener detaches itself as soon as it fires,
  /// so repeated [refresh] calls while hidden cannot stack subscriptions.
  void refreshWhenVisible() {
    if (_visibilityListener != null) return;
    void listener() {
      if (appWindowVisibilityController.isHiddenToTray) return;
      detachVisibilityListener();
      if (_disposed) return;
      unawaited(refresh());
    }

    _visibilityListener = listener;
    appWindowVisibilityController.addListener(listener);
  }

  void detachVisibilityListener() {
    final listener = _visibilityListener;
    if (listener == null) return;
    _visibilityListener = null;
    appWindowVisibilityController.removeListener(listener);
  }

  /// Runs [fetch] under the re-entrancy guard, answering [fallback] when it
  /// fails so a caller never has to distinguish "nothing new" from "it threw".
  Future<R> guardedFetch<R>(
    Future<R> Function() fetch, {
    required R fallback,
  }) async {
    _refreshing = true;
    try {
      return await fetch();
    } catch (_) {
      return fallback;
    } finally {
      _refreshing = false;
    }
  }
}
