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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalSavings = ref.watch(totalSavingsProvider);
    final savedGB = totalSavings.savedBytes / (1024 * 1024 * 1024);

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              const Text('PressPlay', style: AppTypography.headingMedium),
              const SizedBox(width: 16),
              if (totalSavings.savedBytes > 0)
                Text(
                  '${savedGB.toStringAsFixed(1)} GB saved',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const Spacer(),
              const _SearchField(),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                color: AppColors.textSecondary,
                onPressed: () => ref.read(gameListProvider.notifier).refresh(),
                tooltip: 'Refresh games',
              ),
            ],
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
  static const Duration _searchDebounce = Duration(milliseconds: 180);
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
      width: 220,
      height: 36,
      child: TextField(
        controller: _controller,
        style: AppTypography.bodySmall,
        decoration: InputDecoration(
          hintText: 'Search games...',
          hintStyle: AppTypography.bodySmall.copyWith(
            color: AppColors.textMuted,
          ),
          prefixIcon: const Icon(
            LucideIcons.search,
            size: 16,
            color: AppColors.textMuted,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 36,
          ),
          filled: true,
          fillColor: AppColors.surfaceElevated,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.accent),
          ),
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
