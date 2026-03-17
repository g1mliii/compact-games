import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/cinematic_background.dart';
import '../../../models/app_settings.dart';
import '../../../providers/compression/compression_progress_provider.dart';
import '../../../providers/games/game_list_provider.dart';
import '../../../providers/settings/settings_provider.dart';
import 'widgets/home_compression_banner.dart';
import 'widgets/home_cover_art_nudge.dart';
import 'widgets/home_game_grid.dart';
import 'widgets/home_game_list_view.dart';
import 'widgets/home_header.dart';
import 'widgets/home_overview_panel.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CinematicBackground(
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: HomeHeader(),
              ),
              const HomeCompressionBanner(),
              const HomeOverviewPanel(),
              const _HomeCoverArtNudgeSlot(),
              const Expanded(child: _HomeContentSwitcher()),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeContentSwitcher extends ConsumerWidget {
  const _HomeContentSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.homeViewMode ?? HomeViewMode.grid,
      ),
    );

    return viewMode == HomeViewMode.grid
        ? const HomeGameGrid()
        : const HomeGameListView();
  }
}

/// Outer shell: reacts only to the viewport size booleans. When the size
/// thresholds are not met it short-circuits with a zero-size box without
/// subscribing to provider state at all.
class _HomeCoverArtNudgeSlot extends StatelessWidget {
  const _HomeCoverArtNudgeSlot();

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final fitsWidth = viewport.width >= 360;
    final fitsHeight = viewport.height >= 760;
    if (!fitsWidth || !fitsHeight) return const SizedBox.shrink();
    return const _HomeCoverArtNudgeContent();
  }
}

/// Inner content: only instantiated when the viewport thresholds are already
/// met. Does NOT call MediaQuery so it won't rebuild on window resize.
class _HomeCoverArtNudgeContent extends ConsumerWidget {
  const _HomeCoverArtNudgeContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(activeCompressionUiModelProvider);
    final libraryState = ref.watch(
      gameListProvider.select(
        (state) => (
          gameCount: state.valueOrNull?.games.length ?? 0,
          error: state.valueOrNull?.error,
        ),
      ),
    );

    final shouldShow =
        activity == null &&
        libraryState.gameCount > 0 &&
        libraryState.error == null;

    return shouldShow ? const HomeCoverArtNudge() : const SizedBox.shrink();
  }
}
