List<String> buildRustLibraryCandidates({
  required bool isReleaseMode,
  required bool isProfileMode,
  required bool preferDebugRustDll,
}) {
  const bundledDll = 'compact_games_core.dll';
  const releaseDll = 'rust/target/release/compact_games_core.dll';
  const debugDll = 'rust/target/debug/compact_games_core.dll';

  if (isReleaseMode) {
    return const [bundledDll, releaseDll];
  }

  if (isProfileMode) {
    return const [bundledDll, releaseDll, debugDll];
  }

  return preferDebugRustDll
      ? const [debugDll, bundledDll, releaseDll]
      : const [bundledDll, releaseDll, debugDll];
}
