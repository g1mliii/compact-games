import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/watcher_event.dart';
import '../games/game_list_provider.dart';

final watcherEventsProvider = StreamProvider.autoDispose<WatcherEvent>((ref) {
  final bridge = ref.watch(rustBridgeServiceProvider);
  return bridge.watchWatcherEvents();
});
