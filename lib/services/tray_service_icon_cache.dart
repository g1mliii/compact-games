part of 'tray_service.dart';

class _TrayIconCache {
  String? _cachedIconPath;
  String? testIconPathOverride;

  Future<String> resolve() async {
    final testPath = testIconPathOverride;
    if (testPath != null) return testPath;
    final cachedPath = _cachedIconPath;
    if (cachedPath != null) return cachedPath;

    final data = await rootBundle.load('assets/icons/app_icon.ico');
    final tempDir = await getTemporaryDirectory();
    final iconFile = File('${tempDir.path}/pressplay_tray.ico');
    await iconFile.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    _cachedIconPath = iconFile.path;
    return _cachedIconPath!;
  }

  Future<void> deleteCachedFile() async {
    final path = _cachedIconPath;
    _cachedIconPath = null;
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }
}
