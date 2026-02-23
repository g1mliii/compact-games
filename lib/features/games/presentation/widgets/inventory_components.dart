import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../models/game_info.dart';
export 'inventory_status_row.dart';
part 'inventory_sort_menu.dart';

enum InventorySortField { name, originalSize, savingsPercent, platform }

const double _inventoryControlHeight = 40;
const ValueKey<String> _inventorySearchFieldKey = ValueKey<String>(
  'inventorySearchField',
);
const ValueKey<String> _inventorySortFieldKey = ValueKey<String>(
  'inventorySortField',
);
const ValueKey<String> _inventorySortDecoratorKey = ValueKey<String>(
  'inventorySortDecorator',
);
const ValueKey<String> _inventorySortMenuRowKey = ValueKey<String>(
  'inventorySortMenuRow',
);

class InventoryToolbar extends StatefulWidget {
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
  State<InventoryToolbar> createState() => _InventoryToolbarState();
}

class _InventoryToolbarState extends State<InventoryToolbar> {
  static const double _compactBreakpoint = 700;
  bool _compact = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _compactBreakpoint;
        _compact = compact;

        final searchField = SizedBox(
          key: _inventorySearchFieldKey,
          height: _inventoryControlHeight,
          child: TextField(
            controller: widget.searchController,
            decoration: const InputDecoration(
              hintText: 'Search inventory...',
              prefixIcon: Icon(LucideIcons.search),
              isDense: true,
            ),
            onChanged: widget.onSearchChanged,
          ),
        );
        final sortFieldWidget = SizedBox(
          key: _inventorySortFieldKey,
          height: _inventoryControlHeight,
          child: _SortFieldButton(
            sortField: widget.sortField,
            onSortChanged: widget.onSortChanged,
          ),
        );
        final directionButton = IconButton(
          tooltip: widget.descending ? 'Descending' : 'Ascending',
          onPressed: widget.onToggleSortDirection,
          icon: Icon(
            widget.descending
                ? LucideIcons.arrowDownWideNarrow
                : LucideIcons.arrowUpNarrowWide,
          ),
        );

        if (_compact) {
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
            Expanded(flex: 3, child: searchField),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: sortFieldWidget),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openSortMenu(context),
        child: InputDecorator(
          key: _inventorySortDecoratorKey,
          decoration: const InputDecoration(
            labelText: 'Sort by',
            isDense: true,
          ),
          child: SizedBox.expand(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _inventorySortFieldLabel(sortField),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.chevronDown, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSortMenu(BuildContext context) async {
    final menuPosition = _sortMenuPosition(context);
    if (menuPosition == null) {
      return;
    }

    final selected = await showMenu<InventorySortField>(
      context: context,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      position: menuPosition.position,
      constraints: BoxConstraints.tightFor(width: menuPosition.width),
      items: <PopupMenuEntry<InventorySortField>>[
        _HorizontalSortMenuEntry(selected: sortField),
      ],
    );

    if (selected != null && selected != sortField) {
      onSortChanged(selected);
    }
  }

  _SortMenuPosition? _sortMenuPosition(BuildContext context) {
    final buttonBox = context.findRenderObject();
    final overlayState = Overlay.maybeOf(context);
    if (buttonBox is! RenderBox || overlayState == null) {
      return null;
    }

    final overlayBox = overlayState.context.findRenderObject();
    if (overlayBox is! RenderBox || !buttonBox.hasSize) {
      return null;
    }

    final buttonRect =
        buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox) &
        buttonBox.size;
    return _SortMenuPosition(
      width: buttonRect.width,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          buttonRect.left,
          buttonRect.bottom + 4,
          buttonRect.width,
          0,
        ),
        Offset.zero & overlayBox.size,
      ),
    );
  }
}

String _inventorySortFieldLabel(InventorySortField field) {
  return switch (field) {
    InventorySortField.savingsPercent => 'Savings %',
    InventorySortField.originalSize => 'Original size',
    InventorySortField.name => 'Name',
    InventorySortField.platform => 'Platform',
  };
}

class InventoryHeader extends StatelessWidget {
  const InventoryHeader({super.key});

  static final _headerStyle = AppTypography.label.copyWith(
    fontSize: 11,
    letterSpacing: 0.9,
    color: AppColors.textMuted.withValues(alpha: 0.9),
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    final headerStyle = _headerStyle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: [
          Expanded(flex: 28, child: Text('GAME', style: headerStyle)),
          Expanded(flex: 12, child: Text('PLATFORM', style: headerStyle)),
          Expanded(flex: 12, child: Text('ORIGINAL', style: headerStyle)),
          Expanded(flex: 12, child: Text('CURRENT', style: headerStyle)),
          Expanded(flex: 10, child: Text('SAVINGS', style: headerStyle)),
          Expanded(flex: 14, child: Text('LAST CHECKED', style: headerStyle)),
          Expanded(flex: 12, child: Text('WATCHER', style: headerStyle)),
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
    required this.lastCheckedLabel,
    required this.onOpenDetails,
    this.isStriped = false,
  });

  final GameInfo game;
  final bool watcherActive;
  final String lastCheckedLabel;
  final VoidCallback onOpenDetails;
  final bool isStriped;

  static final _stripedDecoration = BoxDecoration(
    color: AppColors.surfaceVariant.withValues(alpha: 0.16),
    border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
  );
  static final _normalDecoration = BoxDecoration(
    color: Colors.transparent,
    border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
  );

  @override
  Widget build(BuildContext context) {
    final originalGb = game.sizeBytes / (1024 * 1024 * 1024);
    final currentGb =
        (game.compressedSize ?? game.sizeBytes) / (1024 * 1024 * 1024);
    final savingsPercent = (game.savingsRatio * 100).toStringAsFixed(1);

    return InkWell(
      onTap: onOpenDetails,
      child: Container(
        decoration: isStriped ? _stripedDecoration : _normalDecoration,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
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
                child: Text(lastCheckedLabel, style: AppTypography.bodySmall),
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
      child: Text(
        'No games match the current inventory filters.',
        style: AppTypography.bodyMedium,
      ),
    );
  }
}
