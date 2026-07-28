# Compact Games Linux Port Plan

Status: proposed

Prepared: 2026-07-27

Scope: x86_64 Linux desktop; CachyOS/Arch, Fedora, Debian/Ubuntu, openSUSE,
GNOME, KDE Plasma, Cinnamon, Xfce, and MATE

## Executive decision

Build Linux support as a capability-aware port, not as a direct WOF replacement.

The recommended first useful release is:

- Native Linux Flutter application.
- Steam and custom-folder discovery first.
- Read-only inventory on every supported Linux filesystem.
- Storage optimization only when the filesystem backend can prove that the
  operation and its reversal are safe.
- Btrfs as the first optimization backend.
- No root daemon, loopback filesystem, Flatpak, Snap, or forced filesystem
  conversion in the first release.
- No claim of feature parity on ext4, XFS, F2FS, ZFS, or bcachefs until each
  backend independently satisfies the restore and crash-recovery contract.

This is the right boundary because Compact Games currently relies on Windows
Overlay Filter (WOF). Linux has no distro-wide equivalent. Btrfs supports
transparent compression, but merely setting the compression property affects
new writes; rewriting existing extents has snapshot/reflink and free-space
consequences. The Btrfs documentation explicitly warns that defragmentation
does not preserve extent sharing and may increase space consumption:

- <https://btrfs.readthedocs.io/en/latest/Compression.html>
- <https://btrfs.readthedocs.io/en/latest/Defragmentation.html>
- <https://btrfs.readthedocs.io/en/stable/btrfs-filesystem.html>

The Linux port should therefore use the product term **storage optimization**
internally and expose exact backend state in the UI. Windows can continue to
say Compress/Decompress.

## Estimated effort

Assumptions:

-
| Area | Current implementation | Linux impact |
|---|---|---|
| Compression engine | WOF, XPRESS/LZX, Windows file-control APIs | New backend required |
| Compression state | Physical size and WOF backing checks | New allocated/shared/compressed extent model |
| Ownership | `managed_paths.json`, record after successful WOF operation | Versioned backend-aware ledger and recovery journal |
| Game discovery | Windows paths, registries, ProgramData manifests | Steam paths reusable in concept; other launchers need Linux/Wine sources |
| Safety | DirectStorage and Windows process checks | DirectStorage policy is not the Linux policy; process checks largely reusable |
| Shell | Explorer, PowerShell picker, `.exe` launching | XDG portals/file selector, `xdg-open`, URI handlers, Linux executable rules |
| Startup | HKCU Run registry | XDG autostart desktop entry or systemd user unit |
| Tray | Windows-first lifecycle | AppIndicator dependency; GNOME may not show a tray icon |
| Native bridge | Loads `compact_games_core.dll` | Load `libcompact_games_core.so` |
| Update | Downloads and launches Inno Setup `.exe` | Package-aware notification; no silent self-installer |
| Installer | Inno Setup, Explorer verbs, uninstall guard | `.deb`, `.rpm`, PKGBUILD; package removal cannot own game restoration |
| CI/release | Windows-only build and installer release | Linux build/test/package jobs and per-platform manifest assets |

Likely reusable without a redesign:

- Flutter screens, theme, navigation, localization, filters, cover art, and most
  Riverpod state.
- FIFO manual compression queue and cancellation flow.
- Progress transport through Flutter Rust Bridge.
- Compression estimates and community database, subject to Linux-specific
  calibration.
- File watching through `notify`.
- CPU/memory idle detection through `sysinfo`.
- Active-process safety checks after Linux path tests are added.
- Managed-ownership principles: do not infer ownership from compression state,
  record only completed operations, and require explicit restore choices.

## Linux product behavior

### User-visible storage states

Every game should show one of these states:

1. **Optimization available**

   The path is on a supported filesystem, the app can write it, no blocking
   safety condition exists, and the backend supports a verified reverse
   operation.

2. **Already optimized by the filesystem**

   The mount or inherited directory policy already compresses new game data.
   Compact Games must not claim ownership or offer to undo it.

3. **Optimized by Compact Games**

   A committed ledger entry names the backend, operation version, path identity,
   prior policy, and completion evidence.

4. **Partially optimized - resume or restore**

   A durable journal proves an interrupted or cancelled operation. Automation
   remains paused for that path until the user resolves it.

5. **Unsupported filesystem**

   Inventory, launch, cover art, and estimates still work. The primary action
   explains why storage optimization is unavailable.

