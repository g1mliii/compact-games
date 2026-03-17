import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/localization/app_localization.dart';
import '../../../../../core/localization/presentation_labels.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/platform_icon.dart';
import '../../../../../core/widgets/status_badge.dart';
import '../../../../../models/game_info.dart';

const double _headerHeight = 156;
const ValueKey<String> _detailsHeaderStatusBadgeKey = ValueKey<String>(
  'detailsHeaderStatusBadge',
);
const ValueKey<String> _detailsHeaderLastCompressedBadgeKey = ValueKey<String>(
  'detailsHeaderLastCompressedBadge',
);
const ValueKey<String> _detailsHeaderActivityBadgeKey = ValueKey<String>(
  'detailsHeaderActivityBadge',
);

enum GameDetailsStatusKind { ready, compressed, directStorage, unsupported }

class GameDetailsHeader extends StatelessWidget {
  const GameDetailsHeader({
    required this.gameName,
    required this.platform,
    required this.statusKind,
    required this.statusLabel,
    required this.coverProvider,
    required this.decodeWidth,
    required this.deferred,
    this.lastCompressedLabel,
    this.activityLabel,
    super.key,
  });

  static final _scrimTop = Colors.black.withValues(alpha: 0.08);
  static final _scrimMid = Colors.black.withValues(alpha: 0.24);
  static final _scrimBottom = AppColors.nightDune.withValues(alpha: 0.9);

  final String gameName;
  final Platform platform;
  final GameDetailsStatusKind statusKind;
  final String statusLabel;
  final ImageProvider<Object>? coverProvider;
  final int decodeWidth;
  final bool deferred;
  final String? lastCompressedLabel;
  final String? activityLabel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: _headerHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: _HeaderBackgroundArt(
                coverProvider: coverProvider,
                decodeWidth: decodeWidth,
                deferred: deferred,
                platform: platform,
              ),
            ),
            RepaintBoundary(
              child: _HeaderForeground(
                gameName: gameName,
                platform: platform,
                statusKind: statusKind,
                statusLabel: statusLabel,
                lastCompressedLabel: lastCompressedLabel,
                activityLabel: activityLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _statusBadgeColor(GameDetailsStatusKind statusKind) {
  return switch (statusKind) {
    GameDetailsStatusKind.unsupported => AppColors.warning,
    GameDetailsStatusKind.compressed => AppColors.richGold,
    GameDetailsStatusKind.directStorage => AppColors.directStorage,
    GameDetailsStatusKind.ready => AppColors.info,
  };
}

class _HeaderForeground extends StatelessWidget {
  const _HeaderForeground({
    required this.gameName,
    required this.platform,
    required this.statusKind,
    required this.statusLabel,
    this.lastCompressedLabel,
    this.activityLabel,
  });

  final String gameName;
  final Platform platform;
  final GameDetailsStatusKind statusKind;
  final String statusLabel;
  final String? lastCompressedLabel;
  final String? activityLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.56, 1],
          colors: [
            GameDetailsHeader._scrimTop,
            GameDetailsHeader._scrimMid,
            GameDetailsHeader._scrimBottom,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HeaderBadge(
                  badgeKey: _detailsHeaderStatusBadgeKey,
                  label: statusLabel,
                  color: _statusBadgeColor(statusKind),
                ),
                if (lastCompressedLabel != null)
                  _HeaderBadge(
                    badgeKey: _detailsHeaderLastCompressedBadgeKey,
                    label: lastCompressedLabel!,
                    color: AppColors.info,
                  ),
                if (activityLabel != null)
                  _HeaderBadge(
                    badgeKey: _detailsHeaderActivityBadgeKey,
                    label: activityLabel!,
                    color: AppColors.richGold,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              gameName,
              style: AppTypography.headingMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  platformIcon(platform),
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  platform.localizedLabel(context.l10n),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.badgeKey,
    required this.label,
    required this.color,
  });

  final Key badgeKey;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(key: badgeKey, label: label, color: color);
  }
}

class _HeaderBackgroundArt extends StatelessWidget {
  const _HeaderBackgroundArt({
    required this.coverProvider,
    required this.decodeWidth,
    required this.deferred,
    required this.platform,
  });

  final ImageProvider<Object>? coverProvider;
  final int decodeWidth;
  final bool deferred;
  final Platform platform;

  @override
  Widget build(BuildContext context) {
    if (coverProvider == null) {
      return DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.panelGradient),
        child: Center(
          child: Icon(
            platformIcon(platform),
            size: 38,
            color: AppColors.desertSand.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    final quality = deferred ? FilterQuality.none : FilterQuality.low;
    final image = _CachedResizeImage(
      provider: coverProvider!,
      decodeWidth: decodeWidth,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: quality,
      errorBuilder: _HeaderFallback(platform: platform),
    );
    if (deferred) {
      return image;
    }
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: image,
    );
  }
}

class GameDetailsCover extends StatelessWidget {
  const GameDetailsCover({
    required this.platform,
    required this.coverProvider,
    required this.decodeWidth,
    required this.deferred,
    super.key,
  });

  final Platform platform;
  final ImageProvider<Object>? coverProvider;
  final int decodeWidth;
  final bool deferred;

  @override
  Widget build(BuildContext context) {
    final quality = deferred ? FilterQuality.none : FilterQuality.low;
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: AppConstants.coverAspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: AppColors.surfaceElevated,
            child: coverProvider == null
                ? _CoverFallback(platform: platform)
                : _CachedResizeImage(
                    provider: coverProvider!,
                    decodeWidth: decodeWidth,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    alignment: Alignment.center,
                    filterQuality: quality,
                    isAntiAlias: true,
                    errorBuilder: _CoverFallback(platform: platform),
                  ),
          ),
        ),
      ),
    );
  }
}

class _HeaderFallback extends StatelessWidget {
  const _HeaderFallback({required this.platform});

  final Platform platform;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.panelGradient),
      child: Center(
        child: Icon(
          platformIcon(platform),
          size: 38,
          color: AppColors.desertSand.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.platform});

  final Platform platform;

  @override
  Widget build(BuildContext context) {
    final icon = platformIcon(platform);
    return ColoredBox(
      color: AppColors.surfaceVariant,
      child: Center(child: Icon(icon, size: 48, color: AppColors.desertSand)),
    );
  }
}

class _CachedResizeImage extends StatefulWidget {
  const _CachedResizeImage({
    required this.provider,
    required this.decodeWidth,
    required this.fit,
    required this.alignment,
    required this.filterQuality,
    required this.errorBuilder,
    this.width,
    this.height,
    this.isAntiAlias = false,
  });

  final ImageProvider<Object> provider;
  final int decodeWidth;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final bool isAntiAlias;
  final Widget errorBuilder;

  @override
  State<_CachedResizeImage> createState() => _CachedResizeImageState();
}

class _CachedResizeImageState extends State<_CachedResizeImage> {
  late ImageProvider<Object> _resizedProvider = ResizeImage(
    widget.provider,
    width: widget.decodeWidth,
  );

  @override
  void didUpdateWidget(covariant _CachedResizeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider ||
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
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      alignment: widget.alignment,
      filterQuality: widget.filterQuality,
      isAntiAlias: widget.isAntiAlias,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => widget.errorBuilder,
    );
  }
}
