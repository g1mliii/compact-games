import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/platform_shell_service.dart';

final platformShellServiceProvider = Provider<PlatformShellService>((ref) {
  return const PlatformShellService();
});
