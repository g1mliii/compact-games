import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/status_badge.dart';

class GameCard extends StatefulWidget {
  const GameCard({
    required this.gameName,
    required this.totalSizeBytes,
    this.compressedSizeBytes,
    this.coverImageUrl,
    this.isCompressed = false,
    this.isDirectStorage = false,
    this.estimatedSavedBytes,
    this.onTap,
    super.key,
  });

  final String gameName;
  final int totalSizeBytes;
  final int? compressedSizeBytes;
  final String? coverImageUrl;
  final bool isCompressed;
  final bool isDirectStorage;
  final int? estimatedSavedBytes;
  final VoidCallback? onTap;

  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  final ValueNotifier<bool> _isHovered = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animationsEnabled = AppMotion.animationsEnabled(context);
    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: ValueListenableBuilder<bool>(
            valueListenable: _isHovered,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [_buildCoverArt(), _buildGameInfo()],
            ),
            builder: (context, isHovered, child) {
              final card = AnimatedContainer(
                duration: animationsEnabled ? AppMotion.base : Duration.zero,
                curve: AppMotion.standardCurve,
                decoration: BoxDecoration(
                  gradient: AppColors.panelGradient,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isHovered ? AppColors.richGold : AppColors.border,
                    width: 1,
                  ),
                ),
                child: child,
              );

              return AnimatedScale(
                scale: animationsEnabled && isHovered ? 1.015 : 1.0,
                duration: animationsEnabled ? AppMotion.base : Duration.zero,
                curve: AppMotion.standardCurve,
                child: AnimatedContainer(
                  duration: animationsEnabled ? AppMotion.base : Duration.zero,
                  curve: AppMotion.standardCurve,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: animationsEnabled && isHovered
                        ? [
                            BoxShadow(
                              color: AppColors.richGold.withValues(alpha: 0.22),
                              blurRadius: 22,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: card,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (_isHovered.value == value) {
      return;
    }
    _isHovered.value = value;
  }

  Widget _buildCoverArt() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: AspectRatio(
        aspectRatio: AppConstants.coverAspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (widget.coverImageUrl == null) {
              return _buildPlaceholderCover();
            }

            final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
            final logicalWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : AppConstants.cardMaxWidth;
            final decodeWidth = (logicalWidth * devicePixelRatio)
                .clamp(240.0, 960.0)
                .round();
            final decodeHeight = (decodeWidth / AppConstants.coverAspectRatio)
                .round();

            return Image.network(
              widget.coverImageUrl!,
              fit: BoxFit.cover,
              cacheWidth: decodeWidth,
              cacheHeight: decodeHeight,
              filterQuality: FilterQuality.low,
              errorBuilder: (context, error, stackTrace) =>
                  _buildPlaceholderCover(),
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) return child;
                return _buildPlaceholderCover();
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlaceholderCover() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.surfaceVariant, AppColors.surfaceElevated],
        ),
      ),
      child: const Center(
        child: Icon(
          LucideIcons.gamepad2,
          size: 48,
          color: AppColors.desertSand,
        ),
      ),
    );
  }

  Widget _buildGameInfo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.gameName,
            style: AppTypography.headingSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _buildStatusBadge(),
            ),
          ),
          const SizedBox(height: 6),
          _buildSizeInfo(),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    if (widget.isDirectStorage) {
      return const StatusBadge.directStorage();
    }

    if (widget.isCompressed && widget.compressedSizeBytes != null) {
      final savedBytes = widget.totalSizeBytes - widget.compressedSizeBytes!;
      final safeSavedBytes = savedBytes > 0 ? savedBytes : 0;
      final savedGB = safeSavedBytes / (1024 * 1024 * 1024);
      return StatusBadge.compressed(savedGB);
    }

    return const StatusBadge.notCompressed();
  }

  Widget _buildSizeInfo() {
    final sizeGB = widget.totalSizeBytes / (1024 * 1024 * 1024);

    if (widget.isCompressed && widget.compressedSizeBytes != null) {
      final totalSizeBytes = widget.totalSizeBytes;
      final compressedSizeBytes = widget.compressedSizeBytes!;
      final compressedGB = widget.compressedSizeBytes! / (1024 * 1024 * 1024);
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
          const SizedBox(height: 3),
          _CompressionBar(ratio: ratio),
        ],
      );
    }

    final estimatedSaved = widget.estimatedSavedBytes;
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
