import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../providers/games/game_list_provider.dart';
import 'rust_bridge_service.dart';

/// Coalesces local unsupported-report payload preparation/submission so UI
/// actions do not repeatedly kick off overlapping background work.
class UnsupportedReportSyncService {
  static final UnsupportedReportSyncService instance =
      UnsupportedReportSyncService._();

  Future<void>? _inFlight;
  RustBridgeService? _pendingBridge;
  bool _needsFollowUpSync = false;

  UnsupportedReportSyncService._();

  Future<void> sync(ProviderContainer container) {
    final bridge = container.read(rustBridgeServiceProvider);
    return _syncWithBridge(bridge);
  }

  Future<void> _syncWithBridge(RustBridgeService bridge) {
    final existing = _inFlight;
    if (existing != null) {
      _needsFollowUpSync = true;
      _pendingBridge = bridge;
      return existing;
    }

    final future = () async {
      try {
        await bridge.syncUnsupportedReportCollection(
          appVersion: AppConstants.appVersion,
        );
      } catch (e) {
        final message = e.toString();
        if (message.contains('flutter_rust_bridge has not been initialized')) {
          return;
        }
        debugPrint('[unsupported-reports] sync skipped: $e');
      }
    }();

    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
        if (_needsFollowUpSync) {
          _needsFollowUpSync = false;
          final nextBridge = _pendingBridge ?? bridge;
          _pendingBridge = null;
          unawaited(_syncWithBridge(nextBridge));
        } else {
          _pendingBridge = null;
        }
      }
    });
  }

  void notePotentialChange(ProviderContainer container) {
    unawaited(sync(container));
  }

  @visibleForTesting
  void resetForTest() {
    _inFlight = null;
    _pendingBridge = null;
    _needsFollowUpSync = false;
  }
}
