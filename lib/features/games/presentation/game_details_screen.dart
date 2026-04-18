import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localization.dart';
import '../../../core/widgets/route_back_icon_button.dart';
import '../../../providers/games/single_game_provider.dart';
import 'widgets/game_details/game_details_body.dart';

const ValueKey<String> _gameDetailsBackButtonKey = ValueKey<String>(
  'gameDetailsBackButton',
);

class GameDetailsScreen extends StatelessWidget {
  const GameDetailsScreen({required this.gamePath, super.key});

  final String gamePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildRouteAppBar(
        context,
        title: _GameDetailsTitle(gamePath: gamePath),
        backButtonKey: _gameDetailsBackButtonKey,
      ),
      body: RepaintBoundary(child: GameDetailsBody(gamePath: gamePath)),
    );
  }
}

class _GameDetailsTitle extends ConsumerWidget {
  const _GameDetailsTitle({required this.gamePath});

  final String gamePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameName = ref.watch(
      singleGameProvider(gamePath).select((g) => g?.name),
    );
    return Text(
      gameName ?? context.l10n.gameDetailsTitleFallback,
      overflow: TextOverflow.ellipsis,
    );
  }
}
