import 'package:flutter/widgets.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/game_info.dart';

IconData platformIcon(Platform platform) {
  return switch (platform) {
    Platform.steam => LucideIcons.flame,
    Platform.epicGames => LucideIcons.rocket,
    Platform.gogGalaxy => LucideIcons.star,
    Platform.ubisoftConnect => LucideIcons.shield,
    Platform.eaApp => LucideIcons.gamepad2,
    Platform.battleNet => LucideIcons.cloudLightning,
    Platform.xboxGamePass => LucideIcons.tv2,
    Platform.custom => LucideIcons.folder,
    Platform.application => LucideIcons.archive,
  };
}

String platformGlyphAsset(Platform platform) {
  return switch (platform) {
    Platform.steam => 'assets/platforms/steam.svg',
    Platform.epicGames => 'assets/platforms/epic.svg',
    Platform.gogGalaxy => 'assets/platforms/gog.svg',
    Platform.ubisoftConnect => 'assets/platforms/ubisoft.svg',
    Platform.eaApp => 'assets/platforms/ea.svg',
    Platform.battleNet => 'assets/platforms/battlenet.svg',
    Platform.xboxGamePass => 'assets/platforms/xbox.svg',
    Platform.custom => 'assets/platforms/custom.svg',
    Platform.application => 'assets/platforms/application.svg',
  };
}
