import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../games/game_list_provider.dart';

final autoCompressionRunningProvider = StreamProvider.autoDispose<bool>((ref) {
  final bridge = ref.watch(rustBridgeServiceProvider);
  return bridge.watchAutoCompressionStatus();
});
