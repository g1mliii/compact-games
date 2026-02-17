import 'package:flutter/material.dart';

import '../../features/games/presentation/game_details_screen.dart';
import '../../features/games/presentation/home_screen.dart';
import '../../features/games/presentation/inventory_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

abstract final class AppRoutes {
  static const String home = '/home';
  static const String inventory = '/inventory';
  static const String settings = '/settings';
  static const String gamePrefix = '/game/';

  static String gameDetails(String gamePath) {
    return '$gamePrefix${Uri.encodeComponent(gamePath)}';
  }

  static Route<dynamic> onGenerateRoute(RouteSettings settingsArg) {
    final name = settingsArg.name ?? home;
    if (name == home || name == '/') {
      return _desktopInstantRoute<void>(
        builder: (_) => const HomeScreen(),
        settings: const RouteSettings(name: home),
      );
    }

    if (name == inventory) {
      return _desktopInstantRoute<void>(
        builder: (_) => const InventoryScreen(),
        settings: const RouteSettings(name: inventory),
      );
    }

    if (name == settings) {
      return _desktopInstantRoute<void>(
        builder: (_) => const SettingsScreen(),
        settings: const RouteSettings(name: settings),
      );
    }

    if (name.startsWith(gamePrefix)) {
      final encodedPath = name.substring(gamePrefix.length);
      final gamePath = Uri.decodeComponent(encodedPath);
      return _desktopInstantRoute<void>(
        builder: (_) => GameDetailsScreen(gamePath: gamePath),
        settings: RouteSettings(name: name),
      );
    }

    return MaterialPageRoute<void>(
      builder: (_) => const _UnknownRouteScreen(),
      settings: RouteSettings(name: name),
    );
  }

  static Route<T> _desktopInstantRoute<T>({
    required WidgetBuilder builder,
    required RouteSettings settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    );
  }
}

class _UnknownRouteScreen extends StatelessWidget {
  const _UnknownRouteScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not Found')),
      body: const Center(child: Text('Requested route was not found.')),
    );
  }
}
