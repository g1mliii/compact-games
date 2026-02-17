import 'package:flutter/material.dart';
import '../../../../core/utils/platform_icon.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/status_badge.dart';
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
    this.estimatedSavedBytes,
    this.assumeBoundedHeight = false,
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
  final int? estimatedSavedBytes;
  final bool assumeBoundedHeight;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          onSecondaryTapDown: onSecondaryTapDown,
          child: Container(
            decoration: BoxDecoration(
              gradient: AppColors.panelGradient,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: assumeBoundedHeight
                ? _buildBoundedBody(context)
                : _buildAdaptiveBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildAdaptiveBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxHeight.isFinite) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCoverArt(context: context, useAspectRatio: true),
              _buildGameInfo(),
            ],
          );
        }
        return _buildBoundedBody(context);
      },
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
    if (coverImageProvider == null && coverImageUrl == null) {
      return _buildPlaceholderCover();
    }

    final decodeWidth = _coverDecodeWidth(context);
    final provider = coverImageProvider ?? NetworkImage(coverImageUrl!);
    return ColoredBox(
      color: AppColors.surfaceElevated,
      child: Image(
        image: ResizeImage(provider, width: decodeWidth),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        filterQuality: FilterQuality.none,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholderCover(),
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return _buildPlaceholderCover();
        },
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.surfaceVariant, AppColors.surfaceElevated],
        ),
      ),
      child: Center(child: Icon(icon, size: 48, color: AppColors.desertSand)),
    );
  }

  Widget _buildGameInfo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
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
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _buildStatusBadge(),
            ),
          ),
          const SizedBox(height: 3),
          _buildSizeInfo(),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    if (isDirectStorage) {
      return const StatusBadge.directStorage();
    }

    if (isCompressed && compressedSizeBytes != null) {
      final savedBytes = totalSizeBytes - compressedSizeBytes!;
      final safeSavedBytes = savedBytes > 0 ? savedBytes : 0;
      final savedGB = safeSavedBytes / (1024 * 1024 * 1024);
      return StatusBadge.compressed(savedGB);
    }

    return const StatusBadge.notCompressed();
  }

  Widget _buildSizeInfo() {
    final sizeGB = totalSizeBytes / (1024 * 1024 * 1024);

    if (isCompressed && compressedSizeBytes != null) {
      final totalSizeBytes = this.totalSizeBytes;
      final compressedSizeBytes = this.compressedSizeBytes!;
      final compressedGB = this.compressedSizeBytes! / (1024 * 1024 * 1024);
      final rawRatio = totalSizeBytes > 0
          ? compressedSizeBytes / totalSizeBytes
          : 0.0;
      final ratio = rawRatio.clamp(0.0, 1.0).toDouble();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                '${compressedGB.toStringAsFixed(1)} GB',
                style: AppTypography.mono.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '/ ${sizeGB.toStringAsFixed(1)} GB',
                style: AppTypography.bodySmall.copyWith(
                  fontFamilyFallback: AppTypography.monoFontFallback,
                  decoration: TextDecoration.lineThrough,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          _CompressionBar(ratio: ratio),
        ],
      );
    }

    final estimatedSaved = estimatedSavedBytes;
    if (estimatedSaved != null && estimatedSaved > 0) {
      final savedGB = estimatedSaved / (1024 * 1024 * 1024);
      return Row(
        children: [
          Text(
            '${sizeGB.toStringAsFixed(1)} GB',
            style: AppTypography.mono.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '~${savedGB.toStringAsFixed(1)} GB saveable',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.success,
              fontSize: 11,
            ),
          ),
        ],
      );
    }

    return Text(
      '${sizeGB.toStringAsFixed(1)} GB',
      style: AppTypography.mono.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _CompressionBar extends StatelessWidget {
  const _CompressionBar({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: [
            Container(color: AppColors.surfaceElevated),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ratio,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.progressGradient,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
