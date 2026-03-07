import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/app_routes.dart';

class RouteStateObserver extends NavigatorObserver with ChangeNotifier {
  String _currentRouteName = AppRoutes.home;
  bool _notifyScheduled = false;
  bool _disposed = false;

  String get currentRouteName => _currentRouteName;

  void _scheduleNotify() {
    if (_notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (_disposed) {
        return;
      }
      notifyListeners();
    });
  }

  void _updateRoute(Route<dynamic>? route, {Route<dynamic>? fallback}) {
    final nextName =
        route?.settings.name ??
        fallback?.settings.name ??
        _currentRouteName;
    if (nextName == _currentRouteName) {
      return;
    }
    _currentRouteName = nextName;
    _scheduleNotify();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateRoute(route, fallback: previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateRoute(previousRoute, fallback: route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _updateRoute(newRoute, fallback: oldRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateRoute(previousRoute, fallback: route);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final routeStateObserverProvider = ChangeNotifierProvider<RouteStateObserver>((
  ref,
) {
  return RouteStateObserver();
});

final currentRouteNameProvider = Provider<String>((ref) {
  return ref.watch(
    routeStateObserverProvider.select((observer) => observer.currentRouteName),
  );
});

final isHomeRouteProvider = Provider<bool>((ref) {
  final routeName = ref.watch(currentRouteNameProvider);
  return routeName == '/' || routeName == AppRoutes.home;
});
