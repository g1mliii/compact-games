import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the currently selected game path for the list/split view.
/// Null when no game is selected.
final selectedGameProvider = StateProvider<String?>((ref) => null);
