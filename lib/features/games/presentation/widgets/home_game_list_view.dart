import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:compact_games/l10n/app_localizations.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/localization/presentation_labels.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/platform_chip.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../providers/games/filtered_games_provider.dart';
import '../../../../providers/games/selected_game_provider.dart';
import '../../../../providers/games/single_game_provider.dart';
import '../widgets/game_details/game_details_body.dart';
import '../widgets/library_home/library_home_surface.dart';

/// Split view: vertical game list on the left, details panel on the right.
///
/// Caches layout mode so continuous window resize only rebuilds the subtree
/// when the stacked/side-by-side breakpoint actually crosses or the bucketed
/// panel height changes.
class HomeGameListView extends StatefulWidget {
  const HomeGameListView({super.key});

  static const double _listPanelWidth = 320;
  static const double _stackedBreakpoint = 560;
  static const double _heightBucket = 20.0;
  static const double _contentTopInset = 8.0;

  @override
  State<HomeGameListView> createState() => _HomeGameListViewState();
}

class _HomeGameListViewState extends State<HomeGameListView> {
  bool? _stacked;
  double _bucketedHeight = 240.0;

  static const Widget _sideBySide = Row(
    children: [
      SizedBox(
        width: HomeGameListView._listPanelWidth,
        child: RepaintBoundary(child: _GameListPanel()),
      ),
      VerticalDivider(width: 1, color: AppColors.borderSubtle),
      Expanded(child: RepaintBoundary(child: _DetailPanel())),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < HomeGameListView._stackedBreakpoint;

        if (stacked) {
          final bucketed = bucketHomeGameListPanelHeight(constraints.maxHeight);

          if (stacked == _stacked && bucketed == _bucketedHeight) {
            return _buildStacked();
          }
          _stacked = stacked;
          _bucketedHeight = bucketed;
          return _buildStacked();
        }

        if (stacked == _stacked) return _buildSideBySide();
        _stacked = stacked;
        return _buildSideBySide();
      },
    );
  }

  Widget _buildSideBySide() {
    return const Padding(
      padding: EdgeInsets.only(top: HomeGameListView._contentTopInset),
      child: _sideBySide,
    );
  }

  Widget _buildStacked() {
    return Padding(
      padding: const EdgeInsets.only(top: HomeGameListView._contentTopInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _bucketedHeight,
            child: const RepaintBoundary(child: _GameListPanel()),
          ),
          const Divider(height: 1, color: AppColors.borderSubtle),
          const Expanded(child: RepaintBoundary(child: _DetailPanel())),
        ],
      ),
    );
  }
}

@visibleForTesting
double bucketHomeGameListPanelHeight(double maxHeight) {
  final raw = maxHeight.isFinite
      ? (maxHeight * 0.34).clamp(90.0, 280.0)
      : 240.0;
  return ((raw / HomeGameListView._heightBucket).floor() *
          HomeGameListView._heightBucket)
      .clamp(90.0, 280.0)
      .toDouble();
}

/// Identifies the scrollable game list, so callers (and tests) can tell a row
/// apart from the same game surfaced elsewhere in the split view.
const Key homeGameListPanelListKey = ValueKey<String>('homeGameListPanelList');

/// Moves the list selection by [delta] rows.
class _MoveListSelectionIntent extends Intent {
  const _MoveListSelectionIntent(this.delta);

  final int delta;
}

class _GameListPanel extends ConsumerStatefulWidget {
  const _GameListPanel();

  @override
  ConsumerState<_GameListPanel> createState() => _GameListPanelState();
}

