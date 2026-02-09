# PressPlay 

A beautiful, intelligent game compressor that automatically saves disk space without compromising performance.

## What is PressPlay?

PressPlay is a game manager that silently compresses your games in the background when your system is idle. It features a stunning UI inspired by modern game launchers, complete with cover art and real-time compression statistics.

## Key Features

- **Automatic Compression**: Compresses games when your system is idle
- **Smart Safety**: Detects and protects DirectStorage-enabled games
- **Beautiful UI**: Game launcher aesthetic with cover art from SteamGridDB
- **Multi-Platform**: Supports Steam, Epic Games, GOG, Xbox Game Pass, and custom paths
- **Real-time Progress**: Live compression stats with estimated time remaining
- **Zero Configuration**: Works out of the box with automatic game detection

## Why PressPlay?

Modern games can consume hundreds of gigabytes of storage. Windows NTFS compression can reduce game sizes by 20-60% without noticeable performance impact on most titles. PressPlay makes this process automatic, safe, and beautiful.

## Technology Stack

- **Frontend**: Flutter (beautiful, cross-platform UI)
- **Backend**: Rust (performance, safety, Windows API access)
- **Bridge**: flutter_rust_bridge (type-safe Dart ↔ Rust communication)

## Quick Start

### Prerequisites

- Windows 10/11 (NTFS filesystem required)
- Rust toolchain (https://rustup.rs/)
- Flutter SDK (https://flutter.dev/docs/get-started/install)

### Installation

```cmd
git clone https://github.com/yourusername/pressplay.git
cd pressplay
```

### Build from Source

```cmd
REM Install Rust dependencies
cd rust
cargo build --release

REM Install Flutter dependencies
cd ..
flutter pub get

REM Run the app
flutter run
```

## How It Works

1. **Discovery**: Automatically finds games from Steam, Epic, GOG, and Xbox Game Pass
2. **Monitoring**: Watches for new game installations
3. **Idle Detection**: Waits until your system is idle (low CPU usage, no games running)
4. **Safety Check**: Verifies the game doesn't use DirectStorage
5. **Compression**: Applies Windows NTFS compression using optimal algorithms
6. **Tracking**: Shows you exactly how much space you've saved

## Safety First

PressPlay includes multiple safety mechanisms:

- **DirectStorage Detection**: Automatically detects and skips games that use DirectStorage
- **Running Game Detection**: Never compresses games while they're running
- **Idle-Only Operation**: Only compresses when your system is idle
- **One-Click Decompression**: Easy rollback if needed
- **Checksum Verification**: Ensures game integrity (planned feature)

## Compression Algorithms

- **XPRESS4K**: Fast, moderate compression (default)
- **XPRESS8K**: Balanced speed and compression
- **XPRESS16K**: Better compression, still fast
- **LZX**: Maximum compression (not recommended for games)

## Screenshots

_Coming soon_

## Roadmap

See [SPEC.md](SPEC.md) for the complete development plan.

### Phase 1: Core Engine 
- Compression engine with Windows API integration
- DirectStorage detection
- Game discovery for multiple platforms

### Phase 2: Beautiful UI 
- Game grid with cover art
- Real-time progress tracking
- Settings and configuration

### Phase 3: Automation 
- Intelligent idle detection
- Automatic compression workflow
- System tray integration

### Phase 4: Polish & Release 
- Comprehensive testing
- Performance optimization
- Installer and distribution

## Contributing

Contributions are welcome! Please read [AGENTS.md](AGENTS.md) for development guidelines.

### Development Workflow

1. Check `tasks/todo.md` for current tasks
2. Follow the guidelines in `AGENTS.md`
3. Write tests for new features
4. Run `cargo clippy` and `flutter analyze` before committing
5. Submit a pull request

## Performance Benchmarks

Target performance metrics:

- Compression speed: >100MB/s on SSD
- UI responsiveness: 60fps animations
- Memory usage: <200MB idle, <500MB during compression
- Startup time: <2 seconds

## FAQ

**Q: Will compression slow down my games?**
A: For most games, no. NTFS compression is transparent and modern CPUs decompress faster than SSDs can read. However, DirectStorage-enabled games should NOT be compressed, which is why PressPlay detects and skips them.

**Q: How much space can I save?**
A: Typically 20-60% depending on the game. Games with many text files, scripts, and uncompressed assets compress better.

**Q: Can I decompress a game?**
A: Yes! One-click decompression is available for any compressed game.

**Q: Does this work with game mods?**
A: Yes, compression is transparent to the game and mods.

**Q: What about multiplayer/anti-cheat?**
A: Compression doesn't modify game files, so it's safe with anti-cheat systems.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by [CompactGUI](https://github.com/ImminentFate/CompactGUI)
- Cover art from [SteamGridDB](https://www.steamgriddb.com/)
- Built with [Flutter](https://flutter.dev/) and [Rust](https://www.rust-lang.org/)

## Support

- Report bugs: [GitHub Issues](https://github.com/yourusername/pressplay/issues)
- Feature requests: [GitHub Discussions](https://github.com/yourusername/pressplay/discussions)
- Documentation: [Wiki](https://github.com/yourusername/pressplay/wiki)

---

Made with love for gamers who need more disk space
