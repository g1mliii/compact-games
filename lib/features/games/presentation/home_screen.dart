import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/cinematic_background.dart';
import '../../../models/app_settings.dart';
import '../../../providers/settings/settings_provider.dart';
import 'widgets/home_compression_banner.dart';
import 'widgets/home_cover_art_nudge.dart';
import 'widgets/home_game_grid.dart';
import 'widgets/home_game_list_view.dart';
import 'widgets/home_header.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.homeViewMode ?? HomeViewMode.grid,
      ),
    );

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
              const HomeCoverArtNudge(),
              Expanded(
                child: viewMode == HomeViewMode.grid
                    ? const HomeGameGrid()
                    : const HomeGameListView(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
