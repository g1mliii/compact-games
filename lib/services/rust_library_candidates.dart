List<String> buildRustLibraryCandidates({
  required bool isReleaseMode,
  required bool isProfileMode,
  required bool preferDebugRustDll,
}) {
  const releaseDll = 'rust/target/release/pressplay_core.dll';
  const debugDll = 'rust/target/debug/pressplay_core.dll';

  if (isReleaseMode) {
    return const [releaseDll];
  }

  if (isProfileMode) {
    return const [releaseDll, debugDll];
  }

  return preferDebugRustDll
      ? const [debugDll, releaseDll]
      : const [releaseDll, debugDll];
}