class _GameListPanelState extends ConsumerState<_GameListPanel> {
  // Focus traversal cannot drive this list: `ListView.builder` only builds the
  // rows near the viewport, so a Next/PreviousFocusIntent wraps back to the
  // top once it runs out of built rows. Move the selection by index instead
  // and scroll it into view ourselves.
  static const _navigationShortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.arrowUp): _MoveListSelectionIntent(-1),
    SingleActivator(LogicalKeyboardKey.arrowDown): _MoveListSelectionIntent(1),
  };

  final ScrollController _scrollController = ScrollController();

  /// One focus node for the whole list rather than one per row: rows are built
  /// lazily, so per-row focus can only ever cover the visible window.
  final FocusNode _listFocusNode = FocusNode(debugLabel: 'GameListPanel');

  @override
  void dispose() {
    _scrollController.dispose();
    _listFocusNode.dispose();
    super.dispose();
  }

  /// Selects [gamePath], or Library Home when it is null.
  ///
  /// Library Home is not a separate selection state: it *is* the null
  /// selection, so nothing downstream has to learn about a second mode.
  void _selectRow(String? gamePath) {
    _listFocusNode.requestFocus();
    ref.read(selectedGameProvider.notifier).state = gamePath;
  }

  /// Moves the selection over [rows], the list the view actually renders.
  ///
  /// Working in row space rather than reconstructing a `+1` offset means
  /// `indexOf` reports `-1` for a selection the filters have hidden, which
  /// clamps onto Library Home from either direction with no special case, and
  /// the index handed to [_revealRow] is the ListView's own index by
  /// construction rather than by coincidence.
  void _moveSelection(int delta, List<String?> rows) {
    final selected = ref.read(selectedGameProvider);
    final nextIndex = (rows.indexOf(selected) + delta).clamp(
      0,
      rows.length - 1,
    );
    final next = rows[nextIndex];
    if (next == selected) return;

    ref.read(selectedGameProvider.notifier).state = next;
    _revealRow(nextIndex);
  }

  void _revealRow(int index) {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final rowTop = index * _rowExtent;
    final rowBottom = rowTop + _rowExtent;
    final viewportTop = position.pixels;
    final viewportBottom = viewportTop + position.viewportDimension;

    final double target;
    if (rowTop < viewportTop) {
      target = rowTop;
    } else if (rowBottom > viewportBottom) {
      target = rowBottom - position.viewportDimension;
    } else {
      return;
    }
    _scrollController.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gamePaths = ref.watch(filteredGamePathsProvider);
    final l10n = context.l10n;

    if (gamePaths.isEmpty) {
      // Library Home stays reachable even when the filters hide every game, so
      // the pane is never a dead end.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _rowExtent,
            child: _LibraryHomeRow(onSelect: () => _selectRow(null)),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.searchX,
                      size: 22,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.homeListEmptyTitle,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.homeListEmptyMessage,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // The rendered rows, with Library Home as the null entry at the top. One
    // list drives the builder, the keyboard navigation, and the scroll math, so
    // adding a row kind later cannot leave the three disagreeing.
    final rows = <String?>[null, ...gamePaths];

    return Shortcuts(
      shortcuts: _navigationShortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          _MoveListSelectionIntent: CallbackAction<_MoveListSelectionIntent>(
            onInvoke: (intent) {
              _moveSelection(intent.delta, rows);
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _listFocusNode,
          child: ListView.builder(
            key: homeGameListPanelListKey,
            controller: _scrollController,
            // Every row shares one extent, which is what lets `_revealRow`
            // compute a scroll offset as `index * _rowExtent`.
            itemCount: rows.length,
            itemExtent: _rowExtent,
            addRepaintBoundaries: true,
            addAutomaticKeepAlives: false,
            itemBuilder: (context, index) {
              final gamePath = rows[index];
              if (gamePath == null) {
                return _LibraryHomeRow(onSelect: () => _selectRow(null));
              }
              return _GameListRow(
                key: ValueKey(gamePath),
                gamePath: gamePath,
                onSelect: _selectRow,
              );
            },
          ),
        ),
      ),
    );
  }
}

const double _rowExtent = 72;

// Shared by both row kinds so the Library Home entry is visually identical to a
// game row when selected.
final _selectedRowDecoration = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      AppColors.selectionSurface.withValues(alpha: 0.9),
      AppColors.focusFill.withValues(alpha: 0.14),
    ],
  ),
  border: Border(
    left: BorderSide(color: AppColors.richGold, width: 3),
    top: BorderSide(color: AppColors.selectionBorder),
    bottom: BorderSide(color: AppColors.selectionBorder),
  ),
);
const _defaultRowDecoration = BoxDecoration(
  border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
);
final _selectedRowTextStyle = AppTypography.bodySmall.copyWith(
  color: AppColors.textPrimary,
  fontWeight: FontWeight.w600,
);
final _defaultRowTextStyle = AppTypography.bodySmall.copyWith(
  color: AppColors.textSecondary,
  fontWeight: FontWeight.w400,
);
final _subtitleSelectedStyle = AppTypography.label.copyWith(
  color: AppColors.textPrimary.withValues(alpha: 0.82),
  fontWeight: FontWeight.w600,
);
final _subtitleDefaultStyle = AppTypography.label.copyWith(
  color: AppColors.textMuted,
  fontWeight: FontWeight.w600,
);

