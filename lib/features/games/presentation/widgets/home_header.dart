import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../providers/games/filtered_games_provider.dart';
import '../../../../providers/games/game_list_provider.dart';

class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  static const BorderRadius _panelRadius = BorderRadius.all(
    Radius.circular(16),
  );
  static const double _compactHeaderBreakpoint = 720;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalSavings = ref.watch(totalSavingsProvider);
    final savedGB = totalSavings.savedBytes / (1024 * 1024 * 1024);
    final savedBadgeWidgets = totalSavings.savedBytes > 0
        ? <Widget>[
            Text(
              '${savedGB.toStringAsFixed(1)} GB saved',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.desertGold,
                fontWeight: FontWeight.w600,
              ),
            ),
          ]
        : const <Widget>[];
    final refreshButton = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: IconButton(
        icon: const Icon(LucideIcons.refreshCw, size: 18),
        color: AppColors.richGold,
        onPressed: () => ref.read(gameListProvider.notifier).refresh(),
        tooltip: 'Refresh games',
      ),
    );

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.panelGradient,
          border: Border.all(color: AppColors.border),
          borderRadius: _panelRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < _compactHeaderBreakpoint;
              final titleBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PressPlay', style: AppTypography.headingMedium),
                  Text(
                    'Cinematic compression control',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: titleBlock),
                        if (savedBadgeWidgets.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          ...savedBadgeWidgets,
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(child: _SearchField()),
                        const SizedBox(width: 8),
                        refreshButton,
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  titleBlock,
                  const SizedBox(width: 18),
                  ...savedBadgeWidgets,
                  const Spacer(),
                  const SizedBox(width: 240, child: _SearchField()),
                  const SizedBox(width: 8),
                  refreshButton,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  static const Duration _searchDebounce = Duration(milliseconds: 300);
  final _controller = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _controller,
        style: AppTypography.bodySmall,
        decoration: InputDecoration(
          hintText: 'Search games...',
          prefixIcon: const Icon(
            LucideIcons.search,
            size: 16,
            color: AppColors.desertSand,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 36,
          ),
          fillColor: AppColors.surfaceElevated.withValues(alpha: 0.8),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_searchDebounce, () {
      if (!mounted) return;
      ref.read(gameListProvider.notifier).setSearchQuery(value);
    });
  }
}
