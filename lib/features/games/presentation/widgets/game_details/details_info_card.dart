import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../models/game_info.dart';
import '../../../../../providers/compression/compression_provider.dart';
import '../../../../../providers/settings/settings_provider.dart';
import '../../../../../providers/system/platform_shell_provider.dart';
import '../game_actions.dart';

const ValueKey<String> _detailsStatusActionRowKey = ValueKey<String>(
  'detailsStatusActionRow',
);
const ValueKey<String> _detailsInfoCardKey = ValueKey<String>(
  'detailsInfoCard',
);
const ValueKey<String> _detailsStatusPrimaryActionKey = ValueKey<String>(
  'detailsStatusPrimaryAction',
);
const ValueKey<String> _detailsStatusExcludeActionKey = ValueKey<String>(
  'detailsStatusExcludeAction',
);
const ValueKey<String> _detailsStatusUnsupportedActionKey = ValueKey<String>(
  'detailsStatusUnsupportedAction',
);

class GameDetailsInfoCard extends ConsumerWidget {
  const GameDetailsInfoCard({
    required this.game,
    required this.currentSize,
    required this.savedBytes,
    required this.savingsPercent,
    required this.lastCompressedText,
    super.key,
  });

  final GameInfo game;
  final int currentSize;
  final int savedBytes;
  final String savingsPercent;
  final String? lastCompressedText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExcluded = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.excludedPaths.contains(game.path) ??
            false,
      ),
    );

    return Card(
      key: _detailsInfoCardKey,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusSectionHeader(game: game, isExcluded: isExcluded),
            _StatLine(label: 'Platform', value: game.platform.displayName),
            _StatLine(
              label: 'Compression',
              value: game.isCompressed ? 'Compressed' : 'Not compressed',
            ),
            _StatLine(
              label: 'DirectStorage',
              value: game.isDirectStorage ? 'Detected' : 'Not detected',
            ),
            _StatLine(
              label: 'Unsupported',
              value: game.isUnsupported ? 'Flagged' : 'Not flagged',
            ),
            _StatLine(
              label: 'Auto-compress',
              value: isExcluded ? 'Excluded' : 'Included',
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: AppColors.borderSubtle),
            ),
            const _InfoGroupTitle(title: 'Storage'),
            _StatLine(
              label: 'Original size',
              value: _formatBytes(game.sizeBytes),
            ),
            _StatLine(label: 'Current size', value: _formatBytes(currentSize)),
            _HeroMetricLine(
              label: 'Space saved',
              value: _formatBytes(savedBytes),
              trailingText: lastCompressedText == null
                  ? null
                  : 'Compressed $lastCompressedText',
            ),
            _HeroMetricLine(label: 'Savings', value: '$savingsPercent%'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: AppColors.borderSubtle),
            ),
            const _InfoGroupTitle(title: 'Install Path'),
            const SizedBox(height: 6),
            _PathBlock(path: game.path),
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(2)} GB';
  }
}

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
    // Build actions widget once, outside the LayoutBuilder.
    final actions = Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _StatusActionButtons(
          game: widget.game,
          isExcluded: widget.isExcluded,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < _StatusSectionHeader._compactBreakpoint;
        if (compact == _compact) {
          return compact
              ? _buildCompact(actions)
              : _buildWide(actions);
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
        const _InfoGroupTitle(title: 'Status'),
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
          const Expanded(child: _InfoGroupTitle(title: 'Status')),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowDirectStorageOverride = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.directStorageOverrideEnabled ?? false,
      ),
    );

    return Wrap(
      key: _detailsStatusActionRowKey,
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildCompressionButton(ref, allowDirectStorageOverride),
        _buildUnsupportedButton(context, ref),
        OutlinedButton.icon(
          onPressed: () =>
              ref.read(platformShellServiceProvider).openFolder(game.path),
          icon: const Icon(LucideIcons.folderOpen, size: 16),
          label: const Text('Open Folder'),
        ),
        OutlinedButton.icon(
          key: _detailsStatusExcludeActionKey,
          onPressed: () => ref
              .read(settingsProvider.notifier)
              .toggleGameExclusion(game.path),
          icon: const Icon(LucideIcons.shieldAlert, size: 16),
          label: Text(
            isExcluded
                ? 'Include In Auto-Compression'
                : 'Exclude From Auto-Compression',
          ),
        ),
      ],
    );
  }

  Widget _buildCompressionButton(
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
        label: const Text('Decompress'),
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
      label: const Text('Compress Now'),
    );
  }

  Widget _buildUnsupportedButton(BuildContext context, WidgetRef ref) {
    final nextUnsupported = !game.isUnsupported;
    return OutlinedButton.icon(
      key: _detailsStatusUnsupportedActionKey,
      onPressed: () => toggleGameUnsupportedStatus(
        ref, context, game, markUnsupported: nextUnsupported,
      ),
      icon: Icon(
        nextUnsupported ? LucideIcons.ban : LucideIcons.checkCircle2,
        size: 16,
      ),
      label: Text(
        nextUnsupported ? 'Mark as Unsupported' : 'Mark as Supported',
      ),
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
        title.toUpperCase(),
        style: AppTypography.label.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _PathBlock extends StatelessWidget {
  const _PathBlock({required this.path});

  final String path;

  static final _pathDecoration = BoxDecoration(
    color: AppColors.surfaceElevated.withValues(alpha: 0.8),
    borderRadius: const BorderRadius.all(Radius.circular(8)),
    border: Border.all(color: AppColors.borderSubtle),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _pathDecoration,
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              path,
              style: AppTypography.mono.copyWith(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Copy path',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: path));
              final messenger = ScaffoldMessenger.maybeOf(context);
              messenger?.hideCurrentSnackBar();
              messenger?.showSnackBar(
                const SnackBar(
                  content: Text('Install path copied.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            icon: const Icon(LucideIcons.copy, size: 16),
          ),
        ],
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetricLine extends StatelessWidget {
  const _HeroMetricLine({
    required this.label,
    required this.value,
    this.trailingText,
  });

  final String label;
  final String value;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  value,
                  style: AppTypography.monoMedium.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (trailingText != null)
                  Text(
                    trailingText!,
                    style: AppTypography.label.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
