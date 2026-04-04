import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pressplay/l10n/app_localizations.dart';

import '../../../../../core/localization/app_localization.dart';
import '../../../../../core/utils/cover_art_utils.dart';
import '../../../../../core/utils/date_time_format.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../models/game_info.dart';
import '../../../../../providers/compression/compression_progress_provider.dart';
import '../../../../../providers/compression/compression_state.dart';
import '../../../../../providers/cover_art/cover_art_provider.dart';
import '../../../../../providers/games/single_game_provider.dart';
import '../../../../../services/cover_art_service.dart';
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
  static const double _contentWidthBucket = 32;

  /// Cover left + info right with full-size cover art.
  static const double _wideLayoutBreakpoint = 980;

  /// Cover left + info right with compact cover art (used in split-view panel).
  static const double _compactRowBreakpoint = 380;
  static const double _coverColumnWidth = 300;
  static const double _compactCoverWidth = 120;

  final String gamePath;

  @override
  ConsumerState<GameDetailsBody> createState() => _GameDetailsBodyState();
}

class _GameDetailsBodyState extends ConsumerState<GameDetailsBody> {
  List<Object?>? _cachedSignature;
  Widget? _cachedViewport;

  @override
  Widget build(BuildContext context) {
    final hasGame = ref.watch(
      singleGameProvider(widget.gamePath).select((game) => game != null),
    );
    if (!hasGame) {
      _cachedSignature = null;
      _cachedViewport = null;
      return Center(
        child: Text(
          context.l10n.gameDetailsNotFound,
          style: AppTypography.bodyMedium,
        ),
      );
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = _bucketContentWidth(constraints.maxWidth);
        final wide = contentWidth >= GameDetailsBody._wideLayoutBreakpoint;
        final compactRow =
            contentWidth >= GameDetailsBody._compactRowBreakpoint;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Builder(
            builder: (scrollContext) {
              final deferred = Scrollable.recommendDeferredLoadingForContext(
                scrollContext,
              );
              final headerDecodeWidth = _decodeWidth(
                dpr: dpr,
                logicalWidth: contentWidth,
                min: 384,
                max: 768,
                bucket: 128,
              );
              final coverDecodeWidth = _decodeWidth(
                dpr: dpr,
                logicalWidth: wide
                    ? GameDetailsBody._coverColumnWidth
                    : GameDetailsBody._compactCoverWidth,
                min: wide ? 224 : 128,
                max: wide ? 512 : 320,
              );
              final nextSignature = <Object?>[
                widget.gamePath,
                contentWidth,
                wide,
                compactRow,
                headerDecodeWidth,
                coverDecodeWidth,
                deferred,
              ];
              // Check the cache BEFORE constructing host widgets so that we
              // avoid allocating new widget instances on every resize tick
              // when the bucketed signature hasn't changed.
              if (_hasMatchingViewportSignature(nextSignature)) {
                return _cachedViewport!;
              }

              final viewport = _buildViewport(
                contentWidth: contentWidth,
                wide: wide,
                compactRow: compactRow,
                headerDecodeWidth: headerDecodeWidth,
                coverDecodeWidth: coverDecodeWidth,
                deferred: deferred,
              );

              _cachedSignature = nextSignature;
              _cachedViewport = viewport;
              return viewport;
            },
          ),
        );
      },
    );
  }

  Widget _buildViewport({
    required double contentWidth,
    required bool wide,
    required bool compactRow,
    required int headerDecodeWidth,
    required int coverDecodeWidth,
    required bool deferred,
  }) {
    final header = _GameDetailsHeaderHost(
      gamePath: widget.gamePath,
      decodeWidth: headerDecodeWidth,
      deferred: deferred,
    );
    final cover = _GameDetailsCoverHost(
      gamePath: widget.gamePath,
      decodeWidth: coverDecodeWidth,
      deferred: deferred,
    );
    final rightColumn = _DetailsRightColumnHost(gamePath: widget.gamePath);

    return Center(
      child: SizedBox(
        width: contentWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 16),
            if (wide)
              _buildWideLayout(cover: cover, rightColumn: rightColumn)
            else if (compactRow)
              _buildCompactRowLayout(cover: cover, rightColumn: rightColumn)
            else
              _buildStackedLayout(cover: cover, rightColumn: rightColumn),
          ],
        ),
      ),
    );
  }

  Widget _buildWideLayout({
    required Widget cover,
    required Widget rightColumn,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: GameDetailsBody._coverColumnWidth, child: cover),
        const SizedBox(width: 16),
        Expanded(child: rightColumn),
      ],
    );
  }

  /// Side-by-side layout with a compact cover (used in the split-view panel).
  Widget _buildCompactRowLayout({
    required Widget cover,
    required Widget rightColumn,
  }) {
    const coverWidth = GameDetailsBody._compactCoverWidth;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: coverWidth, child: cover),
        const SizedBox(width: 12),
        Expanded(child: rightColumn),
      ],
    );
  }

  /// Stacked layout for very narrow viewports (< [GameDetailsBody._compactRowBreakpoint]).
  Widget _buildStackedLayout({
    required Widget cover,
    required Widget rightColumn,
  }) {
    const coverWidth = GameDetailsBody._compactCoverWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: coverWidth),
            child: cover,
          ),
        ),
        const SizedBox(height: 16),
        rightColumn,
      ],
    );
  }

  static int _decodeWidth({
    required double dpr,
    required double logicalWidth,
    required double min,
    required double max,
    int bucket = 64,
  }) {
    final raw = (logicalWidth * dpr).clamp(min, max);
    return ((raw / bucket).round() * bucket)
        .clamp(min.toInt(), max.toInt())
        .toInt();
  }

  bool _hasMatchingViewportSignature(List<Object?> nextSignature) {
    final currentSignature = _cachedSignature;
    return currentSignature != null &&
        _cachedViewport != null &&
        listEquals(currentSignature, nextSignature);
  }

  static double _bucketContentWidth(double maxWidth) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return maxWidth;
    }

    final clamped = maxWidth.clamp(0.0, GameDetailsBody.maxContentWidth);
    if (clamped <= GameDetailsBody._contentWidthBucket) {
      return clamped.toDouble();
    }
    final bucketed =
        (clamped / GameDetailsBody._contentWidthBucket).floor() *
        GameDetailsBody._contentWidthBucket;
    return bucketed.clamp(0.0, clamped).toDouble();
  }
}

