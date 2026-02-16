import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressplay/app.dart';
import 'package:pressplay/core/widgets/status_badge.dart';
import 'package:pressplay/features/games/presentation/component_test_screen.dart';
import 'package:pressplay/features/games/presentation/widgets/compression_progress_indicator.dart';
import 'package:pressplay/features/games/presentation/widgets/game_card.dart';
import 'package:pressplay/features/games/presentation/widgets/home_game_grid.dart';
import 'package:pressplay/models/compression_algorithm.dart';
import 'package:pressplay/models/compression_progress.dart';
import 'package:pressplay/models/game_info.dart';
import 'package:pressplay/providers/games/game_list_provider.dart';
import 'package:pressplay/services/rust_bridge_service.dart';

void main() {
  testWidgets('App loads without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const PressPlayApp());
    expect(find.text('PressPlay'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Section 2.2 components render in test screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ComponentTestScreen())),
    );

    expect(find.text('Component Test Screen'), findsOneWidget);
    expect(find.byType(GameCard), findsNWidgets(3));
    expect(find.byType(CompressionProgressIndicator), findsOneWidget);
    expect(find.byType(StatusBadge), findsAtLeastNWidgets(3));
  });

  testWidgets('Discovery failure renders error view instead of empty state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            const _FailingRustBridgeService(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Failed to load games'), findsOneWidget);
    expect(find.textContaining('discovery boom'), findsOneWidget);
    expect(find.text('No games found'), findsNothing);
  });
}

class _FailingRustBridgeService implements RustBridgeService {
  const _FailingRustBridgeService();

  @override
  void cancelCompression() {}

  @override
  Stream<CompressionProgress> compressGame({
    required String gamePath,
    required String gameName,
    CompressionAlgorithm algorithm = CompressionAlgorithm.xpress8k,
  }) {
    return const Stream<CompressionProgress>.empty();
  }

  @override
  Future<void> decompressGame(String gamePath) async {}

  @override
  Future<List<GameInfo>> getAllGames() async {
    throw Exception('discovery boom');
  }

  @override
  Future<List<GameInfo>> getAllGamesQuick() async {
    throw Exception('discovery boom');
  }

  @override
  Future<GameInfo?> hydrateGame({
    required String gamePath,
    required String gameName,
    required Platform platform,
  }) async {
    throw Exception('discovery boom');
  }

  @override
  CompressionProgress? getCompressionProgress() {
    return null;
  }

  @override
  Future<double> getCompressionRatio(String folderPath) async {
    return 1.0;
  }

  @override
  String initApp() {
    return 'ok';
  }

  @override
  bool isAutoCompressionRunning() {
    return false;
  }

  @override
  bool isDirectStorage(String gamePath) {
    return false;
  }

  @override
  Future<List<GameInfo>> scanCustomFolder(String path) async {
    return const [];
  }

  @override
  Future<void> startAutoCompression() async {}

  @override
  void stopAutoCompression() {}
}
