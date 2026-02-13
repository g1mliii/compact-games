import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
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
    this.onTap,
    super.key,
  });

  final String gameName;
  final int totalSizeBytes;
  final int? compressedSizeBytes;
  final String? coverImageUrl;
  final bool isCompressed;
  final bool isDirectStorage;
  final VoidCallback? onTap;

  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  final ValueNotifier<bool> _isHovered = ValueNotifier<bool>(false);

  static final Matrix4 _hoverTransform = Matrix4.diagonal3Values(
    1.02,
    1.02,
    1.0,
  );

  @override
  void dispose() {
    _isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                transform: isHovered ? _hoverTransform : null,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: AppConstants.cardMinWidth,
                    maxWidth: AppConstants.cardMaxWidth,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isHovered ? AppColors.accent : AppColors.border,
                      width: 1,
                    ),
                    boxShadow: isHovered
                        ? [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.1),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: child,
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
      color: AppColors.surfaceElevated,
      child: const Center(
        child: Icon(LucideIcons.gamepad2, size: 48, color: AppColors.textMuted),
      ),
    );
  }

  Widget _buildGameInfo() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.gameName,
            style: AppTypography.headingSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          _buildStatusBadge(),
          const SizedBox(height: 8),
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
          ? 1 - (compressedSizeBytes / totalSizeBytes)
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
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _CompressionBar(ratio: ratio),
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
              child: Container(color: AppColors.compressed),
            ),
          ],
        ),
      ),
    );
  }
}