6. **Blocked for safety**

   Examples: game running, launcher updating it, read-only mount, insufficient
   headroom, shared extents/snapshots, nested mount, unknown ownership, or
   unsupported kernel/tool version.

### Distro and filesystem expectations

Runtime probing is authoritative; distro name must never decide safety.

| Distribution/install | Typical storage situation | First-release behavior |
|---|---|---|
| CachyOS default install | Btrfs is the documented default and ships with Zstd level 3 compression | App runs; most game data may already be system-compressed, so show that state and do not take ownership |
| Fedora Workstation/new desktop spin install | Btrfs is the default; Fedora enabled Btrfs Zstd compression by default | App runs; commonly reports already optimized; manage only explicitly eligible paths |
| Arch Linux | Filesystem is user-selected | Full behavior on eligible Btrfs paths; inventory-only elsewhere |
| openSUSE Tumbleweed | Btrfs is the documented default, including a home subvolume in the default layout | Probe mount compression and snapshot/shared-extent risk before offering writes |
| Ubuntu/Ubuntu GNOME | Standard installs commonly use regular partitioning; Btrfs is not assumed | App and inventory supported; optimization only on a user-provided eligible Btrfs library |
| Debian GNOME | ext4 is the installer default in most cases | App and inventory supported; optimization unavailable on default ext4 |
| Linux Mint/Pop!_OS | Commonly ext4-based | Same as Ubuntu: inventory works, storage action is capability-gated |
| SteamOS/Steam Deck | Immutable/appliance-style OS and game mode need separate product work | Not a first-release target; desktop-mode inventory can be evaluated later |

References:

- CachyOS filesystem defaults:
  <https://wiki.cachyos.org/installation/filesystem/>
- Fedora Btrfs default:
  <https://docs.fedoraproject.org/en-US/fedora/f33/release-notes/sysadmin/Distribution/#btrfs-default-file-system>
- Fedora transparent compression:
  <https://fedoraproject.org/wiki/Changes/BtrfsTransparentCompression>
- Debian installer filesystem default:
  <https://www.debian.org/releases/stable/amd64/ch06s03>
- Ubuntu storage options:
  <https://documentation.ubuntu.com/desktop/en/latest/reference/advanced-disk-setup-features/>
- openSUSE Btrfs layout:
  <https://doc.opensuse.org/documentation/tumbleweed/snapper/>

### Desktop-environment behavior

| Environment | Required behavior |
|---|---|
| GNOME on Wayland | Use system window decorations. Do not require a tray icon. Disable "minimize to tray" unless AppIndicator support is detected. Never rely on forced window focus/positioning. |
| KDE Plasma on Wayland | Test StatusNotifier/AppIndicator tray behavior, normal decorations, notifications, and autostart. |
| Cinnamon, Xfce, MATE | Test tray and XDG autostart, but keep the app usable when either fails. |
| X11 sessions | Supported as a compatibility path, not the source of truth for Wayland behavior. |

The current `tray_manager` dependency supports Linux but requires an
Ayatana/AppIndicator development/runtime library, and its own documentation
notes that GNOME may require the AppIndicator extension. The product must
therefore treat the tray as an optional capability.

## Target architecture

### 1. Replace WOF-shaped APIs with a backend contract

Add a Rust storage backend boundary:

```rust
trait StorageBackend {
    fn id(&self) -> StorageBackendId;
    fn probe(&self, path: &Path) -> Result<StorageCapabilities, StorageError>;
    fn measure(&self, path: &Path, mode: MeasureMode)
        -> Result<StorageMeasurement, StorageError>;
    fn optimize(&self, request: OptimizeRequest, sink: &dyn ProgressSink)
        -> Result<StorageOperationResult, StorageError>;
    fn restore(&self, request: RestoreRequest, sink: &dyn ProgressSink)
        -> Result<StorageOperationResult, StorageError>;
    fn verify_owned_state(&self, record: &ManagedPathRecord)
        -> Result<OwnershipState, StorageError>;
}
```

Initial implementations:

- `WindowsWofBackend`: wraps the existing engine without changing Windows
  behavior.
- `LinuxBtrfsBackend`: added only after Phase 0 proves the operation contract.
- `UnsupportedBackend`: returns inventory measurements and an exact capability
  reason without exposing write actions.

Do not keep `WofApiError` as the cross-platform error. Introduce typed categories
such as unsupported filesystem, read-only mount, insufficient headroom, shared
extents, unsupported kernel, tool missing, permission denied, active game,
interrupted operation, and ownership mismatch.

