import 'package:compact_games/features/games/presentation/widgets/home_game_list_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds [text] inside the game list panel specifically.
///
/// With nothing selected the split view shows Library Home beside the list, and
/// its highlight cards name the same games, so an unscoped `find.text` matches
/// twice.
Finder listRowText(String text) => find.descendant(
  of: find.byKey(homeGameListPanelListKey),
  matching: find.text(text),
);
