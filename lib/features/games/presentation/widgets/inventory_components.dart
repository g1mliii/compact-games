import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../models/game_info.dart';

enum InventorySortField { name, originalSize, savingsPercent, platform }

class InventoryToolbar extends StatelessWidget {
  const InventoryToolbar({
    super.key,
    required this.searchController,
    required this.sortField,
    required this.descending,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onToggleSortDirection,
  });

  final TextEditingController searchController;
  final InventorySortField sortField;
  final bool descending;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<InventorySortField> onSortChanged;
  final VoidCallback onToggleSortDirection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final searchField = TextField(
          controller: searchController,
          decoration: const InputDecoration(
            hintText: 'Search inventory...',
            prefixIcon: Icon(LucideIcons.search),
          ),
          onChanged: onSearchChanged,
        );
        final sortFieldWidget = _SortFieldButton(
          sortField: sortField,
          onSortChanged: onSortChanged,
        );
        final directionButton = IconButton(
          tooltip: descending ? 'Descending' : 'Ascending',
          onPressed: onToggleSortDirection,
          icon: Icon(
            descending
                ? LucideIcons.arrowDownWideNarrow
                : LucideIcons.arrowUpNarrowWide,
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: sortFieldWidget),
                  const SizedBox(width: 4),
                  directionButton,
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            SizedBox(width: 320, child: searchField),
            const SizedBox(width: 8),
            SizedBox(width: 210, child: sortFieldWidget),
            const SizedBox(width: 8),
            directionButton,
          ],
        );
      },
    );
  }
}

class _SortFieldButton extends StatelessWidget {
  const _SortFieldButton({
    required this.sortField,
    required this.onSortChanged,
  });

  final InventorySortField sortField;
  final ValueChanged<InventorySortField> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<InventorySortField>(
      tooltip: 'Sort by',
      popUpAnimationStyle: AnimationStyle.noAnimation,
      onSelected: onSortChanged,
      itemBuilder: (context) => const <PopupMenuEntry<InventorySortField>>[
        PopupMenuItem(
          value: InventorySortField.savingsPercent,
          child: Text('Savings %'),
        ),
        PopupMenuItem(
          value: InventorySortField.originalSize,
          child: Text('Original size'),
        ),
        PopupMenuItem(value: InventorySortField.name, child: Text('Name')),
        PopupMenuItem(
          value: InventorySortField.platform,
          child: Text('Platform'),
        ),
      ],
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Sort by', isDense: true),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _sortFieldLabel(sortField),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(LucideIcons.chevronDown, size: 16),
          ],
        ),
      ),
    );
  }

  String _sortFieldLabel(InventorySortField field) {
    return switch (field) {
      InventorySortField.savingsPercent => 'Savings %',
      InventorySortField.originalSize => 'Original size',
      InventorySortField.name => 'Name',
      InventorySortField.platform => 'Platform',
    };
  }
}

class InventoryStatusRow extends StatelessWidget {
  const InventoryStatusRow({
    super.key,
    required this.algorithmLabel,
    required this.watcherActive,
    required this.advancedEnabled,
    required this.onAdvancedChanged,
  });

  final String algorithmLabel;
  final bool watcherActive;
  final bool advancedEnabled;
  final ValueChanged<bool> onAdvancedChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        Chip(label: Text('Algorithm: $algorithmLabel')),
        Chip(
          label: Text(watcherActive ? 'Watcher: active' : 'Watcher: paused'),
          backgroundColor: watcherActive
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.warning.withValues(alpha: 0.2),
        ),
        FilterChip(
          label: const Text('Advanced metadata scans (manual)'),
          selected: advancedEnabled,
          onSelected: onAdvancedChanged,
        ),
      ],
    );
  }
}

class InventoryHeader extends StatelessWidget {
  const InventoryHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: [
          Expanded(flex: 28, child: Text('Game', style: AppTypography.label)),
          Expanded(
            flex: 12,
            child: Text('Platform', style: AppTypography.label),
          ),
          Expanded(
            flex: 12,
            child: Text('Original', style: AppTypography.label),
          ),
          Expanded(
            flex: 12,
            child: Text('Current', style: AppTypography.label),
          ),
          Expanded(
            flex: 10,
            child: Text('Savings', style: AppTypography.label),
          ),
          Expanded(
            flex: 14,
            child: Text('Last Checked', style: AppTypography.label),
          ),
          Expanded(
            flex: 12,
            child: Text('Watcher', style: AppTypography.label),
          ),
        ],
      ),
    );
  }
}

class InventoryRow extends StatelessWidget {
  const InventoryRow({
    super.key,
    required this.game,
    required this.watcherActive,
    required this.lastChecked,
    required this.onOpenDetails,
  });

  final GameInfo game;
  final bool watcherActive;
  final DateTime? lastChecked;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final originalGb = game.sizeBytes / (1024 * 1024 * 1024);
    final currentGb =
        (game.compressedSize ?? game.sizeBytes) / (1024 * 1024 * 1024);
    final savingsPercent = (game.savingsRatio * 100).toStringAsFixed(1);
    final checkedLabel = lastChecked == null
        ? 'N/A'
        : '${lastChecked!.hour.toString().padLeft(2, '0')}:${lastChecked!.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onOpenDetails,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Expanded(
              flex: 28,
              child: Text(
                game.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium,
              ),
            ),
            Expanded(
              flex: 12,
              child: Text(
                game.platform.displayName,
                style: AppTypography.bodySmall,
              ),
            ),
            Expanded(
              flex: 12,
              child: Text(
                '${originalGb.toStringAsFixed(1)} GB',
                style: AppTypography.bodySmall,
              ),
            ),
            Expanded(
              flex: 12,
              child: Text(
                '${currentGb.toStringAsFixed(1)} GB',
                style: AppTypography.bodySmall,
              ),
            ),
            Expanded(
              flex: 10,
              child: Text('$savingsPercent%', style: AppTypography.bodySmall),
            ),
            Expanded(
              flex: 14,
              child: Text(checkedLabel, style: AppTypography.bodySmall),
            ),
            Expanded(
              flex: 12,
              child: Text(
                watcherActive ? 'Monitored' : 'Paused',
                style: AppTypography.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InventoryError extends StatelessWidget {
  const InventoryError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: AppTypography.bodyMedium),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class InventoryEmpty extends StatelessWidget {
  const InventoryEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('No games match the current inventory filters.'),
    );
  }
}
