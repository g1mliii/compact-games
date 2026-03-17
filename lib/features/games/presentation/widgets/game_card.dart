import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/localization/app_localization.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/utils/platform_icon.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../models/game_info.dart';

class GameCard extends StatelessWidget {
  const GameCard({
    required this.gameName,
    required this.platform,
    required this.totalSizeBytes,
    this.compressedSizeBytes,
    this.coverImageUrl,
    this.coverImageProvider,
    this.heroTag,
    this.isCompressed = false,
    this.isDirectStorage = false,
    this.isUnsupported = false,
    this.estimatedSavedBytes,
    this.lastCompressedText,
    this.assumeBoundedHeight = true,
    this.onTap,
    this.onSecondaryTapDown,
    super.key,
  });

  final String gameName;
  final Platform platform;
  final int totalSizeBytes;
  final int? compressedSizeBytes;
  final String? coverImageUrl;
  final ImageProvider<Object>? coverImageProvider;
  final String? heroTag;
  final bool isCompressed;
  final bool isDirectStorage;
  final bool isUnsupported;
  final int? estimatedSavedBytes;
  final String? lastCompressedText;
  final bool assumeBoundedHeight;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  static const BorderRadius _cardBorderRadius = BorderRadius.all(
    Radius.circular(12),
  );
  static const double _sizeInfoRegionHeight = 34;
  static const BoxDecoration _placeholderDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [AppColors.surfaceVariant, AppColors.surfaceElevated],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      child: DecoratedBox(
        decoration: buildAppSurfaceDecoration(borderRadius: _cardBorderRadius),
        child: assumeBoundedHeight
            ? _buildBoundedBody(context)
            : _buildAdaptiveBody(),
      ),
    );
  }

  Widget _buildAdaptiveBody() {
    return Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCoverArt(context: context, useAspectRatio: true),
          _buildGameInfo(),
        ],
      ),
    );
  }

  Widget _buildBoundedBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: _buildCoverArt(context: context, useAspectRatio: false),
        ),
        _buildGameInfo(),
      ],
    );
  }

  Widget _buildCoverArt({
    required BuildContext context,
    required bool useAspectRatio,
  }) {
    final content = _buildCoverContent(context);
    final wrappedContent = useAspectRatio
        ? AspectRatio(
            aspectRatio: AppConstants.coverAspectRatio,
            child: content,
          )
        : content;

    final clipped = ClipRRect(
      clipBehavior: Clip.hardEdge,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: wrappedContent,
    );

    final heroTag = this.heroTag;
    if (heroTag == null) {
      return clipped;
    }
    return Hero(tag: heroTag, child: clipped);
  }

  Widget _buildCoverContent(BuildContext context) {
    // Prefer explicit provider (all production callers pass this).
    if (coverImageProvider != null) {
      return _buildImageWithProvider(context, coverImageProvider!);
    }

    // Fallback placeholder when no provider is available.
    return _buildPlaceholderCover();
  }

  Widget _buildImageWithProvider(BuildContext context, ImageProvider provider) {
    final decodeWidth = _coverDecodeWidth(context);
    final deferred = Scrollable.recommendDeferredLoadingForContext(context);
    final filterQuality = deferred ? FilterQuality.none : FilterQuality.low;
    return ColoredBox(
      color: AppColors.surfaceElevated,
      child: _CachedResizeImage(
        provider: provider,
        decodeWidth: decodeWidth,
        filterQuality: filterQuality,
        placeholderBuilder: _buildPlaceholderCover,
      ),
    );
  }

  int _coverDecodeWidth(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final raw = (AppConstants.cardMaxWidth * dpr).clamp(192.0, 448.0);
    final bucketed = ((raw / 64).round() * 64).clamp(192, 448);
    return bucketed.toInt();
  }

  Widget _buildPlaceholderCover() {
    final icon = platformIcon(platform);
    return DecoratedBox(
      decoration: _placeholderDecoration,
      child: Center(child: Icon(icon, size: 48, color: AppColors.desertSand)),
    );
  }

  Widget _buildGameInfo() {
    return Builder(
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              gameName,
              style: AppTypography.headingSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 7),
            _buildStatusRow(context),
            const SizedBox(height: 8),
            _buildSizeInfo(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: _buildStatusBadge(context),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final l10n = context.l10n;
    if (isDirectStorage) {
      return StatusBadge(
        color: AppColors.directStorage,
        label: l10n.gameStatusDirectStorage,
        icon: LucideIcons.alertTriangle,
      );
    }
    if (isUnsupported) {
      return StatusBadge(
        color: AppColors.warning,
        label: l10n.gameStatusUnsupported,
        icon: LucideIcons.ban,
      );
    }

    if (isCompressed && compressedSizeBytes != null) {
      final savedBytes = totalSizeBytes - compressedSizeBytes!;
      final safeSavedBytes = savedBytes > 0 ? savedBytes : 0;
      final savedGB = safeSavedBytes / (1024 * 1024 * 1024);
      return StatusBadge(
        color: AppColors.compressed,
        label: l10n.gameSavedGigabytes(savedGB.toStringAsFixed(1)),
        icon: LucideIcons.checkCircle2,
      );
    }

    return StatusBadge(
      color: AppColors.richGold,
      label: l10n.homeStatusReadyToCompress,
      icon: LucideIcons.archive,
    );
  }

  Widget _buildSizeInfo(BuildContext context) {
    final l10n = context.l10n;
    final sizeGB = totalSizeBytes / (1024 * 1024 * 1024);

    if (isCompressed && compressedSizeBytes != null) {
      final totalSizeBytes = this.totalSizeBytes;
      final compressedSizeBytes = this.compressedSizeBytes!;
      final compressedGB = this.compressedSizeBytes! / (1024 * 1024 * 1024);
      final rawRatio = totalSizeBytes > 0
          ? compressedSizeBytes / totalSizeBytes
          : 0.0;
      final ratio = rawRatio.clamp(0.0, 1.0).toDouble();

      return SizedBox(
        height: _sizeInfoRegionHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCompressedMetaRow(
              context: context,
              compressedGB: compressedGB,
              sizeGB: sizeGB,
            ),
            const SizedBox(height: 2),
            _CompressionBar(ratio: ratio),
          ],
        ),
      );
    }

    final estimatedSaved = estimatedSavedBytes;
    if (estimatedSaved != null && estimatedSaved > 0) {
      final savedGB = estimatedSaved / (1024 * 1024 * 1024);
      return SizedBox(
        height: _sizeInfoRegionHeight,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Text(
                  l10n.commonGigabytes(sizeGB.toStringAsFixed(1)),
                  style: AppTypography.monoSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.gameEstimatedSaveableGigabytes(
                    savedGB.toStringAsFixed(1),
                  ),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.success,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: _sizeInfoRegionHeight,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Text(
          l10n.commonGigabytes(sizeGB.toStringAsFixed(1)),
          style: AppTypography.monoSmall.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildCompressedMetaRow({
    required BuildContext context,
    required double compressedGB,
    required double sizeGB,
  }) {
    final l10n = context.l10n;
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.commonGigabytes(compressedGB.toStringAsFixed(1)),
              style: AppTypography.monoSmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '/ ${l10n.commonGigabytes(sizeGB.toStringAsFixed(1))}',
              style: AppTypography.bodySmall.copyWith(
                fontSize: 12,
                fontFamilyFallback: AppTypography.monoFontFallback,
                decoration: TextDecoration.lineThrough,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CachedResizeImage extends StatefulWidget {
  const _CachedResizeImage({
    required this.provider,
    required this.decodeWidth,
    required this.filterQuality,
    required this.placeholderBuilder,
  });

  final ImageProvider provider;
  final int decodeWidth;
  final FilterQuality filterQuality;
  final Widget Function() placeholderBuilder;

  @override
  State<_CachedResizeImage> createState() => _CachedResizeImageState();
}

class _CachedResizeImageState extends State<_CachedResizeImage> {
  late ImageProvider _resizedProvider = ResizeImage(
    widget.provider,
    width: widget.decodeWidth,
  );

  @override
  void didUpdateWidget(covariant _CachedResizeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.provider, widget.provider) ||
        oldWidget.decodeWidth != widget.decodeWidth) {
      _resizedProvider = ResizeImage(
        widget.provider,
        width: widget.decodeWidth,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      image: _resizedProvider,
      fit: BoxFit.contain,
      isAntiAlias: true,
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      // Keep quality lightweight in steady state, and drop to none when
      // deferred loading is recommended (e.g. fast scrolling).
      filterQuality: widget.filterQuality,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => widget.placeholderBuilder(),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return widget.placeholderBuilder();
      },
    );
  }
}

class _CompressionBar extends StatelessWidget {
  const _CompressionBar({required this.ratio});

  final double ratio;
  static const BorderRadius _barRadius = BorderRadius.all(Radius.circular(2));
  static const BoxDecoration _fillDecoration = BoxDecoration(
    gradient: AppColors.progressGradient,
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: ClipRRect(
        borderRadius: _barRadius,
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            const ColoredBox(color: AppColors.surfaceElevated),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ratio,
              child: const DecoratedBox(decoration: _fillDecoration),
            ),
          ],
        ),
      ),
    );
  }
}
