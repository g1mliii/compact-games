# PressPlay Development Setup

This document describes the scaffolded project structure and how to get started.

## Project Structure

```
pressplay/
├── rust/                       # Rust backend (compression engine)
│   ├── src/
│   │   ├── api/               # Flutter bridge API surface
│   │   ├── compression/       # Compression algorithms & engine
│   │   ├── safety/            # DirectStorage detection, process checks
│   │   ├── discovery/         # Platform-specific game discovery
│   │   ├── automation/        # Idle detection, file watcher
│   │   └── progress/          # Progress tracking
│   ├── Cargo.toml
│   ├── rust-toolchain.toml
│   └── rustfmt.toml
│
├── lib/                        # Flutter frontend
│   ├── core/
│   │   ├── theme/             # AppColors, AppTypography, AppTheme
│   │   ├── constants/         # App-wide constants
│   │   └── widgets/           # Shared widgets
│   ├── features/              # Feature-first architecture
│   │   ├── games/
│   │   │   ├── presentation/  # HomeScreen, GameCard, etc.
│   │   │   ├── domain/        # Business logic
│   │   │   └── data/          # Data layer
│   │   ├── compression/
│   │   └── settings/
│   ├── providers/             # Riverpod providers
│   ├── services/              # Services (cover art, etc.)
│   ├── app.dart               # Root app widget
│   └── main.dart              # Entry point
│
├── assets/
│   └── fonts/                 # Inter & JetBrains Mono (see README)
│
├── windows/                   # Windows platform code
├── test/                      # Widget & unit tests
├── init.ps1                   # Initialization script
├── flutter_rust_bridge.yaml   # FRB configuration
└── pubspec.yaml
```

## Quick Start

### 1. Prerequisites

Ensure you have:
- Rust 1.80+ (`rustc --version`)
- Flutter 3.30+ (`flutter --version`)
- Windows 10/11 with NTFS filesystem

### 2. Initialize Project

Run the initialization script:

```powershell
.\init.ps1
```

This will:
- Verify prerequisites
- Create directory structure
- Compile Rust code
- Fetch Flutter dependencies

### 3. Verify Build

```powershell
# Check Rust compilation
cd rust
cargo check

# Check Flutter analysis
cd ..
flutter analyze

# Run tests (currently minimal)
flutter test
```

### 4. Run the App

```powershell
flutter run -d windows
```

The app will launch with a minimal UI showing "Game grid coming soon".

## Development Workflow

### Rust Development

1. Edit Rust code in `rust/src/`
2. Run `cargo check` to verify compilation
3. Run `cargo test` to run unit tests
4. Run `cargo clippy` for linting

### Flutter Development

1. Edit Dart code in `lib/`
2. Hot reload is enabled (press `r` in terminal)
3. Run `flutter analyze` for static analysis
4. Run `flutter test` for widget tests

### Flutter Rust Bridge

When you add new Rust functions to expose to Dart:

1. Add `#[flutter_rust_bridge::frb(sync)]` annotation to Rust function
2. Run `flutter_rust_bridge_codegen generate` to regenerate bindings
3. Generated Dart code appears in `lib/src/rust/`
4. Import and use in Dart: `import 'package:pressplay/src/rust/api/minimal.dart';`

**Note:** Bridge codegen is not yet configured. This will be set up in Phase 2.

## Current Status

### Implemented
- ✅ Project structure scaffolded
- ✅ Rust modules created with skeleton implementations
- ✅ Flutter app structure with feature-first organization
- ✅ Theme system (dark mode, colors, typography)
- ✅ Basic HomeScreen placeholder
- ✅ Build verification (both Rust and Flutter compile cleanly)

### Not Yet Implemented
- ⏳ WOF compression API integration (Windows FFI)
- ⏳ Platform game discovery (Steam, Epic, GOG, Xbox)
- ⏳ DirectStorage detection logic
- ⏳ Idle detection system
- ⏳ File system watcher
- ⏳ Progress tracking channels
- ⏳ Flutter Rust Bridge codegen setup
- ⏳ Game grid UI
- ⏳ Cover art fetching (SteamGridDB)
- ⏳ Settings screen
- ⏳ System tray integration

## Next Steps

Follow the implementation plan in `IMPLEMENTATION_PLAN.md` or the spec in `SPEC.md`.

**Week 1 Priority**: Implement the compression engine using Windows WOF API.

1. Research WOF API (`WofSetFileDataLocation`)
2. Implement FFI bindings in `rust/src/compression/engine.rs`
3. Test on a dummy folder with various file types
4. Verify space savings and performance

## Fonts (Optional)

The app references Inter and JetBrains Mono fonts in `pubspec.yaml`. Download them from:

- **Inter**: https://rsms.me/inter/
- **JetBrains Mono**: https://www.jetbrains.com/lp/mono/

Place `.ttf` files in `assets/fonts/` (see `assets/fonts/README.md` for details).

The app will run without these fonts (using system defaults), but the intended design uses these typefaces.

## Troubleshooting

### Rust compilation errors

```powershell
cd rust
cargo clean
cargo check
```

### Flutter dependency issues

```powershell
flutter clean
flutter pub get
```

### Window manager errors on Windows

Ensure you're running on Windows 10/11. The `window_manager` package is Windows-only in this configuration.

## Documentation

- [SPEC.md](SPEC.md) - Complete technical specification
- [AGENTS.md](AGENTS.md) - Development guidelines for AI agents
- [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) - Detailed implementation roadmap
- [README.md](README.md) - Project overview

## Support

For questions or issues:
1. Check `tasks/lessons.md` for common pitfalls
2. Review `AGENTS.md` for coding standards
3. Open an issue on GitHub (when repository is public)
