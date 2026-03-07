import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/utils/cover_art_utils.dart';
import '../../../core/utils/date_time_format.dart';
import '../../../core/theme/app_typography.dart';
import '../../../models/game_info.dart';
import '../../../providers/cover_art/cover_art_provider.dart';
import '../../../providers/games/single_game_provider.dart';
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

    final coverResult = ref
        .watch(coverArtProvider(widget.gamePath))
        .valueOrNull;
    final coverProvider = imageProviderFromCover(coverResult);

    final currentSize = game.compressedSize ?? game.sizeBytes;
    final savedBytes = (game.sizeBytes - currentSize).clamp(0, game.sizeBytes);
    final savingsPercent = (game.savingsRatio * 100).toStringAsFixed(1);
    final lastCompressedText = formatLocalMonthDayTimeOrNull(
      game.lastCompressed,
    );

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
          final wide =
              constraints.maxWidth >= GameDetailsScreen._wideLayoutBreakpoint;
          final contentWidth =
              constraints.maxWidth > GameDetailsScreen._maxContentWidth
              ? GameDetailsScreen._maxContentWidth
              : constraints.maxWidth;
          final coverWidth = wide
              ? GameDetailsScreen._coverColumnWidth
              : GameDetailsScreen._compactCoverWidth;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Builder(
              builder: (scrollContext) {
                final deferred = Scrollable.recommendDeferredLoadingForContext(
                  scrollContext,
                );
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: GameDetailsScreen._maxContentWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GameDetailsHeader(
                          gameName: game.name,
                          platform: game.platform,
                          coverProvider: coverProvider,
                          decodeWidth: _decodeWidth(
                            context: scrollContext,
                            logicalWidth: contentWidth,
                            min: 384,
                            max: 768,
                            bucket: 128,
                          ),
                          deferred: deferred,
                        ),
                        const SizedBox(height: 16),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: GameDetailsScreen._coverColumnWidth,
                                child: GameDetailsCover(
                                  platform: game.platform,
                                  coverProvider: coverProvider,
                                  decodeWidth: _decodeWidth(
                                    context: scrollContext,
                                    logicalWidth:
                                        GameDetailsScreen._coverColumnWidth,
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
                                  currentSize: currentSize,
                                  savedBytes: savedBytes,
                                  savingsPercent: savingsPercent,
                                  lastCompressedText: lastCompressedText,
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
                                    maxWidth:
                                        GameDetailsScreen._compactCoverWidth,
                                  ),
                                  child: GameDetailsCover(
                                    platform: game.platform,
                                    coverProvider: coverProvider,
                                    decodeWidth: _decodeWidth(
                                      context: scrollContext,
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
                                currentSize: currentSize,
                                savedBytes: savedBytes,
                                savingsPercent: savingsPercent,
                                lastCompressedText: lastCompressedText,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
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
}

class _DetailsRightColumn extends StatelessWidget {
  const _DetailsRightColumn({
    required this.game,
    required this.currentSize,
    required this.savedBytes,
    required this.savingsPercent,
    required this.lastCompressedText,
  });

  final GameInfo game;
  final int currentSize;
  final int savedBytes;
  final String savingsPercent;
  final String? lastCompressedText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GameDetailsInfoCard(
          game: game,
          currentSize: currentSize,
          savedBytes: savedBytes,
          savingsPercent: savingsPercent,
          lastCompressedText: lastCompressedText,
        ),
        if (game.isDirectStorage) ...[
          const SizedBox(height: 12),
          const GameDetailsDirectStorageWarningCard(),
        ],
        if (game.isUnsupported) ...[
          const SizedBox(height: 12),
          const GameDetailsUnsupportedWarningCard(),
        ],
      ],
    );
  }
}
