import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Finds the artwork an installed MSIX/Xbox package declares for itself.
///
/// Some games have no catalog art anywhere — Minecraft ships on Game Pass and
/// is not on Steam at all, so every store lookup returns nothing and the card
/// falls back to a generic plate. The package's own manifest names the tiles
/// Windows shows it with, and those are installed on disk beside the game, so
/// they need no network and cannot be the wrong game's art.
///
/// Returns the largest declared logo that exists, or null when the folder is
/// not a packaged app.
Future<File?> findPackagedAppLogo(String gamePath) async {
  final manifest = await _findManifest(gamePath);
  if (manifest == null) {
    return null;
  }

  final XmlDocument document;
  try {
    // Bounded: a manifest is a few kilobytes, and anything claiming otherwise
    // is not one.
    final raw = await manifest
        .openRead(0, _maxManifestBytes)
        .expand((c) => c)
        .toList();
    // Decoded as UTF-8, which is what an AppxManifest is: reading the bytes as
    // code units turned a leading byte-order mark into `ï»¿` and every
    // non-ASCII name into mojibake, and the parser rejects a document that
    // starts with anything but `<`.
    final text = utf8.decode(raw, allowMalformed: true);
    document = XmlDocument.parse(
      text.startsWith('\u{FEFF}') ? text.substring(1) : text,
    );
  } catch (_) {
    return null;
  }

  final root = manifest.parent;
  // The declared logos almost always live in the same `Assets` folder, and a
  // packaged app's `Assets` routinely holds hundreds of scale variants. Listing
  // it once per logo path meant re-enumerating those hundreds of entries three
  // to five times per game, so each directory is read at most once.
  final listings = <String, List<File>>{};
  File? best;
  var bestLength = 0;
  for (final relative in _declaredLogoPaths(document)) {
    for (final candidate in await _scaleVariantsOf(root, relative, listings)) {
      final length = await candidate.length();
      if (length > bestLength) {
        best = candidate;
        bestLength = length;
      }
    }
  }
  return best;
}

/// Where an installed package keeps its manifest. Xbox games put the payload in
/// a `Content` subfolder; a plain MSIX install has it at the root.
Future<File?> _findManifest(String gamePath) async {
  for (final relative in <String>[
    p.join('Content', 'appxmanifest.xml'),
    'appxmanifest.xml',
    p.join('Content', 'AppxManifest.xml'),
    'AppxManifest.xml',
  ]) {
    final file = File(p.join(gamePath, relative));
    if (await file.exists()) {
      return file;
    }
  }
  return null;
}

/// The logo paths a manifest declares, in no particular order: the caller keeps
/// the largest file it finds, so which one is offered first does not matter.
Iterable<String> _declaredLogoPaths(XmlDocument document) sync* {
  final visual = document
      .findAllElements('uap:VisualElements')
      .followedBy(document.findAllElements('VisualElements'))
      .toList(growable: false);

  for (final element in visual) {
    for (final attribute in const <String>[
      'Square310x310Logo',
      'Wide310x150Logo',
      'Square150x150Logo',
      'Square44x44Logo',
    ]) {
      final value = element.getAttribute(attribute);
      if (value != null && value.isNotEmpty) {
        yield value;
      }
    }
  }

  // `<Properties><Logo>` is the store logo, and the only one some packages
  // declare.
  for (final element in document.findAllElements('Logo')) {
    final value = element.innerText.trim();
    if (value.isNotEmpty) {
      yield value;
    }
  }
}

/// Every file that could satisfy [relative], including the `scale-200` style
/// variants Windows installs beside the base name.
///
/// A manifest names `Assets\Logo.png` while the package ships
/// `Assets\Logo.scale-200.png` and nothing at the bare path, so resolving the
/// literal name alone finds nothing for most packages.
/// [listings] memoizes each directory's contents across the call sequence.
Future<List<File>> _scaleVariantsOf(
  Directory root,
  String relative,
  Map<String, List<File>> listings,
) async {
  final normalized = relative.replaceAll(r'\', p.separator);
  final target = File(p.join(root.path, normalized));
  final directory = target.parent;

  final files = listings[directory.path] ??= await _filesIn(directory);
  final stem = p.basenameWithoutExtension(target.path);
  final extension = p.extension(target.path).toLowerCase();
  final matches = <File>[];
  for (final entity in files) {
    final name = p.basename(entity.path);
    if (!name.toLowerCase().endsWith(extension)) {
      continue;
    }
    final base = p.basenameWithoutExtension(name);
    if (base == stem || base.startsWith('$stem.')) {
      matches.add(entity);
    }
  }
  return matches;
}

Future<List<File>> _filesIn(Directory directory) async {
  try {
    return <File>[
      await for (final entity in directory.list(followLinks: false))
        if (entity is File) entity,
    ];
  } catch (_) {
    // A missing or unreadable folder is just one with no candidates in it.
    return const <File>[];
  }
}

/// A package manifest is a few kilobytes; this is slack, not a budget.
const int _maxManifestBytes = 512 * 1024;
