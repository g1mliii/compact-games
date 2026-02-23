import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../models/game_info.dart';

class GameDetailsInfoCard extends StatelessWidget {
  const GameDetailsInfoCard({
    required this.game,
    required this.isExcluded,
    required this.currentSize,
    required this.savedBytes,
    required this.savingsPercent,
    required this.lastPlayedText,
    super.key,
  });

  final GameInfo game;
  final bool isExcluded;
  final int currentSize;
  final int savedBytes;
  final String savingsPercent;
  final String lastPlayedText;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _InfoGroupTitle(title: 'Status'),
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
            ),
            _HeroMetricLine(label: 'Savings', value: '$savingsPercent%'),
            _StatLine(label: 'Last played', value: lastPlayedText),
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
  const _HeroMetricLine({required this.label, required this.value});

  final String label;
  final String value;

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
            child: Text(
              value,
              style: AppTypography.monoMedium.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