class _GameDetailsHeaderHost extends ConsumerWidget {
  const _GameDetailsHeaderHost({
    required this.gamePath,
    required this.decodeWidth,
    required this.deferred,
  });

  final String gamePath;
  final int decodeWidth;
  final bool deferred;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    final l10n = context.l10n;
    final headerData = ref.watch(
      singleGameProvider(gamePath).select((game) {
        if (game == null) {
          return null;
        }
        return (
          name: game.name,
          platform: game.platform,
          statusKind: _detailsHeaderStatusKind(game),
          statusLabel: _detailsHeaderStatusLabel(l10n, game),
          lastCompressedText: formatLocalMonthDayTimeOrNull(
            game.lastCompressed,
            locale: locale,
          ),
        );
      }),
    );
    final activityLabel = ref.watch(
      activeCompressionJobProvider.select((job) {
        if (job == null || job.gamePath != gamePath || !job.isActive) {
          return null;
        }
        return job.type == CompressionJobType.compression
            ? l10n.gameDetailsActivityCompressingNow
            : l10n.gameDetailsActivityDecompressingNow;
      }),
    );
    final coverSnapshot = ref.watch(
      coverArtProvider(gamePath).select(_selectCoverArtSnapshot),
    );
    if (headerData == null) {
      return const SizedBox.shrink();
    }

    return GameDetailsHeader(
      gameName: headerData.name,
      platform: headerData.platform,
      statusKind: headerData.statusKind,
      statusLabel: headerData.statusLabel,
      lastCompressedLabel: headerData.lastCompressedText == null
          ? null
          : l10n.gameDetailsLastCompressedBadge(headerData.lastCompressedText!),
      activityLabel: activityLabel,
      coverProvider: _coverImageProviderFromSnapshot(coverSnapshot),
      coverArtType: coverArtTypeFromSource(coverSnapshot.source),
      decodeWidth: decodeWidth,
      deferred: deferred,
    );
  }
}

