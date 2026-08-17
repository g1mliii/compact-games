# Compact Games on Steam

This folder contains the source-of-truth checklist and store copy for the Steam release. Steam account credentials, App IDs, Depot IDs, and generated upload content must not be committed.

## Distribution design

- Product type: **Application / Software**, not a game.
- Supported platform: **Windows 10 and Windows 11, 64-bit only**.
- Steam Deck / SteamOS: **unsupported**. Compact Games requires Windows NTFS and the Windows Overlay Filter API; Proton support must not be claimed.
- Launch executable: `compact_games.exe`, with no launch arguments and no third-party installer.
- Steamworks API integration: not required for the first release. The SDK is required for SteamPipe upload, while API features are optional.
- Updates: Steam owns the files in the Steam depot. The Steam build is compiled with `COMPACT_GAMES_DISTRIBUTION=steam`, which disables the standalone GitHub installer updater.
- Cloud saves: do not enable. Settings contain machine-specific game paths and should not roam between PCs.
- Common redistributables: the packaging script requires and bundles the x64 Visual C++ runtime DLLs. Also select the matching Visual C++ common redistributable in Steamworks if Valve's current review guidance requests it.

## Prepare a depot

While waiting for App and Depot IDs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-steam-package.ps1 `
  -AllowMissingCoverProxy
```

After Steamworks assigns both IDs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-steam-package.ps1 `
  -AppId 1234560 `
  -DepotId 1234561
```

The script builds Rust and Flutter in release mode, selects the Steam distribution channel, adds the project license and generated Rust dependency notices, records a hashed `compact_games_build.json` provenance marker, stages the loose application bundle under `dist/steam/content`, creates a SHA-256 manifest, and writes SteamPipe VDF files under `dist/steam/scripts`.

The build requires the repository-pinned Flutter 3.44.8 toolchain. Put that SDK first on `PATH`, or pass its `flutter.bat` explicitly with `-FlutterExecutable C:\path\to\flutter-3.44.8\bin\flutter.bat`. The script verifies the exact version before generating bindings or compiling.

Use `-SkipCompile` only to restage a Steam-mode release bundle that this script already built successfully. The script verifies the recorded distribution, version, executable, Dart AOT library, and Rust DLL hashes before accepting the bundle, so a later standalone build cannot be mislabeled as Steam content.

Production packaging requires `COMPACT_GAMES_SGDB_PROXY_URL` and `COMPACT_GAMES_SGDB_TOKEN`; a missing pair fails the build. `-AllowMissingCoverProxy` is only for local or CI validation and must not be used for an uploaded depot.

Do not upload the Inno Setup installer to the depot. Steam installs and uninstalls the loose application bundle itself.

To upload after installing the current Steamworks SDK, copy `dist/steam/content` and `dist/steam/scripts` into the SDK ContentBuilder layout or point equivalent VDF paths at them. Run SteamCMD interactively so credentials and Steam Guard codes never enter source control. First upload to a password-protected beta branch, install it through the Steam client on a clean Windows account, and only then promote a reviewed build to the default branch.

## Steamworks configuration

Set these values after the app credit is activated:

- General installation: launch `compact_games.exe` on Windows only.
- Store platform: Windows only; minimum Windows 10.
- Store languages: English, Spanish, and Simplified Chinese for interface; no full audio.
- Categories/features: Software and Utilities only. Do not claim achievements, controller support, Steam Cloud, multiplayer, Workshop, or other unimplemented Steam features.
- Support URL: `https://github.com/g1mliii/compact-games/issues`
- Website: `https://compactgames.app/`
- Privacy policy: `https://compactgames.app/privacy.html`
- Executable working directory: depot root.

## Test through Steam

Complete these checks from a Steam-installed beta build, not from the repository build folder:

1. Fresh install and first launch on Windows 10 and Windows 11 x64.
2. About screen says Steam manages updates and exposes no installer download controls.
3. Automatic discovery finds supported libraries without modifying game files.
4. Estimate, compress, cancel, resume, decompress, and restore workflows on an NTFS test library.
5. Known DirectStorage/unsupported games are blocked with a clear warning.
6. A running game is not compressed.
7. Tray minimize, restore, click-away dismissal, second-launch handoff, and clean quit.
8. Optional launch-at-startup remains off until the user enables it.
9. Steam updates the depot cleanly while Compact Games is closed.
10. Steam uninstall removes application files but does not silently alter or delete games or user data.
11. Network-offline launch works; optional update/community/cover requests fail gracefully.
12. At least five real 1920x1080 or larger 16:9 screenshots are captured from the near-final Steam build. Do not use concept art as screenshots.

## Required release timing

- Pay and activate the per-product Steam Direct app credit after the partner account is accepted.
- For the first few products, Steam imposes a 30-day wait between paying the app fee and release; preparation and review can continue during that window.
- Steam requires a Coming Soon page to be public for at least two weeks before release.
- Submit both the near-final store page and near-final build at least seven business days before the target release; Valve says reviews typically take 3-5 business days.
- Configure any launch discount before release. A product cannot normally be discounted for 30 days after release, except for a preconfigured launch discount.

Current official references:

- https://partner.steamgames.com/doc/gettingstarted/appfee
- https://partner.steamgames.com/doc/store/review_process
- https://partner.steamgames.com/doc/store/types
- https://partner.steamgames.com/doc/sdk/uploading
- https://partner.steamgames.com/doc/store/assets
- https://partner.steamgames.com/doc/store/pricing
- https://partner.steamgames.com/doc/marketing/discounts

## Remaining account-only blockers

- Steamworks partner acceptance, tax/bank verification, and app-credit activation.
- Real App ID and Depot ID.
- Steam pricing submission and Valve approval.
- Uploading the build and setting a beta/default branch live.
- Publishing the Coming Soon page and later pressing Release App.

None of those external actions should be reported complete until Steamworks confirms them.
