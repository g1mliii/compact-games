import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';

class StaticPopupSelectorItem<T> {
  const StaticPopupSelectorItem({
    required this.value,
    required this.label,
    this.selected = false,
  });

  final T value;
  final String label;
  final bool selected;
}

class StaticPopupSelector<T> extends StatefulWidget {
  const StaticPopupSelector({
    super.key,
    required this.labelText,
    required this.selectedLabel,
    required this.items,
    required this.onSelected,
    this.tooltip,
    this.controlHeight = 40,
    this.menuItemHeight = appDesktopMenuRowMin,
    this.contentPadding = const EdgeInsets.fromLTRB(14, 12, 14, 10),
  });

  final String labelText;
  final String selectedLabel;
  final List<StaticPopupSelectorItem<T>> items;
  final ValueChanged<T> onSelected;
  final String? tooltip;
  final double controlHeight;
  final double menuItemHeight;
  final EdgeInsets contentPadding;

  @override
  State<StaticPopupSelector<T>> createState() => _StaticPopupSelectorState<T>();
}

class _StaticPopupSelectorState<T> extends State<StaticPopupSelector<T>> {
  static const Map<ShortcutActivator, Intent> _shortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown): ActivateIntent(),
      };

  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        _openMenu();
        return null;
      },
    ),
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.controlHeight,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        shortcuts: _shortcuts,
        actions: _actions,
        child: Semantics(
          button: true,
          label: widget.tooltip ?? widget.labelText,
          child: RepaintBoundary(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openMenu,
                hoverColor: AppColors.focusFill.withValues(alpha: 0.9),
                focusColor: AppColors.focusFill.withValues(alpha: 0.9),
                overlayColor: appFocusInteractionOverlay,
                splashFactory: NoSplash.splashFactory,
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: widget.labelText,
                    isDense: true,
                    contentPadding: widget.contentPadding,
                  ),
                  child: SizedBox.expand(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.selectedLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(LucideIcons.chevronDown, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu() async {
    final position = _menuPosition();
    if (position == null) {
      return;
    }

    final value = await showMenu<_StaticPopupSelection<T>>(
      context: context,
      position: position,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      items: widget.items
          .map(
            (item) => StaticPopupMenuItem<_StaticPopupSelection<T>>(
              value: _StaticPopupSelection<T>(item.value),
              label: item.label,
              selected: item.selected,
              height: widget.menuItemHeight,
            ),
          )
          .toList(growable: false),
    );
    if (value == null) {
      return;
    }
    widget.onSelected(value.value);
  }

  RelativeRect? _menuPosition() {
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
    return RelativeRect.fromRect(
      Rect.fromLTWH(
        buttonRect.left,
        buttonRect.bottom + 4,
        buttonRect.width,
        0,
      ),
      Offset.zero & overlayBox.size,
    );
  }
}

class _StaticPopupSelection<T> {
  const _StaticPopupSelection(this.value);

  final T value;
}

class StaticPopupMenuItem<T> extends PopupMenuEntry<T> {
  const StaticPopupMenuItem({
    super.key,
    required this.value,
    required this.label,
    required this.selected,
    this.height = 34,
  });

  final T value;
  final String label;
  final bool selected;

  @override
  final double height;

  @override
  bool represents(T? value) => this.value == value;

  @override
  State<StaticPopupMenuItem<T>> createState() => _StaticPopupMenuItemState<T>();
}

class _StaticPopupMenuItemState<T> extends State<StaticPopupMenuItem<T>> {
  static const _kBorderRadius = BorderRadius.all(Radius.circular(8));

  @override
  Widget build(BuildContext context) {
    final baseStyle = AppTypography.bodySmall.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
      fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
    );
    final highlightFill = widget.selected
        ? AppColors.selectionSurface
        : AppColors.focusFill;
    final selectedBorderColor = widget.selected
        ? AppColors.selectionBorder
        : Colors.transparent;

    return RepaintBoundary(
      child: Semantics(
        button: true,
        selected: widget.selected,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: widget.selected ? highlightFill : Colors.transparent,
              borderRadius: _kBorderRadius,
              border: Border.all(color: selectedBorderColor),
            ),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(widget.value),
              mouseCursor: SystemMouseCursors.click,
              hoverColor: AppColors.focusFill,
              focusColor: AppColors.focusFill,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              overlayColor: appFocusInteractionOverlay,
              splashFactory: NoSplash.splashFactory,
              borderRadius: _kBorderRadius,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: widget.height),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: baseStyle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
