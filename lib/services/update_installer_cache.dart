import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef UpdateDirectoryResolver = Future<Directory> Function();

/// Owns downloaded standalone installers under the app support directory.
///
/// This is the single owner of the updater directory and its filename scheme;
/// the update provider asks for paths here rather than rebuilding them, so a
/// rename cannot silently turn cleanup into a no-op.
class UpdateInstallerCache {
  UpdateInstallerCache({UpdateDirectoryResolver? directoryResolver})
    : _directoryResolver = directoryResolver ?? _defaultUpdateDirectory;

  final UpdateDirectoryResolver _directoryResolver;

  /// The app support path cannot change within a process, and resolving it on
  /// Windows reads the executable's version resource off disk — so resolve once
  /// and share the future across every caller.
  Future<Directory>? _updateDirectory;

  static const String installerPrefix = 'CompactGames-Setup-';

  /// Matches both finished installers and interrupted `.tmp` remnants. The
  /// downloader only renames a `.tmp` to its final `.exe` name once the
  /// SHA-256 matches, so an existing `.exe` is verified by construction.
  static final RegExp _updaterOwnedName = RegExp(
    '^${RegExp.escape(installerPrefix)}'
    r'[A-Za-z0-9._+-]+\.(?:exe|tmp)$',
    caseSensitive: false,
  );

  static String installerFileName(String version) =>
      '$installerPrefix$version.exe';

  Future<Directory> _resolveDirectory() =>
      _updateDirectory ??= _directoryResolver();

  /// Absolute path the installer for [version] is downloaded to.
  Future<String> installerPathFor(String version) async {
    final updateDirectory = await _resolveDirectory();
    return p.join(updateDirectory.path, installerFileName(version));
  }

  /// Path of an already-downloaded, checksum-verified installer for [version],
  /// or null when nothing usable is cached.
  Future<String?> findVerifiedInstaller(String version) async {
    final path = await installerPathFor(version);
    return await File(path).exists() ? path : null;
  }

  /// Deletes superseded installers and interrupted-download remnants.
  ///
  /// Only regular files with updater-owned names directly inside the updater
  /// directory are eligible. [keepVersion] preserves the installer for a version
  /// that is still current — whether it was just downloaded or carried over from
  /// an earlier session — so postponing an install never costs a re-download.
  Future<int> deleteStaleInstallers({String? keepVersion}) async {
    final updateDirectory = await _resolveDirectory();
    if (!await updateDirectory.exists()) {
      return 0;
    }

    final keepName = keepVersion == null
        ? null
        : installerFileName(keepVersion).toLowerCase();
    var deleted = 0;

    // `followLinks: false` types each entry during enumeration, so a directory
    // or link wearing an installer name arrives as something other than a File.
    await for (final entity in updateDirectory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = p.basename(entity.path);
      if (!_updaterOwnedName.hasMatch(name)) {
        continue;
      }
      if (keepName != null && name.toLowerCase() == keepName) {
        continue;
      }

      try {
        await entity.delete();
        deleted += 1;
      } on FileSystemException catch (error) {
        debugPrint('[update] Failed to remove stale installer: $error');
      }
    }

    return deleted;
  }

  static Future<Directory> _defaultUpdateDirectory() async {
    final appData = await getApplicationSupportDirectory();
    return Directory(p.join(appData.path, 'updates'));
  }
}
