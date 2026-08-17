import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import 'library_aggregate_provider.dart';

@immutable
class HomeOverviewUiModel {
  const HomeOverviewUiModel({
    required this.readyCount,
    required this.reclaimableBytes,
    required this.firstReadyPath,
  });

  final int readyCount;
  final int reclaimableBytes;
  final String? firstReadyPath;
}

/// Compression-banner view of the shared library reduction.
///
/// Deliberately projects only the three fields the banner draws, so highlight
/// changes that Library Home cares about (largest install, most recently
/// compressed) never rebuild the banner.
final homeOverviewProvider = Provider<HomeOverviewUiModel>((ref) {
  final aggregate = ref.watch(
    libraryAggregateProvider.select(
      (a) => (
        readyCount: a.readyCount,
        reclaimableBytes: a.reclaimableBytes,
        firstReadyPath: a.firstReadyPath,
      ),
    ),
  );

  return HomeOverviewUiModel(
    readyCount: aggregate.readyCount,
    reclaimableBytes: aggregate.reclaimableBytes,
    firstReadyPath: aggregate.firstReadyPath,
  );
});
