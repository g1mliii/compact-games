import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_colors.dart';

/// Desktop window chrome wrapper with a themed custom title bar.
class DesktopWindowFrame extends StatelessWidget {
  const DesktopWindowFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          const _PressPlayWindowTitleBar(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _PressPlayWindowTitleBar extends StatefulWidget {
  const _PressPlayWindowTitleBar();

  @override
  State<_PressPlayWindowTitleBar> createState() =>
      _PressPlayWindowTitleBarState();
}

class _PressPlayWindowTitleBarState extends State<_PressPlayWindowTitleBar>
    with WindowListener {
  static const double _titleBarHeight = 32;
  static const ValueKey<String> _titleBarKey = ValueKey<String>(
    'desktopWindowTitleBar',
  );
  static const ValueKey<String> _titleBarDecorationKey = ValueKey<String>(
    'desktopWindowTitleBarDecoration',
  );
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_syncMaximizedState());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: _titleBarKey,
      height: _titleBarHeight,
      child: DecoratedBox(
        key: _titleBarDecorationKey,
        decoration: const BoxDecoration(color: AppColors.surfaceElevated),
        child: Row(
          children: [
            const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
            WindowCaptionButton.minimize(
              brightness: Brightness.dark,
              onPressed: () {
                windowManager.minimize();
              },
            ),
            _isMaximized
                ? WindowCaptionButton.unmaximize(
                    brightness: Brightness.dark,
                    onPressed: () {
                      windowManager.unmaximize();
                    },
                  )
                : WindowCaptionButton.maximize(
                    brightness: Brightness.dark,
                    onPressed: () {
                      windowManager.maximize();
                    },
                  ),
            WindowCaptionButton.close(
              brightness: Brightness.dark,
              onPressed: () {
                windowManager.close();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() => _isMaximized = true);
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() => _isMaximized = false);
    }
  }

  Future<void> _syncMaximizedState() async {
    bool isMaximized;
    try {
      isMaximized = await windowManager.isMaximized();
    } catch (_) {
      return;
    }
    if (!mounted || isMaximized == _isMaximized) {
      return;
    }
    setState(() => _isMaximized = isMaximized);
  }
}
