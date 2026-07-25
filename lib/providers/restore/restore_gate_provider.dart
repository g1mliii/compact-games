import 'package:flutter_riverpod/flutter_riverpod.dart';

final restoreGateProvider = NotifierProvider<RestoreGateNotifier, bool>(
  RestoreGateNotifier.new,
);

class RestoreGateNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void pauseCompressionAdmission() {
    state = true;
  }

  void resumeCompressionAdmission() {
    state = false;
  }
}
