part of 'tray_service.dart';

class _TrayIconCache {
  String? testIconPathOverride;

  Future<String> resolve() async {
    final testPath = testIconPathOverride;
    if (testPath != null) return testPath;
    return _packagedIconPath(Platform.resolvedExecutable);
  }

  Future<void> deleteCachedFile() async {}

  static String _packagedIconPath(String executablePath) {
    return p.join(
      p.dirname(executablePath),
      'data',
      'flutter_assets',
      'assets',
      'icons',
      'app_icon.ico',
    );
  }
}
