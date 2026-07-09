import 'package:flutter_riverpod/legacy.dart';

/// Holds the currently selected game path for the list/split view.
/// Null when no game is selected.
final selectedGameProvider = StateProvider<String?>((ref) => null);
