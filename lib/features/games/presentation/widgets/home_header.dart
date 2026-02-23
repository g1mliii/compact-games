import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../providers/games/filtered_games_provider.dart';
import '../../../../providers/games/game_list_provider.dart';
import '../../../../providers/games/refresh_games_helper.dart';
import '../../../../providers/system/platform_shell_provider.dart';
part 'home_add_game_dialog.dart';

const ValueKey<String> _addGamePathFieldKey = ValueKey<String>(
  'addGamePathField',
);
const ValueKey<String> _confirmAddGameButtonKey = ValueKey<String>(
  'confirmAddGameButton',
);
const ValueKey<String> _browseGameFolderButtonKey = ValueKey<String>(
  'browseGameFolderButton',
);
const ValueKey<String> _browseGameExeButtonKey = ValueKey<String>(
  'browseGameExeButton',
);

class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  static const BorderRadius _panelRadius = BorderRadius.all(
    Radius.circular(16),
  );
  static const double _compactHeaderBreakpoint = 720;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedBytes = ref.watch(
      totalSavingsProvider.select((s) => s.savedBytes),
    );
    final savedGB = savedBytes / (1024 * 1024 * 1024);
    final savedBadgeWidgets = savedBytes > 0
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
    final refreshButton = _HeaderActionIconButton(
      icon: LucideIcons.refreshCw,
      tooltip: 'Refresh games',
      onPressed: () => unawaited(refreshGamesAndInvalidateCovers(ref)),
    );
    final inventoryButton = _HeaderActionIconButton(
      icon: LucideIcons.list,
      tooltip: 'Compression inventory',
      onPressed: () => Navigator.of(context).pushNamed(AppRoutes.inventory),
    );
    final addGameButton = _HeaderActionIconButton(
      icon: LucideIcons.folderPlus,
      tooltip: 'Add game',
      onPressed: () => unawaited(_promptAddGame(context, ref)),
    );
    final settingsButton = _HeaderActionIconButton(
      icon: LucideIcons.settings,
      tooltip: 'Settings',
      onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
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
          child: _HeaderResponsiveLayout(
            breakpoint: _compactHeaderBreakpoint,
            savedBadgeWidgets: savedBadgeWidgets,
            addGameButton: addGameButton,
            inventoryButton: inventoryButton,
            settingsButton: settingsButton,
            refreshButton: refreshButton,
          ),
        ),
      ),
    );
  }

  Future<void> _promptAddGame(BuildContext context, WidgetRef ref) async {
    final inputValue = await showDialog<String>(
      context: context,
      builder: (_) => const _AddGameDialog(),
    );

    final value = inputValue?.trim() ?? '';
    if (value.isEmpty) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    await _submitManualGame(context, ref, value);
  }

  Future<void> _submitManualGame(
    BuildContext context,
    WidgetRef ref,
    String pathOrExe,
  ) async {
    try {
      final result = await ref
          .read(gameListProvider.notifier)
          .addGameFromPathOrExe(pathOrExe);
      if (!context.mounted) {
        return;
      }

      final message = result.wasAdded
          ? 'Added "${result.game.name}" to your library.'
          : 'Updated "${result.game.name}" in your library.';
      _showHeaderMessage(context, message);
    } on ArgumentError catch (error) {
      if (!context.mounted) {
        return;
      }
      _showHeaderMessage(context, error.message?.toString() ?? 'Invalid path.');
    } on StateError catch (error) {
      if (!context.mounted) {
        return;
      }
      _showHeaderMessage(context, error.message);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showHeaderMessage(context, 'Failed to add game: $error');
    }
  }

  void _showHeaderMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Caches the compact/wide breakpoint so that window resize only rebuilds the
/// subtree when the layout mode actually changes.
class _HeaderResponsiveLayout extends StatefulWidget {
  const _HeaderResponsiveLayout({
    required this.breakpoint,
    required this.savedBadgeWidgets,
    required this.addGameButton,
    required this.inventoryButton,
    required this.settingsButton,
    required this.refreshButton,
  });

  final double breakpoint;
  final List<Widget> savedBadgeWidgets;
  final Widget addGameButton;
  final Widget inventoryButton;
  final Widget settingsButton;
  final Widget refreshButton;

  @override
  State<_HeaderResponsiveLayout> createState() =>
      _HeaderResponsiveLayoutState();
}

class _HeaderResponsiveLayoutState extends State<_HeaderResponsiveLayout> {
  bool _compact = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < widget.breakpoint;
        // Update cached breakpoint synchronously — no setState needed since
        // we use the value in the same builder call.  Between breakpoints the
        // returned subtree is identical, so Flutter reconciliation is a no-op.
        _compact = compact;
        return _compact ? _buildCompact() : _buildWide();
      },
    );
  }

  static const _titleBlock = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('PressPlay', style: AppTypography.headingMedium),
      Text(
        'Cinematic compression control',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodySmall,
      ),
    ],
  );

  Widget _buildCompact() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(child: _titleBlock),
            if (widget.savedBadgeWidgets.isNotEmpty) ...[
              const SizedBox(width: 12),
              ...widget.savedBadgeWidgets,
            ],
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: _SearchField()),
            const SizedBox(width: 8),
            widget.addGameButton,
            const SizedBox(width: 8),
            widget.inventoryButton,
            const SizedBox(width: 8),
            widget.settingsButton,
            const SizedBox(width: 8),
            widget.refreshButton,
          ],
        ),
      ],
    );
  }

  Widget _buildWide() {
    return Row(
      children: [
        _titleBlock,
        const SizedBox(width: 18),
        ...widget.savedBadgeWidgets,
        const Spacer(),
        const SizedBox(width: 240, child: _SearchField()),
        const SizedBox(width: 8),
        widget.addGameButton,
        const SizedBox(width: 8),
        widget.inventoryButton,
        const SizedBox(width: 8),
        widget.settingsButton,
        const SizedBox(width: 8),
        widget.refreshButton,
      ],
    );
  }
}

class _HeaderActionIconButton extends StatelessWidget {
  const _HeaderActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  static final _bgColor = AppColors.surfaceElevated.withValues(alpha: 0.65);
  static const _borderRadius = BorderRadius.all(Radius.circular(10));

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: _borderRadius,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        padding: const EdgeInsets.all(12),
        icon: Icon(icon, size: 18),
        color: AppColors.richGold,
        onPressed: onPressed,
        tooltip: tooltip,
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
          hintStyle: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary.withValues(alpha: 0.9),
          ),
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
