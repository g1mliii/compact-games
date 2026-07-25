import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/game_path_key.dart';
import '../../models/managed_restore_plan.dart';
import '../../services/managed_restore_service.dart';
import '../compression/compression_provider.dart';
import '../compression/compression_state.dart';
import '../games/game_list_provider.dart';
import 'restore_gate_provider.dart';

final restoreGamesProvider =
    NotifierProvider<RestoreGamesNotifier, RestoreGamesState>(
      RestoreGamesNotifier.new,
    );

/// Why a managed game could not be restored.
///
/// The provider records the reason, never the sentence: display text is
/// resolved through `l10n` at the widget layer so failures are translated and
/// no job-status enum name leaks into the UI.
sealed class RestoreFailureReason {
  const RestoreFailureReason();
}

/// Compression admission rejected the game because it is already queued.
class RestoreAlreadyQueued extends RestoreFailureReason {
  const RestoreAlreadyQueued();
}

/// The decompression job ended in a state other than completed.
class RestoreEndedWith extends RestoreFailureReason {
  const RestoreEndedWith(this.status);

  final CompressionJobStatus status;
}

/// The decompression call threw before or while running.
class RestoreThrew extends RestoreFailureReason {
  const RestoreThrew(this.error);

  final String error;
}

class RestoreFailure {
  const RestoreFailure({required this.game, required this.reason});

  final ManagedRestoreGame game;
  final RestoreFailureReason reason;
}

class RestoreGamesState {
  const RestoreGamesState({
    this.plan,
    this.isLoading = false,
    this.isRestoring = false,
    this.completedGames = 0,
    this.totalGames = 0,
    this.failures = const <RestoreFailure>[],
    this.skippedGames = const <ManagedRestoreGame>[],
    this.restoreCompleted = false,
    this.error,
  });

  final ManagedRestorePlan? plan;
  final bool isLoading;
  final bool isRestoring;
  final int completedGames;
  final int totalGames;
  final List<RestoreFailure> failures;
  final List<ManagedRestoreGame> skippedGames;
  final bool restoreCompleted;
  final String? error;

  bool get hasFailures => failures.isNotEmpty;
  bool get canStart =>
      !isLoading &&
      !isRestoring &&
      failures.isEmpty &&
      (plan?.games.isNotEmpty ?? false) &&
      (plan?.hasEnoughSpace ?? false);
  bool get canOfferUninstall =>
      restoreCompleted &&
      !isLoading &&
      !isRestoring &&
      failures.isEmpty &&
      skippedGames.isEmpty &&
      (plan?.games.isEmpty ?? false);

  RestoreGamesState copyWith({
    ManagedRestorePlan? Function()? plan,
    bool? isLoading,
    bool? isRestoring,
    int? completedGames,
    int? totalGames,
    List<RestoreFailure>? failures,
    List<ManagedRestoreGame>? skippedGames,
    bool? restoreCompleted,
    String? Function()? error,
  }) {
    return RestoreGamesState(
      plan: plan != null ? plan() : this.plan,
      isLoading: isLoading ?? this.isLoading,
      isRestoring: isRestoring ?? this.isRestoring,
      completedGames: completedGames ?? this.completedGames,
      totalGames: totalGames ?? this.totalGames,
      failures: failures ?? this.failures,
      skippedGames: skippedGames ?? this.skippedGames,
      restoreCompleted: restoreCompleted ?? this.restoreCompleted,
      error: error != null ? error() : this.error,
    );
  }
}

class RestoreGamesNotifier extends Notifier<RestoreGamesState> {
  @override
  RestoreGamesState build() {
    ref.listen(managedRestoreRefreshProvider, (previous, next) {
      if (previous == next) return;
      unawaited(loadPlan());
    });
    Future<void>.microtask(loadPlan);
    return const RestoreGamesState(isLoading: true);
  }