### 2. Add a platform-capability model in Dart

Replace scattered `TargetPlatform.windows` checks with one injected service:

```dart
abstract interface class PlatformCapabilities {
  bool get supportsNativeWindow;
  bool get supportsTray;
  bool get supportsAutostart;
  bool get supportsShellContextActions;
  bool get supportsSelfInstallUpdates;
  String get nativeLibraryName;
}
```

Keep storage capability per path, not per OS. One Linux machine can have a
Btrfs home library, an ext4 external drive, and an NTFS dual-boot drive at the
same time.

### 3. Version the managed ledger

Upgrade managed records from path-only ownership to records containing at
least:

- Schema version.
- Canonical display path and a normalized lookup key.
- Backend ID and backend format version.
- Filesystem UUID, mount ID, device ID, and root inode/path identity.
- Operation ID and committed timestamp.
- Previous directory compression property and relevant mount state.
- Logical, allocated, exclusive, and shared bytes before and after.
- Selected algorithm/profile.
- Whether any pre-existing compression was detected.
- Journal reference and final verification evidence.

Never migrate an existing Windows managed record into Linux ownership merely
because a dual-boot path is visible.

### 4. Add a durable per-operation journal

Linux extent rewrites can be partially complete after cancellation, process
termination, power loss, or ENOSPC. Journal stages before the corresponding
effect:

1. Validated.
2. Prior policy captured.
3. Path locked.
4. Rewrite started.
5. Rewrite completed.
6. Policy committed.
7. Measurements verified.
8. Managed ledger committed.
9. Journal closed.

On startup, reconcile every open journal before automation starts. Recovery
must be idempotent.

### 5. Keep platform state separate

Use XDG paths on Linux:

- Configuration: `$XDG_CONFIG_HOME/compact_games`
- Cache and cover art: `$XDG_CACHE_HOME/compact_games`
- Durable state/journals: `$XDG_STATE_HOME/compact_games`
- Runtime handoff token/socket: `$XDG_RUNTIME_DIR/compact-games`

Do not share a single state directory between Windows and Linux on a dual-boot
game drive.

## Phase 0 - Btrfs feasibility and safety spike

Goal: answer whether Compact Games can honestly offer both Optimize and Restore
without weakening its ownership guarantees.

### Tasks

- [ ] Build a small Rust-only Linux probe, separate from Flutter.
- [ ] Detect filesystem type, filesystem UUID, mount ID/options, read-only
  state, kernel version, and `btrfs-progs` version.
- [ ] Detect inherited or mount-wide compression separately from app ownership.
- [ ] Compare `statx`/allocated blocks, FIEMAP, `btrfs filesystem du`, and
  `compsize` for logical, physical, exclusive, shared, and compressed sizes.
- [ ] Test setting and restoring directory compression properties.
- [ ] Test recompressing existing extents through the kernel defrag ioctl/tool.
- [ ] Test full uncompression on the oldest planned Fedora, Debian, and Ubuntu
  kernels, including the availability and behavior of `--nocomp`.
- [ ] Test an alternative in-place rewrite strategy if kernel defrag cannot
  provide symmetric restore.
- [ ] Verify behavior for sparse files, hard links, symlinks, reflinks, nested
  subvolumes, bind mounts, read-only files, ACLs, xattrs, immutable flags, and
  files concurrently opened by a game or launcher.
- [ ] Measure worst-case temporary-space use.
- [ ] Simulate cancellation, `SIGKILL`, ENOSPC, process crash, and reboot during
  every operation stage.
- [ ] Prove that original file bytes and required metadata remain unchanged.
- [ ] Record performance on SSD and HDD with small-file and large-archive game
  fixtures.

### Go/no-go gate

Proceed to a writable Linux alpha only if all are true:

- A completed Optimize has a verifiable Restore on every supported baseline.
- Cancellation or power loss leaves content usable and recovery deterministic.
- The app never restores compression it did not own.
- Shared extents/snapshots are either preserved or detected and safely blocked.
- ENOSPC cannot corrupt logical file content.
- Required privilege is ordinary game-folder ownership; no unrestricted root
  command execution is needed.
- Savings measurement is honest about shared extents and sparse files.

If any item fails, release Linux inventory/discovery first and keep storage
writes behind an experimental build flag.

## Phase 1 - Cross-platform architecture and Linux runner

### Rust

