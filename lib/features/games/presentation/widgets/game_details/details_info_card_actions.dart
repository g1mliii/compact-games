part of 'details_info_card.dart';

class _StatusSectionHeader extends StatefulWidget {
  const _StatusSectionHeader({required this.game, required this.isExcluded});

  static const double _compactBreakpoint = 480;

  final GameInfo game;
  final bool isExcluded;

  @override
  State<_StatusSectionHeader> createState() => _StatusSectionHeaderState();
}

class _StatusSectionHeaderState extends State<_StatusSectionHeader> {
  String? _statusNoteText(BuildContext context) {
    if (widget.game.isUnsupported) {
      return context.l10n.gameDetailsUnsupportedWarning;
    }
    if (widget.game.isDirectStorage) {
      return context.l10n.gameDetailsDirectStorageWarning;
    }
    return null;
  }

  Widget _buildNoteText(String text) {
    return Text(
      text,
      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget? _buildNoteSection(String? noteText) {
    if (noteText == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: _buildNoteText(noteText),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < _StatusSectionHeader._compactBreakpoint;
        return compact ? _buildCompact(context) : _buildWide(context);
      },
    );
  }

  Widget _buildCompact(BuildContext context) {
    final noteSection = _buildNoteSection(_statusNoteText(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoGroupTitle(title: context.l10n.gameDetailsStatusGroupTitle),
        ?noteSection,
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: RepaintBoundary(
            child: _StatusActionButtons(
              game: widget.game,
              isExcluded: widget.isExcluded,
            ),
          ),
        ),
        const SizedBox(height: 2),
      ],
    );
  }

