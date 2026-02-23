part of 'inventory_components.dart';

class _HorizontalSortMenuEntry extends PopupMenuEntry<InventorySortField> {
  const _HorizontalSortMenuEntry({required this.selected});

  static const double _entryHeight = 48;
  final InventorySortField selected;

  @override
  double get height => _entryHeight;

  @override
  bool represents(InventorySortField? value) => selected == value;

  @override
  State<_HorizontalSortMenuEntry> createState() =>
      _HorizontalSortMenuEntryState();
}

class _HorizontalSortMenuEntryState extends State<_HorizontalSortMenuEntry> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: _inventorySortMenuRowKey,
      height: _HorizontalSortMenuEntry._entryHeight,
      child: Row(
        children: InventorySortField.values
            .map(
              (field) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _SortMenuOptionButton(
                    label: _inventorySortFieldLabel(field),
                    isSelected: field == widget.selected,
                    onPressed: () => Navigator.of(context).pop(field),
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _SortMenuOptionButton extends StatelessWidget {
  const _SortMenuOptionButton({
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        visualDensity: VisualDensity.compact,
        foregroundColor: isSelected
            ? AppColors.textPrimary
            : AppColors.textSecondary,
        backgroundColor: isSelected
            ? AppColors.surfaceElevated.withValues(alpha: 0.85)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected
                ? AppColors.accent.withValues(alpha: 0.55)
                : AppColors.borderSubtle,
          ),
        ),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodySmall,
      ),
    );
  }
}

class _SortMenuPosition {
  const _SortMenuPosition({required this.width, required this.position});

  final double width;
  final RelativeRect position;
}
