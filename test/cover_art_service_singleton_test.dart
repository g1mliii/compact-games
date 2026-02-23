import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pressplay/providers/cover_art/cover_art_provider.dart';

void main() {
  test('CoverArtService provider uses one shared instance', () {
    final containerA = ProviderContainer();
    final containerB = ProviderContainer();
    addTearDown(containerA.dispose);
    addTearDown(containerB.dispose);

    final aFirst = containerA.read(coverArtServiceProvider);
    final aSecond = containerA.read(coverArtServiceProvider);
    final bValue = containerB.read(coverArtServiceProvider);

    expect(identical(aFirst, aSecond), isTrue);
    expect(identical(aFirst, bValue), isTrue);
  });
}
