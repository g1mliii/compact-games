import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/localization/app_localization.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../providers/games/library_home_news_provider.dart';
import 'library_home_news_card.dart';
import 'library_home_section_header.dart';

/// Horizontally scrolling "What's new" shelf, the top section of Library Home.
///
/// The provider is auto-disposing, so simply mounting this widget is what
/// scopes news fetching to "Library Home is on screen" — there is no timer and
/// nothing to unsubscribe.
class LibraryHomeNewsShelf extends ConsumerStatefulWidget {
  const LibraryHomeNewsShelf({super.key});

  /// Test seam, matching [LibraryHomeSurface.scrollViewKey]: the shelf collapses
  /// to nothing when empty, so its presence is the only way to assert on it.
  static const Key shelfKey = ValueKey<String>('libraryHomeNewsShelf');

  /// The arrows only exist while the shelf can actually move that way, so
  /// finding them is also how a test asserts on overflow.
  static const Key backArrowKey = ValueKey<String>('libraryHomeNewsScrollBack');
  static const Key forwardArrowKey = ValueKey<String>(
    'libraryHomeNewsScrollForward',
  );

  @override
  ConsumerState<LibraryHomeNewsShelf> createState() =>
      _LibraryHomeNewsShelfState();
}

class _LibraryHomeNewsShelfState extends ConsumerState<LibraryHomeNewsShelf> {
  final ScrollController _controller = ScrollController();

  bool _canScrollBack = false;
  bool _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncArrows);
    // The first layout produces no scroll event, so the forward arrow would
    // not appear until the user found the overflow some other way.
    SchedulerBinding.instance.addPostFrameCallback((_) => _syncArrows());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Shows each arrow only when there is something that way to reach.
  void _syncArrows() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    if (!position.hasContentDimensions) return;

    final back = position.pixels > position.minScrollExtent + _extentEpsilon;
    final forward = position.pixels < position.maxScrollExtent - _extentEpsilon;
    if (back == _canScrollBack && forward == _canScrollForward) return;

    setState(() {
      _canScrollBack = back;
      _canScrollForward = forward;
    });
  }

  /// Metrics change during layout, which is too late in the frame to call
  /// [setState] directly, so a layout-driven sync waits for the frame to end.
  void _syncArrowsAfterLayout() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) => _syncArrows());
      return;
    }
    _syncArrows();
  }

  void _scrollBy(double direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    // A viewport-sized jump would skip whatever card straddles the edge, so
    // move a little less than one screenful.
    final step = (position.viewportDimension * 0.8).clamp(
      _cardWidth,
      double.infinity,
    );
    final target = (position.pixels + direction * step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final news = ref.watch(libraryHomeNewsProvider);
    final state = news.value;

    // While the cache is still loading there is nothing meaningful to show and
    // a spinner would flash for a few milliseconds, so stay collapsed.
    if (state == null || !state.hasItems) {
      return const SizedBox.shrink();
    }

    return Column(
      key: LibraryHomeNewsShelf.shelfKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LibraryHomeSectionHeader(
          title: l10n.libraryHomeNewsHeading,
          staleLabel: l10n.libraryHomeNewsStale,
          isStale: state.isStale,
        ),
        SizedBox(
          height: _cardHeight,
          child: RepaintBoundary(
            child: Stack(
              children: [
                // Metrics also change on resize and when the item count does,
                // neither of which fires the controller's scroll listener.
                NotificationListener<ScrollMetricsNotification>(
                  onNotification: (_) {
                    _syncArrowsAfterLayout();
                    return false;
                  },
                  child: ScrollConfiguration(
                    // Dragging is how a desktop mouse scrolls sideways: the
                    // wheel belongs to the vertical surface this sits in.
                    behavior: ScrollConfiguration.of(context).copyWith(
                      scrollbars: false,
                      overscroll: false,
                      dragDevices: const <PointerDeviceKind>{
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.stylus,
                      },
                    ),
                    child: ListView.builder(
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      itemExtent: _cardWidth,
                      addAutomaticKeepAlives: false,
                      itemCount: state.items.length,
                      itemBuilder: (context, index) {
                        final item = state.items[index];
                        return Row(
                          children: [
                            Expanded(
                              child: LibraryHomeNewsCard(
                                key: ValueKey<String>(item.id),
                                item: item,
                              ),
                            ),
                            // Tiles butt against each other, parted by the same
                            // hairline the list on the left uses.
                            const VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: AppColors.borderSubtle,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                if (_canScrollBack)
                  _ShelfArrow(
                    buttonKey: LibraryHomeNewsShelf.backArrowKey,
                    alignment: Alignment.centerLeft,
                    icon: LucideIcons.chevronLeft,
                    tooltip: l10n.libraryHomeNewsScrollBack,
                    onPressed: () => _scrollBy(-1),
                  ),
                if (_canScrollForward)
                  _ShelfArrow(
                    buttonKey: LibraryHomeNewsShelf.forwardArrowKey,
                    alignment: Alignment.centerRight,
                    icon: LucideIcons.chevronRight,
                    tooltip: l10n.libraryHomeNewsScrollForward,
                    onPressed: () => _scrollBy(1),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, thickness: 1, color: AppColors.borderSubtle),
      ],
    );
  }
}

/// One edge affordance. Sits on top of the tiles rather than beside them so the
/// shelf itself stays full-bleed.
class _ShelfArrow extends StatelessWidget {
  const _ShelfArrow({
    required this.buttonKey,
    required this.alignment,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  /// Sits on the button itself rather than on this widget, whose box spans the
  /// whole shelf: a key on the box would point a tap at the middle of a tile.
  final Key buttonKey;
  final Alignment alignment;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final onLeft = alignment == Alignment.centerLeft;
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: AppColors.nightDune.withValues(alpha: 0.78),
            shape: Border(
              left: onLeft
                  ? BorderSide.none
                  : const BorderSide(color: AppColors.borderSubtle),
              right: onLeft
                  ? const BorderSide(color: AppColors.borderSubtle)
                  : BorderSide.none,
            ),
            child: InkWell(
              onTap: onPressed,
              mouseCursor: SystemMouseCursors.click,
              hoverColor: AppColors.hoverSurface,
              highlightColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              child: SizedBox(
                key: buttonKey,
                width: 28,
                height: _arrowHeight,
                child: Icon(icon, size: 18, color: AppColors.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed extents keep the shelf off the layout critical path: it never measures
/// its children, so a resize cannot cascade into image work.
const double _cardWidth = libraryHomeNewsCardWidth;
const double _cardHeight = 148;
const double _arrowHeight = 64;

/// Sub-pixel slack, so a shelf resting exactly at an edge does not flicker an
/// arrow that cannot move it.
const double _extentEpsilon = 1;
