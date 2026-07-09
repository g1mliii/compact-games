import 'package:flutter_test/flutter_test.dart';
import 'package:compact_games/services/rust_library_candidates.dart';

void main() {
  test('uses the DLL staged beside the executable', () {
    expect(
      buildRustLibraryCandidates(
        executablePath: r'C:\Program Files\Compact Games\compact_games.exe',
      ),
      const [r'C:\Program Files\Compact Games\compact_games_core.dll'],
    );
  });
}
