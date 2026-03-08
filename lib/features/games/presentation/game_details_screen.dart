import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../providers/games/single_game_provider.dart';
import '../../../providers/system/platform_shell_provider.dart';
import 'widgets/game_details/game_details_body.dart';

class GameDetailsScreen extends ConsumerWidget {
  const GameDetailsScreen({required this.gamePath, super.key});

  final String gamePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameName = ref.watch(
      singleGameProvider(gamePath).select((g) => g?.name),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(gameName ?? 'Game Details', overflow: TextOverflow.ellipsis),
        actions: [
          if (gameName != null)
            IconButton(
              tooltip: 'Open directory',
              onPressed: () =>
                  ref.read(platformShellServiceProvider).openFolder(gamePath),
              icon: const Icon(LucideIcons.folderOpen),
            ),
        ],
      ),
      body: GameDetailsBody(gamePath: gamePath),
    );
  }
}
