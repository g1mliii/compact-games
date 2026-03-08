import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/cover_art_utils.dart';
import '../../../../../core/utils/date_time_format.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../models/game_info.dart';
import '../../../../../providers/cover_art/cover_art_provider.dart';
import '../../../../../providers/games/single_game_provider.dart';
import 'details_actions.dart';
import 'details_info_card.dart';
import 'details_media.dart';

/// Shared body content for the game details view.
/// Used by both the standalone [GameDetailsScreen] (wrapped in a Scaffold)
/// and the embedded split-view panel (inline, no Scaffold).
///
/// Caches the wide/compact layout mode so continuous window resize only
/// rebuilds the content subtree when the breakpoint actually crosses.
class GameDetailsBody extends ConsumerStatefulWidget {
  const GameDetailsBody({required this.gamePath, super.key});

  static const double maxContentWidth = 1120;
  static const double _wideLayoutBreakpoint = 980;
  static const double _coverColumnWidth = 300;
  static const double _compactCoverWidth = 280;

  final String gamePath;

  @override
  ConsumerState<GameDetailsBody> createState() => _GameDetailsBodyState();
}

class _GameDetailsBodyState extends ConsumerState<GameDetailsBody> {
  bool? _wide;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(singleGameProvider(widget.gamePath));
    if (game == null) {
      return const Center(
        child: Text('Game not found.', style: AppTypography.bodyMedium),
      );
    }

    final coverResult =
        ref.watch(coverArtProvider(widget.gamePath)).valueOrNull;
    final coverProvider = imageProviderFromCover(coverResult);

    final currentSize = game.compressedSize ?? game.sizeBytes;
    final savedBytes = (game.sizeBytes - currentSize).clamp(0, game.sizeBytes);
    final savingsPercent = (game.savingsRatio * 100).toStringAsFixed(1);
    final lastCompressedText = formatLocalMonthDayTimeOrNull(
      game.lastCompressed,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= GameDetailsBody._wideLayoutBreakpoint;
        // Only rebuild content subtree when layout mode changes.
        if (wide != _wide) {
          _wide = wide;
        }
        final contentWidth = constraints.maxWidth > GameDetailsBody.maxContentWidth
            ? GameDetailsBody.maxContentWidth
            : constraints.maxWidth;
        final coverWidth = wide
            ? GameDetailsBody._coverColumnWidth
            : GameDetailsBody._compactCoverWidth;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Builder(
            builder: (scrollContext) {
              final deferred =
                  Scrollable.recommendDeferredLoadingForContext(scrollContext);
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: GameDetailsBody.maxContentWidth,
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
                        _buildWideLayout(
                          game: game,
                          coverProvider: coverProvider,
                          scrollContext: scrollContext,
                          deferred: deferred,
                          currentSize: currentSize,
                          savedBytes: savedBytes,
                          savingsPercent: savingsPercent,
                          lastCompressedText: lastCompressedText,
                        )
                      else
                        _buildCompactLayout(
                          game: game,
                          coverProvider: coverProvider,
                          scrollContext: scrollContext,
                          coverWidth: coverWidth,
                          deferred: deferred,
                          currentSize: currentSize,
                          savedBytes: savedBytes,
                          savingsPercent: savingsPercent,
                          lastCompressedText: lastCompressedText,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildWideLayout({
    required GameInfo game,
    required ImageProvider<Object>? coverProvider,
    required BuildContext scrollContext,
    required bool deferred,
    required int currentSize,
    required int savedBytes,
    required String savingsPercent,
    required String? lastCompressedText,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: GameDetailsBody._coverColumnWidth,
          child: GameDetailsCover(
            platform: game.platform,
            coverProvider: coverProvider,
            decodeWidth: _decodeWidth(
              context: scrollContext,
              logicalWidth: GameDetailsBody._coverColumnWidth,
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
    );
  }

  Widget _buildCompactLayout({
    required GameInfo game,
    required ImageProvider<Object>? coverProvider,
    required BuildContext scrollContext,
    required double coverWidth,
    required bool deferred,
    required int currentSize,
    required int savedBytes,
    required String savingsPercent,
    required String? lastCompressedText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: coverWidth),
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
    );
  }

  static int _decodeWidth({
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
