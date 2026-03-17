part of 'details_info_card.dart';

class _StorageComparisonBar extends StatelessWidget {
  const _StorageComparisonBar({
    required this.originalSizeBytes,
    required this.currentSizeBytes,
    required this.savedBytes,
  });

  static final _trackColor = AppColors.notCompressed.withValues(alpha: 0.36);
  static final _savedColor = AppColors.richGold.withValues(alpha: 0.22);
  static const _currentGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.richGold, AppColors.desertGold],
  );
  static const _barRadius = BorderRadius.all(Radius.circular(999));

  final int originalSizeBytes;
  final int currentSizeBytes;
  final int savedBytes;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final safeOriginal = originalSizeBytes <= 0 ? 1 : originalSizeBytes;
    final currentRatio = (currentSizeBytes / safeOriginal).clamp(0.0, 1.0);
    final savedRatio = (savedBytes / safeOriginal).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: _barRadius,
            child: SizedBox(
              key: _detailsStorageComparisonBarKey,
              height: 12,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: _trackColor),
                  if (savedRatio > 0)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: savedRatio,
                        child: ColoredBox(
                          key: _detailsStorageSavedFillKey,
                          color: _savedColor,
                        ),
                      ),
                    ),
                  if (currentRatio > 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: currentRatio,
                        child: DecoratedBox(
                          key: _detailsStorageCurrentFillKey,
                          decoration: const BoxDecoration(
                            gradient: _currentGradient,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _StorageLegend(
                color: AppColors.richGold,
                label: l10n.gameDetailsStorageLegendCurrent,
              ),
              _StorageLegend(
                color: AppColors.notCompressed,
                label: l10n.gameDetailsStorageLegendOriginal,
              ),
              _StorageLegend(
                color: AppColors.desertSand,
                label: l10n.gameDetailsStorageLegendSaved,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StorageLegend extends StatelessWidget {
  const _StorageLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTypography.label.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.15,
          ),
        ),
      ],
    );
  }
}

class _InfoGroupTitle extends StatelessWidget {
  const _InfoGroupTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: AppTypography.label.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _PathBlock extends StatefulWidget {
  const _PathBlock({required this.path});

  final String path;

  @override
  State<_PathBlock> createState() => _PathBlockState();
}

class _PathBlockState extends State<_PathBlock> {
  static const double _compactBreakpoint = 180;

  static final _pathDecoration = BoxDecoration(
    color: AppColors.surfaceElevated.withValues(alpha: 0.8),
    borderRadius: const BorderRadius.all(Radius.circular(8)),
    border: Border.all(color: AppColors.borderSubtle),
  );

  bool? _compact;
  Widget? _cached;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _compactBreakpoint;
        if (compact == _compact && _cached != null) return _cached!;
        _compact = compact;
        _cached = _buildContent(compact);
        return _cached!;
      },
    );
  }

  Widget _buildContent(bool compact) {
    return Container(
      decoration: _pathDecoration,
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PathText(path: widget.path),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: _CopyPathButton(path: widget.path),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _PathText(path: widget.path)),
                const SizedBox(width: 4),
                _CopyPathButton(path: widget.path),
              ],
            ),
    );
  }
}

class _PathText extends StatelessWidget {
  const _PathText({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      path,
      style: AppTypography.mono.copyWith(
        fontSize: 12,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _CopyPathButton extends StatelessWidget {
  const _CopyPathButton({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.gameDetailsCopyPathTooltip,
      onPressed: () {
        Clipboard.setData(ClipboardData(text: path));
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(
            content: Text(context.l10n.gameDetailsInstallPathCopied),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      icon: const Icon(LucideIcons.copy, size: 16),
    );
  }
}
