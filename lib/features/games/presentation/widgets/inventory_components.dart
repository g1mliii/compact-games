import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pressplay/l10n/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/localization/presentation_labels.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../models/game_info.dart';
import '../../../../providers/games/game_list_provider.dart';
import '../../../../providers/localization/locale_provider.dart';
import '../../../../providers/games/single_game_provider.dart';
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
const ValueKey<String> _inventorySortDirectionButtonKey = ValueKey<String>(
  'inventorySortDirectionButton',
);
const ValueKey<String> inventoryListBoundaryKey = ValueKey<String>(
  'inventoryListBoundary',
);
const EdgeInsets _inventorySavingsCellPadding = EdgeInsets.only(
  left: 6,
  right: 14,
);
const EdgeInsets _inventoryLastCheckedCellPadding = EdgeInsets.only(
  left: 14,
  right: 10,
);
const EdgeInsets _inventoryWatcherCellPadding = EdgeInsets.only(left: 10);

final inventoryLastCheckedLabelProvider = Provider<String>((ref) {
  final l10n = ref.watch(appLocalizationsProvider);
  final lastChecked = ref.watch(
    gameListProvider.select((state) => state.valueOrNull?.lastRefreshed),
  );
  if (lastChecked == null) {
    return l10n.commonNotAvailable;
  }

  final hour = lastChecked.hour.toString().padLeft(2, '0');
  final minute = lastChecked.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
});

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
  static const double _compactBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _compactBreakpoint;

          final searchField = SizedBox(
            key: _inventorySearchFieldKey,
            height: _inventoryControlHeight,
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: l10n.inventorySearchHint,
                prefixIcon: Icon(LucideIcons.search),
                isDense: true,
              ),
              onChanged: onSearchChanged,
            ),
          );
          final sortFieldWidget = SizedBox(
            key: _inventorySortFieldKey,
            height: _inventoryControlHeight,
            child: _SortFieldButton(
              sortField: sortField,
              onSortChanged: onSortChanged,
            ),
          );
          final directionButton = SizedBox(
            key: _inventorySortDirectionButtonKey,
            width: _inventoryControlHeight,
            height: _inventoryControlHeight,
            child: IconButton(
              tooltip: descending
                  ? l10n.inventorySortDirectionDescending
                  : l10n.inventorySortDirectionAscending,
              onPressed: onToggleSortDirection,
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints.expand(),
              icon: Icon(
                descending
                    ? LucideIcons.arrowDownWideNarrow
                    : LucideIcons.arrowUpNarrowWide,
                size: 18,
              ),
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
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
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(flex: 3, child: searchField),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: sortFieldWidget),
              const SizedBox(width: 8),
              directionButton,
            ],
          );
        },
      ),
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
    final l10n = context.l10n;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openSortMenu(context),
        mouseCursor: SystemMouseCursors.click,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        overlayColor: appInteractionOverlay,
        child: InputDecorator(
          key: _inventorySortDecoratorKey,
          decoration: InputDecoration(
            labelText: l10n.inventorySortLabel,
            isDense: true,
          ),
          child: SizedBox.expand(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _inventorySortFieldLabel(l10n, sortField),
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
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      menuPadding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
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
          buttonRect.bottom,
          buttonRect.width,
          0,
        ),
        Offset.zero & overlayBox.size,
      ),
    );
  }
}

