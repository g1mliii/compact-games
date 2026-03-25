import 'package:pressplay/l10n/app_localizations.dart';

import '../../models/compression_algorithm.dart';
import '../../models/game_info.dart';

extension CompressionAlgorithmLocalizationX on CompressionAlgorithm {
  String localizedLabel(AppLocalizations l10n) {
    return switch (this) {
      CompressionAlgorithm.xpress4k => l10n.algorithmXpress4k,
      CompressionAlgorithm.xpress8k => l10n.algorithmXpress8k,
      CompressionAlgorithm.xpress16k => l10n.algorithmXpress16k,
      CompressionAlgorithm.lzx => l10n.algorithmLzx,
    };
  }
}

extension PlatformLocalizationX on Platform {
  String localizedLabel(AppLocalizations l10n) {
    return switch (this) {
      Platform.steam => l10n.platformSteam,
      Platform.epicGames => l10n.platformEpicGames,
      Platform.gogGalaxy => l10n.platformGogGalaxy,
      Platform.ubisoftConnect => l10n.platformUbisoftConnect,
      Platform.eaApp => l10n.platformEaApp,
      Platform.battleNet => l10n.platformBattleNet,
      Platform.xboxGamePass => l10n.platformXboxGamePass,
      Platform.custom => l10n.platformCustom,
      Platform.application => l10n.platformApplication,
    };
  }
}