  Future<void> loadPlan() async {
    if (state.isRestoring) return;
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final plan = await ref.read(managedRestoreServiceProvider).getPlan();
      state = state.copyWith(
        plan: () => plan,
        isLoading: false,
        error: () => null,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: () => error.toString());
    }
  }

  Future<void> restoreAll() async {
    if (state.isLoading || state.isRestoring || state.failures.isNotEmpty) {
      return;
    }

    state = state.copyWith(isLoading: true, error: () => null);
    late final ManagedRestorePlan preflight;
    try {
      // Recheck immediately before admission is paused so the game count,
      // filesystem state, and per-drive free-space check are current.
      preflight = await ref.read(managedRestoreServiceProvider).getPlan();
    } catch (error) {
      state = state.copyWith(isLoading: false, error: () => error.toString());
      return;
    }

    if (preflight.games.isEmpty || !preflight.hasEnoughSpace) {
      state = state.copyWith(
        plan: () => preflight,
        isLoading: false,
        restoreCompleted: false,
      );
      return;
    }

    _pauseAutomationAndCompressionAdmission();
    state = state.copyWith(
      plan: () => preflight,
      isLoading: false,
      isRestoring: true,
      completedGames: 0,
      totalGames: preflight.gameCount,
      failures: const <RestoreFailure>[],
      skippedGames: const <ManagedRestoreGame>[],
      restoreCompleted: false,
      error: () => null,
    );

    final compression = ref.read(compressionProvider.notifier);
    final queued = <ManagedRestoreGame, Future<CompressionJobStatus?>>{};
    for (final game in preflight.games) {
      queued[game] = compression.startDecompressionAndWait(
        gamePath: game.gamePath,
        gameName: game.gameName,
      );
    }

    final failures = <RestoreFailure>[];
    var completed = 0;
    for (final entry in queued.entries) {
      try {
        final status = await entry.value;
        if (status == CompressionJobStatus.completed) {
          completed += 1;
        } else {
          failures.add(
            RestoreFailure(game: entry.key, reason: _statusReason(status)),
          );
        }
      } catch (error) {
        failures.add(
          RestoreFailure(game: entry.key, reason: RestoreThrew('$error')),
        );
      }
      state = state.copyWith(
        completedGames: completed,
        failures: List<RestoreFailure>.unmodifiable(failures),
      );
    }

    final refreshedPlan = await _refreshPlanBestEffort(preflight);
    if (failures.isEmpty) {
      _resumeAutomationAndCompressionAdmission();
      state = state.copyWith(
        plan: () => refreshedPlan,
        isRestoring: false,
        completedGames: completed,
        failures: const <RestoreFailure>[],
        restoreCompleted: refreshedPlan.games.isEmpty,
      );
      await _refreshGames();
      return;
    }

    // Release the gate now that the restore run has stopped. Leaving it engaged
    // would silently block every manual and automatic compression app-wide with
    // no user feedback until each failure is resolved. The remaining failures
    // stay visible in the Settings restore section for Retry/Skip, and each
    // retry re-pauses the gate for the duration of its own decompression.
    _resumeAutomationAndCompressionAdmission();
    state = state.copyWith(
      plan: () => refreshedPlan,
      isRestoring: false,
      completedGames: completed,
      failures: List<RestoreFailure>.unmodifiable(failures),
      restoreCompleted: false,
    );
    await _refreshGames();
  }

  Future<void> retryFailure(String gamePath) async {
    if (state.isRestoring) return;
    final index = state.failures.indexWhere(
      (failure) => gamePathKey(failure.game.gamePath) == gamePathKey(gamePath),
    );
    if (index < 0) return;
    final failure = state.failures[index];

    _pauseAutomationAndCompressionAdmission();
    state = state.copyWith(isRestoring: true, error: () => null);
    CompressionJobStatus? status;
    RestoreFailureReason? thrownReason;
    try {
      status = await ref
          .read(compressionProvider.notifier)
          .startDecompressionAndWait(
            gamePath: failure.game.gamePath,
            gameName: failure.game.gameName,
          );
    } catch (error) {
      thrownReason = RestoreThrew('$error');
    }

    final failures = <RestoreFailure>[...state.failures]..removeAt(index);
    var completed = state.completedGames;
    if (status == CompressionJobStatus.completed) {
      completed += 1;
    } else {
      failures.add(
        RestoreFailure(
          game: failure.game,
          reason: thrownReason ?? _statusReason(status),
        ),
      );
    }

    final plan = await _refreshPlanBestEffort(state.plan);
    final allSucceeded = failures.isEmpty && plan.games.isEmpty;
    // The retry has stopped, so release the gate regardless of remaining
    // failures. A later retry re-pauses it around its own decompression.
    _resumeAutomationAndCompressionAdmission();
    state = state.copyWith(
      plan: () => plan,
      isRestoring: false,
      completedGames: completed,
      failures: List<RestoreFailure>.unmodifiable(failures),
      restoreCompleted: allSucceeded,
    );
    await _refreshGames();
  }

  Future<void> skipFailure(String gamePath) async {
    if (state.isRestoring) return;
    final index = state.failures.indexWhere(
      (failure) => gamePathKey(failure.game.gamePath) == gamePathKey(gamePath),
    );
    if (index < 0) return;
    final skipped = state.failures[index].game;
    final failures = <RestoreFailure>[...state.failures]..removeAt(index);
    if (failures.isEmpty) {
      _resumeAutomationAndCompressionAdmission();
    }
    state = state.copyWith(
      failures: List<RestoreFailure>.unmodifiable(failures),
      skippedGames: List<ManagedRestoreGame>.unmodifiable([
        ...state.skippedGames,
        skipped,
      ]),
      restoreCompleted: false,
    );
  }

  void _pauseAutomationAndCompressionAdmission() {
    ref.read(restoreGateProvider.notifier).pauseCompressionAdmission();
    try {
      ref.read(rustBridgeServiceProvider).stopAutoCompression();
    } catch (_) {
      // The reactive automation sync also observes restoreGateProvider.
    }
  }

  void _resumeAutomationAndCompressionAdmission() {
    ref.read(restoreGateProvider.notifier).resumeCompressionAdmission();
  }

  Future<ManagedRestorePlan> _refreshPlanBestEffort(
    ManagedRestorePlan? fallback,
  ) async {
    try {
      return await ref.read(managedRestoreServiceProvider).getPlan();
    } catch (error) {
      state = state.copyWith(error: () => error.toString());
      return fallback ?? const ManagedRestorePlan(games: [], drives: []);
    }
  }

  Future<void> _refreshGames() async {
    try {
      await ref.read(gameListProvider.notifier).refresh();
    } catch (_) {
      // Restore ownership is already durable in Rust; discovery refresh is UX.
    }
  }

  /// A null status means admission rejected the game (already queued).
  RestoreFailureReason _statusReason(CompressionJobStatus? status) =>
      status == null ? const RestoreAlreadyQueued() : RestoreEndedWith(status);
}
