import 'pending_signal_dispatcher.dart';
import 'shell_launch_args.dart';

class ShellActionDispatcher
    extends PendingSignalDispatcher<ShellActionRequest> {
  ShellActionDispatcher._();

  static final ShellActionDispatcher instance = ShellActionDispatcher._();
}