class _GameDetailsCoverHost extends ConsumerWidget {
  const _GameDetailsCoverHost({
    required this.gamePath,
    required this.decodeWidth,
    required this.deferred,
  });

  final String gamePath;
  final int decodeWidth;
  final bool deferred;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(
      singleGameProvider(gamePath).select((game) => game?.platform),
    );
    final coverSnapshot = ref.watch(
      coverArtProvider(gamePath).select(_selectCoverArtSnapshot),
    );
    if (platform == null) {
      return const SizedBox.shrink();
    }

    return GameDetailsCover(
      platform: platform,
      coverProvider: _coverImageProviderFromSnapshot(coverSnapshot),
      coverArtType: coverArtTypeFromSource(coverSnapshot.source),
      decodeWidth: decodeWidth,
      deferred: deferred,
    );
  }
}

({String? uri, int revision, CoverArtSource source}) _selectCoverArtSnapshot(
  AsyncValue<CoverArtResult> value,
) {
  final result = value.valueOrNull;
  return (
    uri: result?.uri,
    revision: result?.revision ?? 0,
    source: result?.source ?? CoverArtSource.none,
  );
}

ImageProvider<Object>? _coverImageProviderFromSnapshot(
  ({String? uri, int revision, CoverArtSource source}) coverSnapshot,
) {
  final coverUri = coverSnapshot.uri;
  return imageProviderFromCover(
    coverUri == null
        ? null
        : CoverArtResult(
            uri: coverUri,
            source: CoverArtSource.none,
            revision: coverSnapshot.revision,
          ),
  );
}

class _DetailsRightColumnHost extends ConsumerWidget {
  const _DetailsRightColumnHost({required this.gamePath});

  final String gamePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Select only the fields rendered in the right column so this host does not
    // rebuild when unrelated GameInfo fields change (e.g. cover art revision).
    final columnData = ref.watch(
      singleGameProvider(gamePath).select((game) {
        if (game == null) return null;
        return (
          sizeBytes: game.sizeBytes,
          compressedSize: game.compressedSize,
          isCompressed: game.isCompressed,
          isDirectStorage: game.isDirectStorage,
          isUnsupported: game.isUnsupported,
          savingsRatio: game.savingsRatio,
          lastCompressed: game.lastCompressed,
          // Pass through the full game for widgets that need all fields
          // (GameDetailsInfoCard).
          game: game,
        );
      }),
    );
    if (columnData == null) {
      return const SizedBox.shrink();
    }

    final currentSize = columnData.compressedSize ?? columnData.sizeBytes;
    final savedBytes = (columnData.sizeBytes - currentSize).clamp(
      0,
      columnData.sizeBytes,
    );
    final savingsPercent = (columnData.savingsRatio * 100).toStringAsFixed(1);
    final lastCompressedText = formatLocalMonthDayTimeOrNull(
      columnData.lastCompressed,
      locale: Localizations.localeOf(context),
    );

    return _DetailsRightColumn(
      game: columnData.game,
      currentSize: currentSize,
      savedBytes: savedBytes,
      savingsPercent: savingsPercent,
      lastCompressedText: lastCompressedText,
    );
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
      ],
    );
  }
}

GameDetailsStatusKind _detailsHeaderStatusKind(GameInfo game) {
  if (game.isUnsupported) {
    return GameDetailsStatusKind.unsupported;
  }
  if (game.isDirectStorage) {
    return GameDetailsStatusKind.directStorage;
  }
  if (game.isCompressed) {
    return GameDetailsStatusKind.compressed;
  }
  return GameDetailsStatusKind.ready;
}

String _detailsHeaderStatusLabel(AppLocalizations l10n, GameInfo game) {
  return switch (_detailsHeaderStatusKind(game)) {
    GameDetailsStatusKind.unsupported => l10n.gameStatusUnsupported,
    GameDetailsStatusKind.directStorage => l10n.gameStatusDirectStorage,
    GameDetailsStatusKind.compressed => l10n.gameDetailsStatusCompressed,
    GameDetailsStatusKind.ready => l10n.gameDetailsStatusReady,
  };
}