  Widget _buildWide(BuildContext context) {
    final noteSection = _buildNoteSection(_statusNoteText(context));
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoGroupTitle(
                  title: context.l10n.gameDetailsStatusGroupTitle,
                ),
                ?noteSection,
              ],
            ),
          ),
          const SizedBox(width: 10),
          RepaintBoundary(
            child: _StatusActionButtons(
              game: widget.game,
              isExcluded: widget.isExcluded,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusActionButtons extends ConsumerWidget {
  const _StatusActionButtons({required this.game, required this.isExcluded});

  static const double _compactLayoutBreakpoint = 360;

  final GameInfo game;
  final bool isExcluded;

  // Pre-computed color constants — zero runtime allocation on hover/resize.
  // Values derived from the design-system palette (see app_colors.dart).
  static const Color _kIconBg = Color(0x1F2A3B4E); // surfaceElevated @12%
  static const Color _kDestructiveBg = Color(0x14DA7453); // error @8%
  static const Color _kDestructiveBorder = Color(0x59DA7453); // error @35%

  // Static styles — built once at class load, never re-allocated on hover/resize.
  static final ButtonStyle _primaryStyle = FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    minimumSize: const Size(0, 32),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
  static final ButtonStyle _secondaryStyle = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    minimumSize: const Size(0, 32),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  // Outlined icon button using the same 12 px radius as every other button
  // in the app (appButtonRadius / StatusBadge). Uses appInteractionOverlay for
  // hover/press feedback consistent with FilledButton and OutlinedButton.
  static final ButtonStyle _iconBtnStyle = IconButton.styleFrom(
    fixedSize: const Size(30, 30),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: const RoundedRectangleBorder(borderRadius: appButtonRadius),
    side: const BorderSide(color: AppColors.borderSubtle),
    backgroundColor: _kIconBg,
  ).copyWith(overlayColor: appInteractionOverlay);

  static final ButtonStyle _destructiveBtnStyle = IconButton.styleFrom(
    foregroundColor: AppColors.error,
    fixedSize: const Size(30, 30),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: const RoundedRectangleBorder(borderRadius: appButtonRadius),
    side: const BorderSide(color: _kDestructiveBorder),
    backgroundColor: _kDestructiveBg,
  ).copyWith(overlayColor: appInteractionOverlay);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final allowDirectStorageOverride = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.directStorageOverrideEnabled ?? false,
      ),
    );
    final primaryAction = _buildCompressionButton(
      context,
      ref,
      allowDirectStorageOverride,
    );
    final secondaryAction = _buildDecompressionButton(context, ref);
    final actionIcons = <Widget>[
      Tooltip(
        message: l10n.commonOpenFolder,
        child: IconButton(
          tooltip: null,
          style: _iconBtnStyle,
          onPressed: () =>
              ref.read(platformShellServiceProvider).openFolder(game.path),
          icon: const Icon(LucideIcons.folderOpen, size: 16),
        ),
      ),
      Tooltip(
        message: game.isUnsupported
            ? l10n.gameMenuMarkSupported
            : l10n.gameMenuMarkUnsupported,
        child: IconButton(
          key: _detailsStatusUnsupportedActionKey,
          tooltip: null,
          style: _iconBtnStyle,
          onPressed: () => toggleGameUnsupportedStatus(
            ref,
            context,
            game,
            markUnsupported: !game.isUnsupported,
          ),
          icon: Icon(
            game.isUnsupported ? LucideIcons.checkCircle2 : LucideIcons.ban,
            size: 16,
          ),
        ),
      ),
      Tooltip(
        message: isExcluded
            ? l10n.gameMenuIncludeInAutoCompression
            : l10n.gameMenuExcludeFromAutoCompression,
        child: IconButton(
          key: _detailsStatusExcludeActionKey,
          tooltip: null,
          style: _iconBtnStyle,
          onPressed: () => ref
              .read(settingsProvider.notifier)
              .toggleGameExclusion(game.path),
          icon: const Icon(LucideIcons.shieldAlert, size: 16),
        ),
      ),
      Tooltip(
        message: l10n.gameMenuRemoveFromLibrary,
        child: IconButton(
          tooltip: null,
          style: _destructiveBtnStyle,
          onPressed: () => _removeFromLibrary(context, ref),
          icon: const Icon(LucideIcons.trash2, size: 16),
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth.isFinite &&
            constraints.maxWidth < _compactLayoutBreakpoint;
        return compact
            ? _buildCompactActionLayout(
                primaryAction,
                secondaryAction,
                actionIcons,
              )
            : _buildWideActionLayout(
                primaryAction,
                secondaryAction,
                actionIcons,
              );
      },
    );
  }

  Widget _buildWideActionLayout(
    Widget primaryAction,
    Widget? secondaryAction,
    List<Widget> actionIcons,
  ) {
    return Wrap(
      key: _detailsStatusActionRowKey,
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        primaryAction,
        ?secondaryAction,
        ...actionIcons,
      ],
    );
  }

  Widget _buildCompactActionLayout(
    Widget primaryAction,
    Widget? secondaryAction,
    List<Widget> actionIcons,
  ) {
    return Column(
      key: _detailsStatusActionRowKey,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 4,
          runSpacing: 4,
          children: [primaryAction, ?secondaryAction],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: _interleaveSpacing(actionIcons),
        ),
      ],
    );
  }

  List<Widget> _interleaveSpacing(List<Widget> widgets) {
    if (widgets.length < 2) {
      return widgets;
    }
    return [
      for (var index = 0; index < widgets.length; index++) ...[
        if (index > 0) const SizedBox(width: 4),
        widgets[index],
      ],
    ];
  }

  void _removeFromLibrary(BuildContext context, WidgetRef ref) {
    ref.read(gameListProvider.notifier).removeGameByPath(game.path);
    ref.read(selectedGameProvider.notifier).state = null;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.gameDetailsRemovedFromLibrary(game.name)),
          duration: const Duration(seconds: 4),
        ),
      );
    unawaited(_persistLibraryRemoval(context, ref));
  }

  Future<void> _persistLibraryRemoval(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      await ref
          .read(rustBridgeServiceProvider)
          .removeGameFromDiscovery(path: game.path, platform: game.platform);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.l10n.gameRemovalPersistFailed(game.name)),
            duration: const Duration(seconds: 4),
          ),
        );
      await ref.read(gameListProvider.notifier).refresh();
    }
  }

  Widget _buildCompressionButton(
    BuildContext context,
    WidgetRef ref,
    bool allowDirectStorageOverride,
  ) {
    final l10n = context.l10n;
    return FilledButton.icon(
      key: _detailsStatusPrimaryActionKey,
      style: _primaryStyle,
      onPressed: game.isDirectStorage && !allowDirectStorageOverride
          ? null
          : () => ref
                .read(compressionProvider.notifier)
                .startCompression(
                  gamePath: game.path,
                  gameName: game.name,
                  allowDirectStorageOverride: allowDirectStorageOverride,
                ),
      icon: const Icon(LucideIcons.archive, size: 15),
      label: Text(
        game.isCompressed ? l10n.gameMenuRecompress : l10n.gameMenuCompressNow,
      ),
    );
  }

  Widget? _buildDecompressionButton(BuildContext context, WidgetRef ref) {
    if (!game.isCompressed) {
      return null;
    }

    return OutlinedButton.icon(
      key: _detailsStatusDecompressActionKey,
      style: _secondaryStyle,
      onPressed: () => ref
          .read(compressionProvider.notifier)
          .startDecompression(gamePath: game.path, gameName: game.name),
      icon: const Icon(LucideIcons.archiveRestore, size: 15),
      label: Text(context.l10n.gameMenuDecompress),
    );
  }
}
