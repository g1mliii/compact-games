import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/providers/games/library_aggregate_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const int _oneGiB = 1024 * 1024 * 1024;

GameInfo _game({
  required String name,
  required String path,
  Platform platform = Platform.steam,
  int sizeBytes = _oneGiB,
  int? compressedSize,
  bool isCompressed = false,
  bool isDirectStorage = false,
  bool isUnsupported = false,
  DateTime? lastCompressedAt,
}) {
  return GameInfo(
    name: name,
    path: path,
    platform: platform,
    sizeBytes: sizeBytes,
    compressedSize: compressedSize,
    isCompressed: isCompressed,
    isDirectStorage: isDirectStorage,
    isUnsupported: isUnsupported,
    lastCompressedAt: lastCompressedAt,
  );
}

void main() {
  group('buildLibraryAggregate', () {
    test('empty library returns the canonical empty aggregate', () {
      final aggregate = buildLibraryAggregate(const <GameInfo>[]);

      expect(identical(aggregate, LibraryAggregate.empty), isTrue);
      expect(aggregate.totalGames, 0);
      expect(aggregate.compressedCount, 0);
      expect(aggregate.actualBytesSaved, 0);
      expect(aggregate.largestInstallPath, isNull);
      expect(aggregate.biggestSaverPath, isNull);
      expect(aggregate.mostRecentCompressedPath, isNull);
      expect(aggregate.reclaimableBytes, 0);
    });

    test('counts every discovered game, not only compressible ones', () {
      final aggregate = buildLibraryAggregate(<GameInfo>[
        _game(name: 'Ready', path: r'C:\a'),
        _game(
          name: 'Compressed',
          path: r'C:\b',
          sizeBytes: 10 * _oneGiB,
          compressedSize: 8 * _oneGiB,
          isCompressed: true,
        ),
        _game(name: 'DirectStorage', path: r'C:\c', isDirectStorage: true),
        _game(name: 'Unsupported', path: r'C:\d', isUnsupported: true),
      ]);

      expect(aggregate.totalGames, 4);
      expect(aggregate.compressedCount, 1);
      // Only the plain game is compressible; DirectStorage and unsupported
      // entries are excluded from the ready set.
      expect(aggregate.readyCount, 1);
      expect(aggregate.firstReadyPath, r'C:\a');
    });

    test('space saved is measured, never estimated', () {
      final aggregate = buildLibraryAggregate(<GameInfo>[
        _game(
          name: 'A',
          path: r'C:\a',
          sizeBytes: 10 * _oneGiB,
          compressedSize: 7 * _oneGiB,
          isCompressed: true,
        ),
        _game(
          name: 'B',
          path: r'C:\b',
          sizeBytes: 20 * _oneGiB,
          compressedSize: 15 * _oneGiB,
          isCompressed: true,
        ),
      ]);

      expect(aggregate.actualBytesSaved, 8 * _oneGiB);
      expect(aggregate.biggestSaverPath, r'C:\b');
      expect(aggregate.biggestSaverBytes, 5 * _oneGiB);
    });

    test('largest install spans the whole library including compressed', () {
      final aggregate = buildLibraryAggregate(<GameInfo>[
        _game(name: 'Small', path: r'C:\small', sizeBytes: 5 * _oneGiB),
        _game(
          name: 'Huge',
          path: r'C:\huge',
          sizeBytes: 200 * _oneGiB,
          compressedSize: 190 * _oneGiB,
          isCompressed: true,
        ),
        _game(
          name: 'Blocked',
          path: r'C:\blocked',
          sizeBytes: 90 * _oneGiB,
          isUnsupported: true,
        ),
      ]);

      expect(aggregate.largestInstallPath, r'C:\huge');
      expect(aggregate.largestInstallBytes, 200 * _oneGiB);
    });

    test('most recently compressed uses the dedicated timestamp', () {
      final older = DateTime.utc(2026, 1, 1);
      final newer = DateTime.utc(2026, 6, 1);
      final aggregate = buildLibraryAggregate(<GameInfo>[
        _game(
          name: 'Older',
          path: r'C:\older',
          compressedSize: 1,
          isCompressed: true,
          lastCompressedAt: older,
        ),
        _game(
          name: 'Newer',
          path: r'C:\newer',
          compressedSize: 1,
          isCompressed: true,
          lastCompressedAt: newer,
        ),
      ]);

      expect(aggregate.mostRecentCompressedPath, r'C:\newer');
      expect(aggregate.mostRecentCompressedAt, newer);
    });

    test('ties resolve deterministically regardless of input order', () {
      final at = DateTime.utc(2026, 3, 3);
      final forwards = <GameInfo>[
        _game(
          name: 'Alpha',
          path: r'C:\alpha',
          sizeBytes: 4 * _oneGiB,
          compressedSize: 3 * _oneGiB,
          isCompressed: true,
          lastCompressedAt: at,
        ),
        _game(
          name: 'Beta',
          path: r'C:\beta',
          sizeBytes: 4 * _oneGiB,
          compressedSize: 3 * _oneGiB,
          isCompressed: true,
          lastCompressedAt: at,
        ),
      ];
      final backwards = forwards.reversed.toList();

      final a = buildLibraryAggregate(forwards);
      final b = buildLibraryAggregate(backwards);

      expect(a.largestInstallPath, b.largestInstallPath);
      expect(a.biggestSaverPath, b.biggestSaverPath);
      expect(a.mostRecentCompressedPath, b.mostRecentCompressedPath);
      // Lowered path ascending is the documented tie-break.
      expect(a.largestInstallPath, r'C:\alpha');
      expect(a.biggestSaverPath, r'C:\alpha');
      expect(a.mostRecentCompressedPath, r'C:\alpha');
    });

    test('mixed-platform libraries aggregate without platform bias', () {
      final aggregate = buildLibraryAggregate(<GameInfo>[
        _game(name: 'S', path: r'C:\s', platform: Platform.steam),
        _game(name: 'E', path: r'C:\e', platform: Platform.epicGames),
        _game(name: 'G', path: r'C:\g', platform: Platform.gogGalaxy),
        _game(name: 'X', path: r'C:\x', platform: Platform.xboxGamePass),
      ]);

      expect(aggregate.totalGames, 4);
      expect(aggregate.readyCount, 4);
    });

    test(
      'learned savings ratio drives reclaimable bytes and stays clamped',
      () {
        // A 50% observed saving is above the clamp ceiling of 0.32.
        final aggregate = buildLibraryAggregate(<GameInfo>[
          _game(
            name: 'Saver',
            path: r'C:\saver',
            sizeBytes: 100 * _oneGiB,
            compressedSize: 50 * _oneGiB,
            isCompressed: true,
          ),
          _game(name: 'Ready', path: r'C:\ready', sizeBytes: 100 * _oneGiB),
        ]);

        expect(aggregate.learnedSavingsRatio, 0.32);
        expect(aggregate.reclaimableBytes, (100 * _oneGiB * 0.32).round());
      },
    );

    test('a library with no compressed games falls back to the estimate', () {
      final aggregate = buildLibraryAggregate(<GameInfo>[
        _game(name: 'Ready', path: r'C:\ready', sizeBytes: 100 * _oneGiB),
      ]);

      expect(aggregate.learnedSavingsRatio, 0.18);
      expect(aggregate.compressedCount, 0);
      expect(aggregate.actualBytesSaved, 0);
    });

    test('compressed games that saved nothing yield no biggest saver', () {
      final aggregate = buildLibraryAggregate(<GameInfo>[
        _game(
          name: 'NoGain',
          path: r'C:\nogain',
          sizeBytes: 10 * _oneGiB,
          compressedSize: 10 * _oneGiB,
          isCompressed: true,
        ),
      ]);

      expect(aggregate.compressedCount, 1);
      expect(aggregate.actualBytesSaved, 0);
      expect(aggregate.biggestSaverPath, isNull);
    });
  });
}