/// Wraps row content in the shared selectable chrome.
Widget _buildSelectableRow({
  required bool isSelected,
  required VoidCallback onTap,
  required Widget child,
}) {
  return Material(
    color: Colors.transparent,
    child: Ink(
      decoration: isSelected ? _selectedRowDecoration : _defaultRowDecoration,
      child: InkWell(
        onTap: onTap,
        // Keyboard navigation is owned by the panel's single focus node, so
        // rows stay out of the traversal order.
        canRequestFocus: false,
        mouseCursor: SystemMouseCursors.click,
        overlayColor: appInteractionOverlay,
        hoverColor: isSelected ? Colors.transparent : AppColors.hoverSurface,
        focusColor: AppColors.hoverSurface,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        child: child,
      ),
    ),
  );
}

/// The persistent first row. Selecting it clears the game selection, which is
/// what makes the details pane show [LibraryHomeSurface].
class _LibraryHomeRow extends ConsumerWidget {
  const _LibraryHomeRow({required this.onSelect});

  /// Library Home is the null selection, so this row has no argument to pass.
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isSelected = ref.watch(
      selectedGameProvider.select((selected) => selected == null),
    );

    return _buildSelectableRow(
      isSelected: isSelected,
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(
              LucideIcons.libraryBig,
              size: 18,
              color: isSelected ? AppColors.richGold : AppColors.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.libraryHomeRowTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: isSelected
                        ? _selectedRowTextStyle
                        : _defaultRowTextStyle,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.libraryHomeRowSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: isSelected
                        ? _subtitleSelectedStyle
                        : _subtitleDefaultStyle,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameListRow extends ConsumerWidget {
  const _GameListRow({
    required this.gamePath,
    required this.onSelect,
    super.key,
  });

  final String gamePath;
  final ValueChanged<String> onSelect;

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
                isCompressed: g.isCompressed,
                isDirectStorage: g.isDirectStorage,
                isUnsupported: g.isUnsupported,
              ),
      ),
    );
    if (gameData == null) return const SizedBox.shrink();

    final isSelected = ref.watch(
      selectedGameProvider.select((selected) => selected == gamePath),
    );

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PlatformChip(platform: gameData.platform, size: PlatformChipSize.sm),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gameData.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isSelected
                      ? _selectedRowTextStyle
                      : _defaultRowTextStyle,
                ),
                const SizedBox(height: 3),
                Text(
                  gameData.platform.localizedLabel(l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isSelected
                      ? _subtitleSelectedStyle
                      : _subtitleDefaultStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _StatusPill(
                  isCompressed: gameData.isCompressed,
                  isDirectStorage: gameData.isDirectStorage,
                  isUnsupported: gameData.isUnsupported,
                  l10n: l10n,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return _buildSelectableRow(
      isSelected: isSelected,
      onTap: () => onSelect(gamePath),
      child: content,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.isCompressed,
    required this.isDirectStorage,
    required this.isUnsupported,
    required this.l10n,
  });

  final bool isCompressed;
  final bool isDirectStorage;
  final bool isUnsupported;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData? icon, String label) = switch ((
      isCompressed,
      isDirectStorage,
      isUnsupported,
    )) {
      (_, true, _) => (
        AppColors.directStorage,
        LucideIcons.alertTriangle,
        l10n.gameStatusDirectStorage,
      ),
      (_, _, true) => (
        AppColors.warning,
        LucideIcons.ban,
        l10n.gameStatusUnsupported,
      ),
      (true, _, _) => (
        AppColors.compressed,
        LucideIcons.checkCircle2,
        l10n.gameDetailsStatusCompressed,
      ),
      _ => (AppColors.info, null, l10n.homeStatusReadyToCompress),
    };

    return StatusBadge(
      color: color,
      icon: icon,
      label: label,
      variant: StatusBadgeVariant.outlined,
      toneAlpha: 0.85,
    );
  }
}

class _DetailPanel extends ConsumerWidget {
  const _DetailPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPath = ref.watch(selectedGameProvider);

    // No game selected means the Library Home row is the active row.
    if (selectedPath == null) {
      return const LibraryHomeSurface();
    }

    return GameDetailsBody(
      key: ValueKey(selectedPath),
      gamePath: selectedPath,
      // The list on the left already shows a status pill per game, so
      // suppress the cover overlay to avoid showing the same chip twice.
      hideCoverStatusOverlay: true,
      expandToAvailableHeight: true,
    );
  }
}
