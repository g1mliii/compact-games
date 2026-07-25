import 'package:compact_games/core/utils/game_name_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeGameName', () {
    test('strips common site and scene suffixes case-insensitively', () {
      expect(
        normalizeGameName('Cyberpunk 2077 - SteamGG.NET'),
        'Cyberpunk 2077',
      );
      expect(
        normalizeGameName('Sample Adventure - steamgg.net'),
        'Sample Adventure',
      );
      expect(
        normalizeGameName('Example Quest - FitGirl Repack'),
        'Example Quest',
      );
      expect(
        normalizeGameName('Demo Racing Game SteamRIP'),
        'Demo Racing Game',
      );
      expect(
        normalizeGameName('Fictional Strategy Game-TENOKE'),
        'Fictional Strategy Game',
      );
      expect(normalizeGameName('Example - DODI Repack'), 'Example');
      expect(normalizeGameName('Example-EMPRESS'), 'Example');
    });

    test('removes trailing versions and junk metadata fragments', () {
      expect(normalizeGameName('Example Game v1.2.3'), 'Example Game');
      expect(normalizeGameName('Example Game - Build 12345'), 'Example Game');
      expect(normalizeGameName('Example Game - Early Access'), 'Example Game');
      expect(normalizeGameName('Example Game - GOG'), 'Example Game');
      expect(normalizeGameName('Example Game [v1.2.3 MULTi7]'), 'Example Game');
      expect(
        normalizeGameName('Example Game (English FitGirl Repack)'),
        'Example Game',
      );
    });

    test('preserves meaningful title text and punctuation', () {
      expect(normalizeGameName('Sample45'), 'Sample45');
      expect(normalizeGameName('Sample-Game 2'), 'Sample-Game 2');
      expect(
        normalizeGameName('Example Adventure (2016)'),
        'Example Adventure (2016)',
      );
      expect(normalizeGameName('CODEX'), 'CODEX');
      expect(normalizeGameName('The Empress'), 'The Empress');
      expect(normalizeGameName('Shadow Rune'), 'Shadow Rune');
      expect(normalizeGameName('Central Plaza'), 'Central Plaza');
    });

    test('collapses noisy separators and whitespace after stripping', () {
      expect(
        normalizeGameName('  Example   Game  |  - SteamRIP  '),
        'Example Game',
      );
    });
  });
}
