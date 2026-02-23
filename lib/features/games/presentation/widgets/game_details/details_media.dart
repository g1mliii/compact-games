import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/platform_icon.dart';
import '../../../../../models/game_info.dart';

const double _headerHeight = 156;

class GameDetailsHeader extends StatelessWidget {
  const GameDetailsHeader({
    required this.gameName,
    required this.platform,
    required this.coverProvider,
    required this.decodeWidth,
    required this.deferred,
    super.key,
  });

  static final _scrimTop = Colors.black.withValues(alpha: 0.2);
  static final _scrimBottom = AppColors.surface.withValues(alpha: 0.78);

  final String gameName;
  final Platform platform;
  final ImageProvider<Object>? coverProvider;
  final int decodeWidth;
  final bool deferred;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: _headerHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _HeaderBackgroundArt(
                coverProvider: coverProvider,
                decodeWidth: decodeWidth,
                deferred: deferred,
                platform: platform,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_scrimTop, _scrimBottom],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
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
                          platform.displayName,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
      return Container(
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
    final image = Image(
      image: ResizeImage(coverProvider!, width: decodeWidth),
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: quality,
      errorBuilder: (context, error, stackTrace) => Container(
        decoration: const BoxDecoration(gradient: AppColors.panelGradient),
      ),
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
                : Image(
                    image: ResizeImage(coverProvider!, width: decodeWidth),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    alignment: Alignment.center,
                    filterQuality: quality,
                    isAntiAlias: true,
                    errorBuilder: (context, error, stackTrace) =>
                        _CoverFallback(platform: platform),
                  ),
          ),
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
    return Container(
      color: AppColors.surfaceVariant,
      child: Center(child: Icon(icon, size: 48, color: AppColors.desertSand)),
    );
  }
}
