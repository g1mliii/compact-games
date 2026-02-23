import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/utils/cover_art_utils.dart';
import '../../../core/theme/app_typography.dart';
import '../../../models/game_info.dart';
import '../../../providers/cover_art/cover_art_provider.dart';
import '../../../providers/games/single_game_provider.dart';
import '../../../providers/settings/settings_provider.dart';
import '../../../providers/system/platform_shell_provider.dart';
import 'widgets/game_details/details_actions.dart';
import 'widgets/game_details/details_info_card.dart';
import 'widgets/game_details/details_media.dart';

class GameDetailsScreen extends ConsumerStatefulWidget {
  const GameDetailsScreen({required this.gamePath, super.key});

  static const double _maxContentWidth = 1120;
  static const double _wideLayoutBreakpoint = 980;
  static const double _coverColumnWidth = 300;
  static const double _compactCoverWidth = 280;

  final String gamePath;

  @override
  ConsumerState<GameDetailsScreen> createState() => _GameDetailsScreenState();
}

class _GameDetailsScreenState extends ConsumerState<GameDetailsScreen> {
  bool _wide = false;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(singleGameProvider(widget.gamePath));
    if (game == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Game Details')),
        body: const Center(
          child: Text('Game not found.', style: AppTypography.bodyMedium),
        ),
      );
    }

    final coverResult = ref.watch(coverArtProvider(widget.gamePath)).valueOrNull;
    final coverProvider = imageProviderFromCover(coverResult);
    final isExcluded = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.excludedPaths.contains(widget.gamePath) ??
            false,
      ),
    );

    final currentSize = game.compressedSize ?? game.sizeBytes;
    final savedBytes = (game.sizeBytes - currentSize).clamp(0, game.sizeBytes);
    final savingsPercent = (game.savingsRatio * 100).toStringAsFixed(1);
    final lastPlayedText = _formatLastPlayed(game.lastPlayed);
    final deferred = Scrollable.recommendDeferredLoadingForContext(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(game.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Open directory',
            onPressed: () =>
                ref.read(platformShellServiceProvider).openFolder(game.path),
            icon: const Icon(LucideIcons.folderOpen),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= GameDetailsScreen._wideLayoutBreakpoint;
          _wide = wide;
          final contentWidth = constraints.maxWidth > GameDetailsScreen._maxContentWidth
              ? GameDetailsScreen._maxContentWidth
              : constraints.maxWidth;
          final coverWidth = _wide ? GameDetailsScreen._coverColumnWidth : GameDetailsScreen._compactCoverWidth;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: GameDetailsScreen._maxContentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GameDetailsHeader(
                      gameName: game.name,
                      platform: game.platform,
                      coverProvider: coverProvider,
                      decodeWidth: _decodeWidth(
                        context: context,
                        logicalWidth: contentWidth,
                        min: 384,
                        max: 768,
                        bucket: 128,
                      ),
                      deferred: deferred,
                    ),
                    const SizedBox(height: 16),
                    if (_wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: GameDetailsScreen._coverColumnWidth,
                            child: GameDetailsCover(
                              platform: game.platform,
                              coverProvider: coverProvider,
                              decodeWidth: _decodeWidth(
                                context: context,
                                logicalWidth: GameDetailsScreen._coverColumnWidth,
                                min: 224,
                                max: 512,
                              ),
                              deferred: deferred,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _DetailsRightColumn(
                              game: game,
                              isExcluded: isExcluded,
                              currentSize: currentSize,
                              savedBytes: savedBytes,
                              savingsPercent: savingsPercent,
                              lastPlayedText: lastPlayedText,
                              centeredActions: false,
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: GameDetailsScreen._compactCoverWidth,
                              ),
                              child: GameDetailsCover(
                                platform: game.platform,
                                coverProvider: coverProvider,
                                decodeWidth: _decodeWidth(
                                  context: context,
                                  logicalWidth: coverWidth,
                                  min: 224,
                                  max: 512,
                                ),
                                deferred: deferred,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _DetailsRightColumn(
                            game: game,
                            isExcluded: isExcluded,
                            currentSize: currentSize,
                            savedBytes: savedBytes,
                            savingsPercent: savingsPercent,
                            lastPlayedText: lastPlayedText,
                            centeredActions: true,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  int _decodeWidth({
    required BuildContext context,
    required double logicalWidth,
    required double min,
    required double max,
    int bucket = 64,
  }) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final raw = (logicalWidth * dpr).clamp(min, max);
    return ((raw / bucket).round() * bucket)
        .clamp(min.toInt(), max.toInt())
        .toInt();
  }

  String _formatLastPlayed(DateTime? value) {
    if (value == null) {
      return 'Unknown';
    }
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}

class _DetailsRightColumn extends StatelessWidget {
  const _DetailsRightColumn({
    required this.game,
    required this.isExcluded,
    required this.currentSize,
    required this.savedBytes,
    required this.savingsPercent,
    required this.lastPlayedText,
    required this.centeredActions,
  });

  final GameInfo game;
  final bool isExcluded;
  final int currentSize;
  final int savedBytes;
  final String savingsPercent;
  final String lastPlayedText;
  final bool centeredActions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GameDetailsInfoCard(
          game: game,
          isExcluded: isExcluded,
          currentSize: currentSize,
          savedBytes: savedBytes,
          savingsPercent: savingsPercent,
          lastPlayedText: lastPlayedText,
        ),
        if (game.isDirectStorage) ...[
          const SizedBox(height: 12),
          const GameDetailsDirectStorageWarningCard(),
        ],
        const SizedBox(height: 14),
        GameDetailsActionsCard(
          game: game,
          centered: centeredActions,
          isExcluded: isExcluded,
        ),
      ],
    );
  }
}
