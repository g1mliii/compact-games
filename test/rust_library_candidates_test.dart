import 'package:flutter_test/flutter_test.dart';
import 'package:compact_games/services/rust_library_candidates.dart';

void main() {
  test('profile mode prefers the release Rust DLL', () {
    expect(
      buildRustLibraryCandidates(
        isReleaseMode: false,
        isProfileMode: true,
        preferDebugRustDll: true,
      ),
      const [
        'rust/target/release/compact_games_core.dll',
        'rust/target/debug/compact_games_core.dll',
      ],
    );
  });

  test('debug mode still honors debug-first preference', () {
    expect(
      buildRustLibraryCandidates(
        isReleaseMode: false,
        isProfileMode: false,
        preferDebugRustDll: true,
      ),
      const [
        'rust/target/debug/compact_games_core.dll',
        'rust/target/release/compact_games_core.dll',
      ],
    );
  });
}
