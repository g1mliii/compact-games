import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../../core/localization/app_localization.dart';
import '../../../../../core/localization/presentation_labels.dart';
import '../../../../../core/utils/byte_formatting.dart';
import '../../../../../core/widgets/platform_chip.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../models/compression_algorithm.dart';
import '../../../../../models/compression_estimate.dart';
import '../../../../../models/game_info.dart';
import '../../../../../providers/compression/compression_provider.dart';
import '../../../../../providers/compression/compression_state.dart';
import '../../../../../providers/games/game_list_provider.dart';
import '../../../../../providers/games/selected_game_provider.dart';
import '../../../../../providers/settings/settings_provider.dart';
import '../../../../../providers/system/platform_shell_provider.dart';
import '../game_actions.dart';
part 'details_info_card_actions.dart';
part 'details_info_card_sections.dart';
part 'details_info_card_primitives.dart';

const ValueKey<String> _detailsStatusActionRowKey = ValueKey<String>(
  'detailsStatusActionRow',
);
const ValueKey<String> _detailsInfoCardKey = ValueKey<String>(
  'detailsInfoCard',
);
const ValueKey<String> _detailsStatusPrimaryActionKey = ValueKey<String>(
  'detailsStatusPrimaryAction',
);
const ValueKey<String> _detailsStatusDecompressActionKey = ValueKey<String>(
  'detailsStatusDecompressAction',
);
const ValueKey<String> _detailsStatusExcludeActionKey = ValueKey<String>(
  'detailsStatusExcludeAction',
);
const ValueKey<String> _detailsStatusUnsupportedActionKey = ValueKey<String>(
  'detailsStatusUnsupportedAction',
);
const ValueKey<String> _detailsInstallPathBlockKey = ValueKey<String>(
  'detailsInstallPathBlock',
);

typedef _DetailsEstimateRequest = ({
  String path,
  String name,
  int sizeBytes,
  int? steamAppId,
  CompressionAlgorithm algorithm,
});

final _detailsCompressionEstimateProvider = FutureProvider.autoDispose
    .family<CompressionEstimate?, _DetailsEstimateRequest>((
      ref,
      request,
    ) async {
      final bridge = ref.read(rustBridgeServiceProvider);
      final estimate = await bridge.estimateCompressionSavings(
        gamePath: request.path,
        algorithm: request.algorithm,
        gameName: request.name,
        steamAppId: request.steamAppId,
        knownSizeBytes: request.sizeBytes,
      );
      if (estimate.shouldRetryCommunityLookup) {
        final retryTimer = Timer(
          const Duration(seconds: 2),
          ref.invalidateSelf,
        );
        ref.onDispose(retryTimer.cancel);
      }
      return estimate;
    });

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
    final l10n = context.l10n;
    final isExcluded = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.excludedPaths.contains(game.path) ??
            false,
      ),
    );
    final statusSection = _StatusSectionHeader(
      game: game,
      isExcluded: isExcluded,
    );
    final algorithm =
        ref.watch(
          settingsProvider.select(
            (async) => async.valueOrNull?.settings.algorithm,
          ),
        ) ??
        CompressionAlgorithm.xpress8k;
    final allowDirectStorageOverride = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.directStorageOverrideEnabled ?? false,
      ),
    );
    final directStorageBlocked =
        game.isDirectStorage && !allowDirectStorageOverride;
    final detailsEstimate = game.isCompressed || directStorageBlocked
        ? null
        : ref
              .watch(
                _detailsCompressionEstimateProvider((
                  path: game.path,
                  name: game.name,
                  sizeBytes: game.sizeBytes,
                  steamAppId: game.steamAppId,
                  algorithm: algorithm,
                )),
              )
              .valueOrNull;

    return RepaintBoundary(
      child: Card(
        key: _detailsInfoCardKey,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GameIdentityHeader(game: game),
              const SizedBox(height: 12),
              statusSection,
              _StatLine(
                label: _InfoLabel(l10n.gameDetailsPlatformLabel),
                crossAxisAlignment: CrossAxisAlignment.center,
                valueChild: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PlatformChip(
                      platform: game.platform,
                      semanticLabel: game.platform.localizedLabel(l10n),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        game.platform.localizedLabel(l10n),
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _StatLine(
                label: _InfoLabel(l10n.gameDetailsDirectStorageLabel),
                value: game.isDirectStorage
                    ? l10n.gameDetailsDirectStorageDetected
                    : l10n.gameDetailsDirectStorageNotDetected,
              ),
              _StatLine(
                label: _InfoLabel(l10n.gameDetailsUnsupportedLabel),
                value: game.isUnsupported
                    ? l10n.gameDetailsUnsupportedFlagged
                    : l10n.gameDetailsUnsupportedNotFlagged,
              ),
              _StatLine(
                label: _InfoLabel(l10n.gameDetailsAutoCompressLabel),
                value: isExcluded
                    ? l10n.gameDetailsAutoCompressExcluded
                    : l10n.gameDetailsAutoCompressIncluded,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: AppColors.borderSubtle),
              ),
              _InfoGroupTitle(title: l10n.gameDetailsStorageGroupTitle),
              _StatLine(
                label: _InfoLabel(l10n.gameDetailsOriginalSizeLabel),
                value: formatBytesDetailed(context.l10n, game.sizeBytes),
              ),
              _StatLine(
                label: _InfoLabel(l10n.gameDetailsCurrentSizeLabel),
                value: formatBytesDetailed(context.l10n, currentSize),
              ),
              const SizedBox(height: 6),
              _HeroMetricLine(
                label: _InfoLabel(
                  l10n.gameDetailsSpaceSavedLabel,
                  emphasized: true,
                ),
                value: formatBytesDetailed(context.l10n, savedBytes),
                trailingText: lastCompressedText == null
                    ? null
                    : l10n.gameDetailsCompressedAt(lastCompressedText!),
              ),
              _HeroMetricLine(
                label: _InfoLabel(
                  l10n.gameDetailsSavingsLabel,
                  emphasized: true,
                ),
                value: '$savingsPercent%',
              ),
              if (detailsEstimate != null &&
                  detailsEstimate.estimatedSavedBytes > 0)
                _HeroMetricLine(
                  label: _InfoLabel(
                    l10n.gameDetailsEstimatedSavingsLabel,
                    emphasized: true,
                  ),
                  value:
                      '${formatBytesDetailed(context.l10n, detailsEstimate.estimatedSavedBytes)} '
                      '(${detailsEstimate.estimatedSavingsPercent.toStringAsFixed(1)}%)',
                  trailing: detailsEstimate.showCommunityBadge
                      ? Tooltip(
                          message: l10n.gameEstimateCommunityTooltip,
                          child: const Icon(
                            LucideIcons.database,
                            size: 13,
                            color: AppColors.richGold,
                          ),
                        )
                      : null,
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: AppColors.borderSubtle),
              ),
              _InfoGroupTitle(title: l10n.gameDetailsInstallPathGroupTitle),
              const SizedBox(height: 6),
              _PathBlock(key: _detailsInstallPathBlockKey, path: game.path),
            ],
          ),
        ),
      ),
    );
  }
}
