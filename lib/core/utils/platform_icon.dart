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
  };
}