- [ ] Introduce `StorageBackend` and wrap the WOF implementation.
- [ ] Rename cross-platform API types away from WOF-specific names.
- [ ] Keep Windows output and tests byte-for-byte/behaviorally compatible.
- [ ] Make path normalization platform-aware: case-insensitive on Windows,
  case-sensitive on Linux, while preserving Unicode safely.
- [ ] Add `.so` candidates and Linux FRB library loading.
- [ ] Audit all `cfg(not(windows))` stubs; replace misleading success/empty
  results with explicit capability results where appropriate.

### Flutter

- [ ] Generate the `linux/` runner.
- [ ] Add PNG application/tray icons; the repository currently has only an ICO
  app icon plus SVG platform icons.
- [ ] Add `PlatformCapabilities` and provider overrides for tests.
- [ ] Preserve native Linux window decorations.
- [ ] Make tray initialization optional and non-fatal.
- [ ] Change Windows-only labels such as "Start with Windows" to localized
  platform-neutral text.
- [ ] Preserve all current Windows behavior through regression tests.

### Acceptance

- `cargo test`, `cargo clippy`, `flutter analyze`, and `flutter test` pass on
  Windows and Linux.
- The Linux app starts, loads `libcompact_games_core.so`, and renders every
  route without a storage write.
- A missing tray, keyring, or optional integration does not prevent startup.

## Phase 2 - Linux discovery and shell integration

### Discovery priority

1. Native Steam.
2. Flatpak Steam.
3. Custom folders.
4. Heroic Games Launcher for Epic and GOG.
5. Lutris.
6. Bottles/Wine prefixes.
7. Other launchers only when a stable manifest source and test fixtures exist.

Do not present Xbox Game Pass as supported on Linux. Do not reuse Windows
registry scanners and silently return an empty list as if the scan succeeded.

### Steam

- [ ] Probe native Steam locations such as `~/.local/share/Steam` and
  `~/.steam/steam`.
- [ ] Probe Flatpak and Snap locations without assuming either is installed.
- [ ] Reuse VDF/appmanifest parsing and library-folder discovery.
- [ ] Store launcher kind/installation ID so native and Flatpak libraries do
  not deduplicate incorrectly.
- [ ] Add fixtures for escaped paths, external drives, missing mounts, and
  Proton compatibility data.

### Shell

- [ ] Replace Explorer folder opening with `xdg-open` or a portal-backed API.
- [ ] Replace PowerShell pickers with Flutter `file_selector` or XDG portals.
- [ ] Launch Steam through `steam://rungameid/<id>` using the registered URI
  handler.
- [ ] Launch Linux executables only when the stored target is an executable
  regular file; retain a per-game explicit target rather than guessing.
- [ ] Add `.desktop` actions only after the main command handoff works through
  XDG runtime state.
- [ ] Defer Nautilus/Dolphin/Nemo file-manager context menus; each uses a
  different extension model.

### Acceptance

- Native and Flatpak Steam libraries are discovered on at least Fedora,
  CachyOS, Ubuntu, and Debian fixtures.
- Custom import works through the native portal/file picker.
- Open folder and Launch game work on GNOME/Wayland and KDE/Wayland.
- Missing launchers produce a real "not installed/not accessible" result, not
  a false successful empty scan.

## Phase 3 - Production Btrfs backend

Implement only the approach approved by Phase 0.

### Capability probe

- [ ] Resolve the path to its mount without crossing symlink or mount
  boundaries.
- [ ] Return filesystem type, UUID, mount options, read-only state, ownership,
  inherited compression, and backend/tool compatibility.
- [ ] Detect system-wide compression and return `alreadyOptimizedBySystem`.
- [ ] Detect nodatacow/nocompress conflicts.
- [ ] Detect shared extents or a conservative condition that blocks unsafe
  rewriting.
- [ ] Compute a conservative headroom requirement before changing anything.

### Operation engine

- [ ] Use ordinary user permissions only.
- [ ] Reuse the existing operation-scoped worker policy only if concurrency
  improves the selected kernel operation safely.
- [ ] Do not descend into symlinks, nested mounts, or subvolumes.
- [ ] Journal before every persistent effect.
- [ ] Support cancellation between files/chunks without abandoning ownership
  evidence.
- [ ] Keep the path locked against a second Compact Games operation.
- [ ] Recheck game/launcher process state immediately before the first write.
- [ ] Verify measurements and content invariants before committing ownership.

### Restore

- [ ] Restore only records owned by the Linux Btrfs backend.
- [ ] Restore the prior directory policy exactly; do not replace a system
  policy with "none" unless that was the recorded prior state.
