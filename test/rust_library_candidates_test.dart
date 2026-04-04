import 'package:flutter_test/flutter_test.dart';
import 'package:pressplay/services/rust_library_candidates.dart';

void main() {
  test('profile mode prefers the release Rust DLL', () {
    expect(
      buildRustLibraryCandidates(
        isReleaseMode: false,
        isProfileMode: true,
        preferDebugRustDll: true,
      ),
      const [
        'rust/target/release/pressplay_core.dll',
        'rust/target/debug/pressplay_core.dll',
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
        'rust/target/debug/pressplay_core.dll',
        'rust/target/release/pressplay_core.dll',
      ],
    );
  });
}
