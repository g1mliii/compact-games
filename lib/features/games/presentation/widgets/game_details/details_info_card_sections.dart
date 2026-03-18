part of 'details_info_card.dart';

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
  const _PathBlock({required this.path, super.key});

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
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PathText(path: widget.path),
                const SizedBox(height: 8),
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
                const SizedBox(width: 6),
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
        height: 1.3,
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