- [ ] Rebuild uncompressed extents only when the baseline supports the proven
  method.
- [ ] Treat missing mounts, filesystem UUID changes, replaced directories, and
  ownership mismatch as explicit recovery cases.
- [ ] Remove the ledger entry only after full verification.
- [ ] Preserve the existing product rule: uninstall/removal never silently
  restores games.

### Acceptance

- Round-trip byte equality and metadata invariants pass for a representative
  game corpus.
- Four-worker and one-worker tests verify actual selected concurrency if the
  backend uses parallel file work.
- Crash/restart recovery passes at each journal stage.
- A path compressed by mount policy but never managed by Compact Games is never
  offered as app-owned Restore.
- Low-space, snapshots/reflinks, nested mounts, and permission failures are
  blocked before an unsafe write.

## Phase 4 - Linux UX, lifecycle, and automation

### UX

- [ ] Replace the single algorithm dropdown with backend-provided profiles.
  Windows keeps XPRESS/LZX; Linux initially exposes one proven Btrfs Zstd
  profile rather than pretending the algorithms are equivalent.
- [ ] Add a filesystem capability panel to game details.
- [ ] Explain unsupported ext4/XFS paths without suggesting that installing a
  package can add filesystem compression.
- [ ] Show "already optimized by filesystem" separately from "managed by
  Compact Games."
- [ ] Make estimate confidence backend-specific; do not blindly reuse WOF
  ratios as Btrfs predictions.

### Lifecycle

- [ ] Implement XDG autostart with a per-user `.desktop` entry or a systemd user
  service, selected after testing background/keyring behavior.
- [ ] Run normally without a tray on plain GNOME.
- [ ] Use desktop notifications for job completion/errors.
- [ ] Move the single-instance token to `$XDG_RUNTIME_DIR`, require restrictive
  permissions, and keep loopback/token authentication or switch to a Unix
  domain socket.
- [ ] Keep normal app exit separate from package uninstall.

### Automation

- [ ] Disable automation globally until journal reconciliation completes.
- [ ] Require per-path capability success immediately before every automated
  operation.
- [ ] Detect Steam downloads/updates and active Proton/Wine processes.
- [ ] Exclude unsupported mounts and removable drives that are currently
  absent.
- [ ] Never change system-wide mount options automatically.

## Phase 5 - Packaging, updates, and CI

### Packages

Ship in this order:

1. `.deb` for Ubuntu/Debian/Mint/Pop!_OS.
2. `.rpm` for Fedora/openSUSE.
3. PKGBUILD/AUR source package for Arch/CachyOS.
4. Generic tarball or AppImage only after its runtime dependencies and desktop
   integration are tested.

Do not ship Flatpak or Snap initially. Compact Games needs arbitrary game
library access, filesystem/mount inspection, launcher discovery, and
background operation. Broad sandbox permissions would undermine the point of
those formats and still require separate filesystem-backend validation.
Flatpak documentation treats full host filesystem access as a last resort:
<https://docs.flatpak.org/en/latest/flatpak-command-reference.html>

Package dependencies include GTK/Flutter runtime libraries, an
Ayatana/AppIndicator implementation when tray support is enabled, and
`libsecret` for secure storage. Flutter's Linux distribution guide notes that
the bundle still depends on host system libraries:
<https://docs.flutter.dev/platform-integration/linux/building>

### Update model

- [ ] Make the release manifest platform/architecture aware.
- [ ] On native packages, show update availability and open the release/package
  instructions; do not download and execute an installer silently.
- [ ] Keep the Windows Inno Setup flow unchanged.
- [ ] Sign packages and publish checksums/provenance.
- [ ] Never run `sudo`, `dnf`, `apt`, `pacman`, or `zypper` from the app.

### CI

- [ ] Add Ubuntu Linux formatting, analyze, unit-test, Rust test, and release
  build jobs.
- [ ] Add packaging jobs for `.deb` and `.rpm`.
- [ ] Add Arch/CachyOS package builds in clean containers.
- [ ] Add FRB generated-binding checks for `.so` and Linux runner output.
- [ ] Add a Btrfs integration environment using a dedicated VM or self-hosted
  runner; container-only tests are not proof of kernel/filesystem behavior.
- [ ] Keep Windows release gates mandatory so the port cannot regress WOF.

## Phase 6 - Distro and desktop hardening

### Minimum test matrix

