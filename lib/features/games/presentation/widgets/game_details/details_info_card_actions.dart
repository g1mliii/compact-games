part of 'details_info_card.dart';

class _StatusSectionHeader extends StatefulWidget {
  const _StatusSectionHeader({required this.game, required this.isExcluded});

  static const double _compactBreakpoint = 720;

  final GameInfo game;
  final bool isExcluded;

  @override
  State<_StatusSectionHeader> createState() => _StatusSectionHeaderState();
}

class _StatusSectionHeaderState extends State<_StatusSectionHeader> {
  bool? _compact;

  String? _statusNoteText(BuildContext context) {
    if (widget.game.isUnsupported) {
      return context.l10n.gameDetailsUnsupportedWarning;
    }
    if (widget.game.isDirectStorage) {
      return context.l10n.gameDetailsDirectStorageWarning;
    }
    return null;
  }

  Widget _buildStatusNote(BuildContext context) {
    final text = _statusNoteText(context);
    if (text == null) {
      return const SizedBox.shrink();
    }

    return Text(
      text,
      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = RepaintBoundary(
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _StatusActionButtons(
            game: widget.game,
            isExcluded: widget.isExcluded,
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < _StatusSectionHeader._compactBreakpoint;
        if (compact == _compact) {
          return compact ? _buildCompact(actions) : _buildWide(actions);
        }
        _compact = compact;
        return compact ? _buildCompact(actions) : _buildWide(actions);
      },
    );
  }

  Widget _buildCompact(Widget actions) {
    final note = _statusNoteText(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoGroupTitle(title: context.l10n.gameDetailsStatusGroupTitle),
        if (note != null) ...[
          const SizedBox(height: 4),
          _buildStatusNote(context),
        ],
        const SizedBox(height: 6),
        actions,
        const SizedBox(height: 2),
      ],
    );
  }

  Widget _buildWide(Widget actions) {
    final note = _statusNoteText(context);
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
                if (note != null) ...[
                  const SizedBox(height: 4),
                  _buildStatusNote(context),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(flex: 3, child: actions),
        ],
      ),
    );
  }
}

class _StatusActionButtons extends ConsumerWidget {
  const _StatusActionButtons({required this.game, required this.isExcluded});

  final GameInfo game;
  final bool isExcluded;

  static final _destructiveStyle = TextButton.styleFrom(
    foregroundColor: AppColors.error,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowDirectStorageOverride = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.directStorageOverrideEnabled ?? false,
      ),
    );

    return Column(
      key: _detailsStatusActionRowKey,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildCompressionButton(context, ref, allowDirectStorageOverride),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(platformShellServiceProvider).openFolder(game.path),
              icon: const Icon(LucideIcons.folderOpen, size: 16),
              label: Text(context.l10n.commonOpenFolder),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildUnsupportedButton(context, ref),
            OutlinedButton.icon(
              key: _detailsStatusExcludeActionKey,
              onPressed: () => ref
                  .read(settingsProvider.notifier)
                  .toggleGameExclusion(game.path),
              icon: const Icon(LucideIcons.shieldAlert, size: 16),
              label: Text(
                isExcluded
                    ? context.l10n.gameMenuIncludeInAutoCompression
                    : context.l10n.gameMenuExcludeFromAutoCompression,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => _removeFromLibrary(context, ref),
          style: _destructiveStyle,
          icon: const Icon(LucideIcons.trash2, size: 16),
          label: Text(context.l10n.gameMenuRemoveFromLibrary),
        ),
      ],
    );
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
      if (!context.mounted) {
        return;
      }
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
    if (game.isCompressed) {
      return FilledButton.icon(
        key: _detailsStatusPrimaryActionKey,
        onPressed: () => ref
            .read(compressionProvider.notifier)
            .startDecompression(gamePath: game.path, gameName: game.name),
        icon: const Icon(LucideIcons.archiveRestore, size: 16),
        label: Text(context.l10n.gameMenuDecompress),
      );
    }

    return FilledButton.icon(
      key: _detailsStatusPrimaryActionKey,
      onPressed: game.isDirectStorage && !allowDirectStorageOverride
          ? null
          : () => ref
                .read(compressionProvider.notifier)
                .startCompression(
                  gamePath: game.path,
                  gameName: game.name,
                  allowDirectStorageOverride: allowDirectStorageOverride,
                ),
      icon: const Icon(LucideIcons.archive, size: 16),
      label: Text(context.l10n.gameMenuCompressNow),
    );
  }

  Widget _buildUnsupportedButton(BuildContext context, WidgetRef ref) {
    final nextUnsupported = !game.isUnsupported;
    return OutlinedButton.icon(
      key: _detailsStatusUnsupportedActionKey,
      onPressed: () => toggleGameUnsupportedStatus(
        ref,
        context,
        game,
        markUnsupported: nextUnsupported,
      ),
      icon: Icon(
        nextUnsupported ? LucideIcons.ban : LucideIcons.checkCircle2,
        size: 16,
      ),
      label: Text(
        nextUnsupported
            ? context.l10n.gameMenuMarkUnsupported
            : context.l10n.gameMenuMarkSupported,
      ),
    );
  }
}