String _inventorySortFieldLabel(
  AppLocalizations l10n,
  InventorySortField field,
) {
  return switch (field) {
    InventorySortField.savingsPercent => l10n.inventorySortSavingsPercent,
    InventorySortField.originalSize => l10n.inventorySortOriginalSize,
    InventorySortField.name => l10n.inventorySortName,
    InventorySortField.platform => l10n.inventorySortPlatform,
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
    final l10n = context.l10n;
    final headerStyle = _headerStyle;
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Row(
          children: [
            Expanded(
              flex: 28,
              child: _InventoryTableCell(
                padding: const EdgeInsets.only(right: 8),
                child: Text(l10n.inventoryHeaderGame, style: headerStyle),
              ),
            ),
            Expanded(
              flex: 12,
              child: _InventoryTableCell(
                child: Text(l10n.inventoryHeaderPlatform, style: headerStyle),
              ),
            ),
            Expanded(
              flex: 12,
              child: _InventoryTableCell(
                child: Text(
                  l10n.inventoryHeaderOriginal,
                  style: headerStyle,
                  textAlign: TextAlign.right,
                ),
              ),
            ),
            Expanded(
              flex: 12,
              child: _InventoryTableCell(
                child: Text(
                  l10n.inventoryHeaderCurrent,
                  style: headerStyle,
                  textAlign: TextAlign.right,
                ),
              ),
            ),
            Expanded(
              flex: 10,
              child: _InventoryTableCell(
                padding: _inventorySavingsCellPadding,
                child: Text(
                  l10n.inventoryHeaderSavings,
                  style: headerStyle,
                  textAlign: TextAlign.right,
                ),
              ),
            ),
            Expanded(
              flex: 14,
              child: _InventoryTableCell(
                padding: _inventoryLastCheckedCellPadding,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    l10n.inventoryHeaderLastChecked,
                    style: headerStyle,
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 12,
              child: _InventoryTableCell(
                padding: _inventoryWatcherCellPadding,
                child: Text(l10n.inventoryHeaderWatcher, style: headerStyle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InventoryGameRow extends ConsumerWidget {
  const InventoryGameRow({
    required this.gamePath,
    required this.excludedPathKeys,
    required this.watcherActive,
    required this.lastCheckedLabel,
    this.isStriped = false,
    super.key,
  });

  final String gamePath;
  final Set<String> excludedPathKeys;
  final bool watcherActive;
  final String lastCheckedLabel;
  final bool isStriped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final gameData = ref.watch(
      singleGameProvider(gamePath).select(
        (g) => g == null
            ? null
            : (
                name: g.name,
                platform: g.platform,
                sizeBytes: g.sizeBytes,
                compressedSize: g.compressedSize,
                isCompressed: g.isCompressed,
                savingsRatio: g.savingsRatio,
                normalizedPath: g.normalizedPath,
                isDirectStorage: g.isDirectStorage,
                isUnsupported: g.isUnsupported,
                path: g.path,
              ),
      ),
    );
    if (gameData == null) {
      return const SizedBox.shrink();
    }

    final isExcluded = excludedPathKeys.contains(gameData.normalizedPath);
    final watcherLabel = !gameData.isCompressed || isExcluded
        ? l10n.inventoryWatcherNotWatched
        : watcherActive
        ? l10n.inventoryWatcherWatched
        : l10n.inventoryWatcherPaused;

    // Reconstruct a minimal GameInfo-like value object for InventoryRow by
    // reading the full record imperatively — avoids an extra watch.
    final game = ref.read(singleGameProvider(gamePath));
    if (game == null) return const SizedBox.shrink();

    return InventoryRow(
      game: game,
      watcherLabel: watcherLabel,
      lastCheckedLabel: lastCheckedLabel,
      isStriped: isStriped,
      onOpenDetails: () =>
          Navigator.of(context).pushNamed(AppRoutes.gameDetails(gameData.path)),
    );
  }
}

class InventoryRow extends StatelessWidget {
  const InventoryRow({
    super.key,
    required this.game,
    required this.watcherLabel,
    required this.lastCheckedLabel,
    required this.onOpenDetails,
    this.isStriped = false,
  });

  final GameInfo game;
  final String watcherLabel;
  final String lastCheckedLabel;
  final VoidCallback onOpenDetails;
  final bool isStriped;

  static final _stripedColor = AppColors.surfaceVariant.withValues(alpha: 0.28);
  static const _bottomBorder = Border(
    bottom: BorderSide(color: AppColors.borderSubtle),
  );
  static final TextStyle _numericTextStyle = AppTypography.bodySmall.copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final game = this.game;
    final originalGb = game.sizeBytes / (1024 * 1024 * 1024);
    final currentGb =
        (game.compressedSize ?? game.sizeBytes) / (1024 * 1024 * 1024);
    final savingsValue = game.savingsRatio * 100;
    final savingsPercent = savingsValue.toStringAsFixed(1);

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      child: Row(
        children: [
          Expanded(
            flex: 28,
            child: _InventoryTableCell(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                game.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium,
              ),
            ),
          ),
          Expanded(
            flex: 12,
            child: _InventoryTableCell(
              child: Text(
                game.platform.localizedLabel(l10n),
                style: AppTypography.bodySmall,
              ),
            ),
          ),
          Expanded(
            flex: 12,
            child: _InventoryTableCell(
              child: _NumericCell(
                text: l10n.commonGigabytes(originalGb.toStringAsFixed(1)),
              ),
            ),
          ),
          Expanded(
            flex: 12,
            child: _InventoryTableCell(
              child: _NumericCell(
                text: l10n.commonGigabytes(currentGb.toStringAsFixed(1)),
              ),
            ),
          ),
          Expanded(
            flex: 10,
            child: _InventoryTableCell(
              padding: _inventorySavingsCellPadding,
              child: _NumericCell(
                text: '$savingsPercent%',
                style: _savingsTextStyle(savingsValue),
              ),
            ),
          ),
          Expanded(
            flex: 14,
            child: _InventoryTableCell(
              padding: _inventoryLastCheckedCellPadding,
              child: _NumericCell(text: lastCheckedLabel),
            ),
          ),
          Expanded(
            flex: 12,
            child: _InventoryTableCell(
              padding: _inventoryWatcherCellPadding,
              child: Text(watcherLabel, style: AppTypography.bodySmall),
            ),
          ),
        ],
      ),
    );

    final bgColor = isStriped ? _stripedColor : Colors.transparent;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(color: bgColor, border: _bottomBorder),
        child: InkWell(
          onTap: onOpenDetails,
          mouseCursor: SystemMouseCursors.click,
          overlayColor: appInteractionOverlay,
          hoverColor: AppColors.hoverSurface,
          focusColor: AppColors.hoverSurface,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          child: content,
        ),
      ),
    );
  }
}

class _NumericCell extends StatelessWidget {
  const _NumericCell({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: style ?? InventoryRow._numericTextStyle,
    );
  }
}

class _InventoryTableCell extends StatelessWidget {
  const _InventoryTableCell({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 6),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: padding, child: child);
  }
}

// Pre-computed savings text style variants — avoids TextStyle.copyWith on
// every row build. The three cases map to: zero/negative, moderate, notable.
final _savingsStyleNone = InventoryRow._numericTextStyle.copyWith(
  color: AppColors.textMuted,
  fontWeight: FontWeight.w500,
);
final _savingsStyleModerate = InventoryRow._numericTextStyle.copyWith(
  color: AppColors.textPrimary,
  fontWeight: FontWeight.w500,
);
final _savingsStyleNotable = InventoryRow._numericTextStyle.copyWith(
  color: AppColors.richGold,
  fontWeight: FontWeight.w700,
);

TextStyle _savingsTextStyle(double savingsPercent) {
  return switch (savingsPercent) {
    <= 0 => _savingsStyleNone,
    > 10 => _savingsStyleNotable,
    _ => _savingsStyleModerate,
  };
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
          TextButton(onPressed: onRetry, child: Text(context.l10n.commonRetry)),
        ],
      ),
    );
  }
}

class InventoryEmpty extends StatelessWidget {
  const InventoryEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(context.l10n.inventoryEmpty, style: AppTypography.bodyMedium),
    );
  }
}
