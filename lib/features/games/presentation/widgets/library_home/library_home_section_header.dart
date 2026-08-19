import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_typography.dart';

/// The heading above a Library Home section, with the note it shows when what
/// is under it came from an earlier fetch.
///
/// Shared so the sections cannot drift apart: they sit directly above one
/// another, where a two-pixel difference in padding is visible.
class LibraryHomeSectionHeader extends StatelessWidget {
  const LibraryHomeSectionHeader({
    super.key,
    required this.title,
    required this.staleLabel,
    required this.isStale,
  });

  final String title;

  /// Shown beside [title] while [isStale] — never on its own.
  final String staleLabel;
  final bool isStale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        children: [
          Text(
            title,
            style: AppTypography.label.copyWith(
              color: AppColors.richGold,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          if (isStale) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                staleLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label.copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
