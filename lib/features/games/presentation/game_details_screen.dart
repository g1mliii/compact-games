import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localization.dart';
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: Navigator.of(context).canPop() ? 64 : null,
        leading: Navigator.of(context).canPop()
            ? Padding(
                padding: const EdgeInsets.only(left: 8),
                child: SizedBox(
                  key: _gameDetailsBackButtonKey,
                  width: 56,
                  height: 56,
                  child: IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              )
            : null,
        title: _GameDetailsTitle(gamePath: gamePath),
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
