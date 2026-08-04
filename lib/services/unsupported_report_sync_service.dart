import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../providers/games/game_list_provider.dart';
import '../providers/settings/settings_provider.dart';
import 'rust_bridge_service.dart';

/// Coalesces local unsupported-report payload preparation/submission so UI
/// actions do not repeatedly kick off overlapping background work.
class UnsupportedReportSyncService {
  static final UnsupportedReportSyncService instance =
      UnsupportedReportSyncService._();

  Future<void>? _inFlight;
  ProviderContainer? _pendingContainer;
  bool _needsFollowUpSync = false;

  UnsupportedReportSyncService._();

  Future<void> sync(ProviderContainer container) async {
    try {
      final settings = await container.read(settingsProvider.future);
      if (!settings.settings.shareUnsupportedReports) {
        return;
      }
    } catch (_) {
      // Reporting is opt-in and therefore fails closed if settings are not
      // available. A later user action or app start can retry the sync.
      return;
    }

    final bridge = container.read(rustBridgeServiceProvider);
    await _syncWithBridge(bridge, container);
  }

  Future<void> _syncWithBridge(
    RustBridgeService bridge,
    ProviderContainer container,
  ) {
    final existing = _inFlight;
    if (existing != null) {
      _needsFollowUpSync = true;
      _pendingContainer = container;
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
          final nextContainer = _pendingContainer ?? container;
          _pendingContainer = null;
          // Re-enter the public path so consent is checked again immediately
          // before each coalesced follow-up can reach the native bridge.
          unawaited(sync(nextContainer));
        } else {
          _pendingContainer = null;
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
    _pendingContainer = null;
    _needsFollowUpSync = false;
  }
}
