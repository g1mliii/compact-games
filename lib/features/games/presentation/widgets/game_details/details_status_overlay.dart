import 'package:flutter/material.dart';
import 'package:compact_games/l10n/app_localizations.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/widgets/status_badge.dart';
import '../../../../../models/game_info.dart';

enum DetailsStatusKind { ready, compressed, directStorage, unsupported }

DetailsStatusKind detailsStatusKind(GameInfo game) {
  if (game.isUnsupported) {
    return DetailsStatusKind.unsupported;
  }
  if (game.isDirectStorage) {
    return DetailsStatusKind.directStorage;
  }
  if (game.isCompressed) {
    return DetailsStatusKind.compressed;
  }
  return DetailsStatusKind.ready;
}

String detailsStatusLabel(AppLocalizations l10n, DetailsStatusKind kind) {
  return switch (kind) {
    DetailsStatusKind.unsupported => l10n.gameStatusUnsupported,
    DetailsStatusKind.directStorage => l10n.gameStatusDirectStorage,
    DetailsStatusKind.compressed => l10n.gameDetailsStatusCompressed,
    DetailsStatusKind.ready => l10n.gameDetailsStatusReady,
  };
}

Color detailsStatusColor(DetailsStatusKind statusKind) {
  return switch (statusKind) {
    DetailsStatusKind.unsupported => AppColors.warning,
    DetailsStatusKind.compressed => AppColors.richGold,
    DetailsStatusKind.directStorage => AppColors.directStorage,
    DetailsStatusKind.ready => AppColors.info,
  };
}

class GameDetailsStatusOverlay extends StatelessWidget {
  const GameDetailsStatusOverlay({
    required this.statusKind,
    required this.statusLabel,
    this.activityLabel,
    super.key,
  });

  final DetailsStatusKind statusKind;
  final String statusLabel;
  final String? activityLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _OverlayBadge(
              key: const ValueKey<String>('detailsHeaderStatusBadge'),
              label: statusLabel,
              color: detailsStatusColor(statusKind),
              maxWidth: 150,
            ),
            if (activityLabel != null)
              _OverlayBadge(
                key: const ValueKey<String>('detailsHeaderActivityBadge'),
                label: activityLabel!,
                color: AppColors.richGold,
                maxWidth: 170,
              ),
          ],
        ),
      ),
    );
  }
}

class _OverlayBadge extends StatelessWidget {
  const _OverlayBadge({
    required super.key,
    required this.label,
    required this.color,
    required this.maxWidth,
  });

  final String label;
  final Color color;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: StatusBadge(label: label, color: color),
      ),
    );
  }
}
