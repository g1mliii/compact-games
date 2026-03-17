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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoGroupTitle(title: context.l10n.gameDetailsStatusGroupTitle),
        const SizedBox(height: 6),
        actions,
        const SizedBox(height: 2),
      ],
    );
  }

  Widget _buildWide(Widget actions) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _InfoGroupTitle(
              title: context.l10n.gameDetailsStatusGroupTitle,
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

  static final _secondaryStyle = TextButton.styleFrom(
    backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.5),
    foregroundColor: AppColors.textPrimary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  );

  static final _tertiaryStyle = TextButton.styleFrom(
    foregroundColor: AppColors.textSecondary,
    backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.18),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  );

  static final _destructiveStyle = TextButton.styleFrom(
    foregroundColor: AppColors.error,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  );

  static final _primaryStyle = FilledButton.styleFrom(
    backgroundColor: AppColors.richGold,
    foregroundColor: AppColors.nightDune,
    disabledBackgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.55),
    disabledForegroundColor: AppColors.textMuted,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
            TextButton.icon(
              onPressed: () =>
                  ref.read(platformShellServiceProvider).openFolder(game.path),
              style: _secondaryStyle,
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
            TextButton.icon(
              key: _detailsStatusExcludeActionKey,
              onPressed: () => ref
                  .read(settingsProvider.notifier)
                  .toggleGameExclusion(game.path),
              style: _tertiaryStyle,
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
        style: _primaryStyle,
        onPressed: () => ref
            .read(compressionProvider.notifier)
            .startDecompression(gamePath: game.path, gameName: game.name),
        icon: const Icon(LucideIcons.archiveRestore, size: 16),
        label: Text(context.l10n.gameMenuDecompress),
      );
    }

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
      icon: const Icon(LucideIcons.archive, size: 16),
      label: Text(context.l10n.gameMenuCompressNow),
    );
  }

  Widget _buildUnsupportedButton(BuildContext context, WidgetRef ref) {
    final nextUnsupported = !game.isUnsupported;
    return TextButton.icon(
      key: _detailsStatusUnsupportedActionKey,
      onPressed: () => toggleGameUnsupportedStatus(
        ref,
        context,
        game,
        markUnsupported: nextUnsupported,
      ),
      style: _tertiaryStyle,
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
