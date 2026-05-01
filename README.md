Compact Games

Free up storage by compressing games safely on Windows.

Compact Games helps you reclaim disk space from large game libraries using Windows NTFS compression. It finds your installed games, shows how much space you may be able to save, and lets you compress or decompress games with simple controls.

What Compact Games Does

Modern games can take up a huge amount of storage. Compact Games makes it easier to reduce that footprint without manually running command-line tools or hunting through install folders.

With Compact Games, you can:

Automatically find games from supported launchers

Compress selected games to save disk space

Decompress games later with one click

See progress while compression is running

Track how much space you have saved

Avoid compressing games that may not be safe to compress

Download

Download the latest Windows release from:

https://g1mliii.github.io/compact-games/

After downloading, run the installer or .exe file and follow the on-screen steps.

Requirements

Compact Games is built for Windows PCs.

You need:

Windows 10 or Windows 11

An NTFS-formatted drive

Enough free space for normal Windows operation

Game folders that your Windows account can access

Compact Games is not intended for macOS or Linux.

Supported Game Sources

Compact Games can detect games from common launchers and folders, including:

Steam

Epic Games

GOG

Xbox Game Pass

Custom game folders

You can also add your own paths if a game is installed somewhere else.

How to Use Compact Games

1. Open the app

Launch Compact Games after installation.

2. Let it scan your games

The app will look for supported game libraries and list the games it finds.

3. Review your games

Each game will show information such as its location, size, compression state, and estimated savings when available.

4. Choose what to compress

Select the game or folder you want to compress.

5. Start compression

Compact Games will compress the selected game using Windows NTFS compression and show live progress.

6. Decompress whenever needed

You can restore a compressed game back to its original uncompressed state from inside the app.

Is It Safe?

Compact Games uses Windows NTFS compression, which does not rewrite or modify the contents of your game files. Windows transparently decompresses files when games read them.

The app also includes safety checks such as:

Skipping games that appear to use DirectStorage

Avoiding games that are currently running

Compressing only when it is safe to do so

Allowing one-click decompression

That said, every PC setup is different. If you are unsure, start with one game and test it before compressing a large library.

Will Compression Affect Performance?

For many games, the performance impact is small or unnoticeable because modern CPUs can decompress files quickly. Some games may even load similarly depending on your drive and system.

However, compression may not be ideal for every game. Games that rely heavily on DirectStorage, very high-speed asset streaming, or unusual file layouts may not be good candidates.

Compact Games tries to detect and avoid risky cases, but you can always decompress a game if needed.

How Much Space Can I Save?

Savings depend on the game.

Games with many text files, scripts, uncompressed assets, or loose files often compress well. Games that already use compressed archives may save less space.

Typical savings can vary widely, so the app shows estimates and actual saved space where possible.

Compression Modes

Compact Games supports multiple Windows compression algorithms:

XPRESS4K — Fast compression, good default choice

XPRESS8K — Balanced speed and savings

XPRESS16K — Better compression, slower than XPRESS4K

LZX — Maximum compression, usually not recommended for games

Most users should use the default setting unless they know they want a different mode.

Frequently Asked Questions

Does Compact Games modify my games?

No. NTFS compression changes how files are stored on disk, but it does not change the game files themselves.

Can I still update my games?

Yes. Game launchers should still be able to update compressed games normally.

Can I use this with mods?

Usually yes. Compression is transparent to Windows, the game, and most mods.

Is this safe with anti-cheat?

NTFS compression does not alter game file contents, so it is generally safe. If you run into issues with a specific game, decompress it.

Can I undo compression?

Yes. You can decompress any compressed game from inside the app.

Should I compress every game?

No. Some games are better left uncompressed, especially games that use DirectStorage or stream large assets aggressively. Compact Games helps you identify safer choices.

Troubleshooting

A game was not detected

Try adding its install folder manually through custom paths.

Compression failed

Check that:

The game is not running

You have permission to access the folder

The drive uses NTFS

Your antivirus or security software is not blocking the app

A game behaves strangely after compression

Decompress the game from inside Compact Games, then restart the game launcher and verify the game files if needed.

For Developers

Compact Games is built with:

Flutter for the interface

Rust for performance-sensitive Windows functionality

flutter_rust_bridge for Dart ↔ Rust communication

To build from source:

git clone https://github.com/g1mliii/compact-games.git
cd compact-games

Install the required Rust and Flutter toolchains before building.

Before contributing, please:

Run cargo clippy

Run flutter analyze

Add tests for new functionality where appropriate

Credits

Compact Games is inspired by tools like CompactGUI.

Optional runtime compression estimates may use community data from CompactGUI by IridiumIO. That data is GPL-3.0 licensed and fetched at runtime rather than bundled directly in the app binary.

Cover art may be provided by SteamGridDB through the built-in cover service or through your own optional SteamGridDB API key.

License

MIT License. See LICENSE for details.

Support

Report bugs through GitHub Issues

Request features through GitHub Discussions

Check the project wiki for additional documentation

