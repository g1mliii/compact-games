import 'package:compact_games/app.dart';
import 'package:compact_games/core/lifecycle/app_window_visibility.dart';
import 'package:compact_games/core/navigation/app_routes.dart';
import 'package:compact_games/features/settings/presentation/settings_screen.dart';
import 'package:compact_games/models/app_settings.dart';
import 'package:compact_games/providers/games/game_list_provider.dart';
import 'package:compact_games/providers/settings/settings_persistence.dart';
import 'package:compact_games/providers/settings/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/noop_rust_bridge_service.dart';

void main() {
  setUp(() {
    appWindowVisibilityController.markVisible();
  });

  tearDown(() {
    appWindowVisibilityController.markVisible();
  });

  testWidgets('tray-hidden state preserves navigator route stack on restore', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            const NoOpRustBridgeService(),
          ),
          settingsPersistenceProvider.overrideWithValue(
            _MemorySettingsPersistence(
              const AppSettings(autoCheckUpdates: false),
            ),
          ),
        ],
        child: const CompactGamesApp(),
      ),
    );
    await tester.pumpAndSettle();

    final initialNavigator = tester.state<NavigatorState>(
      find.byType(Navigator),
    );
    initialNavigator.pushNamed(AppRoutes.settings);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(initialNavigator.canPop(), isTrue);

    appWindowVisibilityController.markHiddenToTray();
    await tester.pump();

    expect(find.byType(MaterialApp, skipOffstage: false), findsOneWidget);

    appWindowVisibilityController.markVisible();
    await tester.pumpAndSettle();

    final restoredNavigator = tester.state<NavigatorState>(
      find.byType(Navigator),
    );
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(restoredNavigator.canPop(), isTrue);
  });
}

class _MemorySettingsPersistence implements SettingsPersistence {
  _MemorySettingsPersistence(this._current);

  AppSettings _current;

  @override
  Future<AppSettings> load() async => _current;

  @override
  Future<void> save(AppSettings settings) async {
    _current = settings;
  }
}