| Distribution | Desktop/session | Filesystem cases |
|---|---|---|
| CachyOS current | KDE Wayland; GNOME Wayland | Default compressed Btrfs; separate uncompressed Btrfs; ext4 |
| Fedora current and previous | GNOME Wayland; KDE Wayland | Default compressed Btrfs; custom ext4; external Btrfs |
| Ubuntu current LTS | GNOME Wayland and X11 fallback | ext4 default-style; custom Btrfs |
| Debian stable | GNOME Wayland/X11 as available | ext4; custom Btrfs |
| openSUSE Tumbleweed | KDE Wayland | Btrfs with snapshots/shared extents |
| Arch current | KDE or GNOME | user-selected Btrfs and ext4 |

### Required scenarios

- Fresh install, upgrade, downgrade-block, and package removal.
- Native Steam, Flatpak Steam, multiple libraries, missing external drive.
- A game running natively, through Proton, and through Wine.
- Steam downloading, patching, verifying, and moving a game.
- App hidden/closed with and without tray support.
- Login autostart with locked and unlocked keyrings.
- Suspend/resume, logout, reboot, and abrupt power/process loss.
- Low data space, low Btrfs metadata space, read-only remount, and ENOSPC.
- Snapshots/reflinks, sparse files, hard links, symlinks, nested mounts,
  subvolumes, ACLs, and xattrs.
- Partial journal recovery and explicit restore-before-removal guidance.
- Non-English UI and path names.
- 100k+ file games and multi-hundred-gigabyte libraries.

## Release gates

### Technical preview

- Linux runner and `.so` build are reproducible.
- Steam/custom inventory works.
- No storage mutation is compiled into the public preview.
- GNOME and KDE can start and exit without tray assumptions.

### Alpha

- Phase 0 go/no-go gate passed.
- Btrfs backend is explicitly opt-in.
- Every write has a durable journal and recovery path.
- No root privileges.
- Windows regression suite remains green.

### Public beta

- All minimum matrix rows pass.
- `.deb`, `.rpm`, and Arch package are installable and removable.
- No critical data-loss, ownership, or unrecoverable ENOSPC defect remains.
- Documentation states filesystem limitations before download and in-app.
- Telemetry is not required; bug reports can export a redacted diagnostics
  bundle containing capability and journal state.

### Supported release

- At least one full beta cycle has exercised real Btrfs libraries and system
  compression.
- Restore has been validated after upgrades across the supported ledger/backend
  version.
- Support policy names exact distro versions, package formats, architectures,
  desktop sessions, and filesystems.
- The release page does not use "all Linux distributions" as a synonym for
  "full compression support everywhere."

## Deliberate non-goals for the first Linux release

- Making ext4 or XFS transparently compress individual game folders.
- Creating and mounting a Btrfs loopback image.
- Installing a privileged daemon or broad polkit rule.
- Automatically changing `/etc/fstab` or remounting filesystems.
- Converting ext4 to Btrfs.
- Undoing distro- or user-managed compression.
- Flatpak/Snap distribution.
- Steam Deck game-mode UI.
- Nautilus, Dolphin, Nemo, and Thunar context-menu extensions.
- Xbox Game Pass support.
- Claiming DirectStorage rules are the Linux safety model.

## Recommended implementation order

1. Complete Phase 0 before changing public UI terminology or committing to a
   Linux release date.
2. Land the storage-backend abstraction with the existing WOF implementation
   and prove Windows has not changed.
3. Land a read-only Linux technical preview.
4. Add Steam/custom Linux discovery and normal shell behavior.
5. Add the Btrfs backend behind an experimental flag.
6. Run crash, ENOSPC, snapshot, and ownership tests before enabling it by
   default.
7. Package `.deb`, `.rpm`, and Arch builds.
8. Run the distro/desktop beta matrix.
9. Publish the supported release only after restore/version-upgrade testing.

## Final recommendation

Proceed, but position the first Linux version as **cross-distro game inventory
plus capability-aware storage optimization**, not "the Windows app on Linux."

CachyOS and Fedora are the easiest systems on which to build and test because
Btrfs is common there, but their default compression also means Compact Games
may correctly report that the operating system has already done the work.
Debian and Ubuntu are important packaging and desktop targets, yet their common
ext4 installations will usually be inventory-only unless the user keeps games
on a separate eligible Btrfs filesystem.

The first engineering milestone should be the 5-8 day Btrfs feasibility spike.
It is the cheapest point at which to prove that a Linux storage backend can meet
Compact Games' defining promise: explicit ownership, reversible operations, and
safe recovery.
