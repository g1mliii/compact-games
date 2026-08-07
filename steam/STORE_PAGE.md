# Steam store page draft

## Identity

- Name: **Compact Games**
- Developer: **Compact Games**
- Publisher: **Compact Games**
- Product type: **Software / Utility**
- Platform: **Windows**
- Suggested base price: **US$2.99**
- Suggested launch discount: **10%** for 7 days, producing US$2.69 before regional conversion

Why US$2.99: the app is polished and useful enough to avoid bargain-bin positioning, while remaining an impulse purchase. It also leaves more room for future discounts than US$1.99. Because the same MIT-licensed core app is available independently at no charge, the page should explicitly describe the Steam purchase as a convenient Steam-managed edition that supports continued development.

## Short description

Free up space without uninstalling your games. Compact Games scans popular Windows libraries, estimates savings, applies transparent NTFS compression, blocks known risky titles, and lets you restore everything with one click.

## About this software

### Keep your games installed. Take back your drive.

Modern game libraries fill an SSD quickly. Compact Games helps you reclaim space from installed Windows games without deleting them or changing their contents.

It finds supported game libraries, shows current size and potential savings, and applies Windows' transparent NTFS compression with clear progress and one-click restoration.

### Built around safe defaults

- Discover installed games from Steam, Epic Games, GOG, Xbox, and custom folders.
- Estimate potential savings before starting.
- Choose from XPRESS4K, XPRESS8K, XPRESS16K, and LZX compression modes.
- Track active work, queued games, completed savings, and compression history.
- Avoid compressing games that are running.
- Detect known DirectStorage and community-reported incompatible titles.
- Decompress a game at any time and restore managed games before uninstalling.
- Use optional idle automation and filesystem monitoring for selected libraries.
- Minimize to the system tray while work continues.
- Use the interface in English, Spanish, or Simplified Chinese.

### What compression changes

Compact Games uses the Windows Overlay Filter and NTFS compression features. Game file contents remain the same; Windows decompresses data transparently when an application reads it. Results vary by title: games with already-compressed archives may save little space, and storage or CPU performance can differ across systems.

Start with one game, test it, and keep backups of important data. Compact Games provides safety checks and reversible controls, but no utility can guarantee compatibility with every game, mod, anti-cheat system, drive, or future update.

### Steam edition

The Steam edition uses Steam for installation and updates. Compact Games is open-source software, and the same core features are also available in the independently distributed edition. Purchasing it on Steam supports continued development and provides the convenience of Steam-managed delivery.

No account, name, or email address is required inside Compact Games, and the app does not use advertising or third-party analytics. Optional network requests provide cover art and community compatibility data. Sharing unsupported-game reports is off by default and requires explicit consent in Settings; the privacy policy describes the limited pseudonymous data sent when enabled.

## System requirements

### Minimum

- OS: Windows 10 64-bit
- Processor: 64-bit x86 processor
- Memory: 4 GB RAM
- Storage: 250 MB available space for the application, plus normal operating headroom
- Additional notes: An NTFS-formatted game drive and permission to access the selected game folders are required. Not compatible with macOS, Linux, SteamOS, or non-NTFS game drives.

### Recommended

- OS: Windows 11 64-bit
- Processor: Modern multi-core 64-bit processor
- Memory: 8 GB RAM
- Storage: SSD with sufficient free space for normal Windows and game-launcher operation
- Additional notes: Back up important data and test one game before compressing a large library.

## Languages

| Language | Interface | Full audio | Subtitles |
| --- | --- | --- | --- |
| English | Yes | N/A | N/A |
| Spanish - Spain | Yes | N/A | N/A |
| Simplified Chinese | Yes | N/A | N/A |

## Store assets

Generated under `steam/assets/final`:

- Header capsule: 920x430
- Small capsule: 462x174
- Main capsule: 1232x706
- Vertical capsule: 748x896
- Shortcut icon: 256x256
- App icon: 184x184 JPG
- Library capsule: 600x900
- Library hero: 3840x1240, artwork only
- Library logo: transparent PNG
- Library header capsule: 920x430
- Optional page background: 1438x810

The source key art was created with OpenAI image generation using the existing Compact Games icon as the visual reference, then composed and resized locally. It contains no third-party game art or Steam branding. Keep this provenance note for review and rights records. The app itself does not generate AI content at runtime. Confirm the exact Content Survey wording presented in Steamworks and disclose this pre-generated marketing artwork if the survey includes store assets.

Still required: at least five genuine, all-ages-safe, 16:9 screenshots at 1920x1080 or higher from the near-final product build. Suggested shots:

1. Library overview with multiple detected games and total space saved.
2. Game details with the savings estimate and compression choices.
3. Active compression with visible progress and queue.
4. Safety warning for a known incompatible or DirectStorage title.
5. Automation settings and restore-managed-games controls.

Use only game artwork that can legally appear in marketing screenshots. Redact personal Windows usernames, local paths, account names, and API keys.

## Content survey notes

- Mature/adult content: none in the application.
- Violence, sexual content, drugs, gambling, strong language: none in the application UI.
- In-app purchases: none.
- Live-generated AI: none.
- Pre-generated AI: no AI-generated content ships inside the application. See the marketing-art provenance note above and answer the portal's exact question truthfully if it covers store artwork.
- User-generated content: none.
- Online interactions: optional data fetches/report submission only; no chat, multiplayer, or public user profile.

## Review notes for Valve

Compact Games is a Windows-only storage utility, not a game. A reviewer can evaluate discovery without modifying files. For the compression workflow, use a disposable NTFS test folder containing ordinary files, add it as a custom game, estimate savings, compress it, verify the files still open, and then decompress it. The About page identifies Steam as the update owner in this build. No external installer or account is required.
