import 'package:flutter/material.dart';

import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/platform_icon.dart';
import '../../../../../models/game_info.dart';
import '../../../../../services/cover_art_service.dart';

class GameDetailsCover extends StatelessWidget {
  const GameDetailsCover({
    required this.platform,
    required this.coverProvider,
    required this.decodeWidth,
    required this.deferred,
    this.coverArtType,
    this.overlay,
    super.key,
  });

  final Platform platform;
  final ImageProvider<Object>? coverProvider;
  final int decodeWidth;
  final bool deferred;
  final CoverArtType? coverArtType;
  final Widget? overlay;

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
            child: Stack(
              fit: StackFit.expand,
              children: [
                coverProvider == null
                    ? _CoverFallback(platform: platform)
                    : coverArtType == CoverArtType.icon
                    ? _IconCoverLayout(
                        coverProvider: coverProvider!,
                      )
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
                if (overlay != null)
                  Positioned(top: 8, right: 8, child: overlay!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconCoverLayout extends StatelessWidget {
  const _IconCoverLayout({required this.coverProvider});

  final ImageProvider<Object> coverProvider;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.surfaceElevated),
        Center(
          child: SizedBox(
            width: 64,
            height: 64,
            child: Image(
              image: coverProvider,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      ],
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
