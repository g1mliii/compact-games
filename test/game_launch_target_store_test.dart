import 'package:compact_games/services/game_launch_target_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'launch targets persist by normalized case-insensitive game path',
    () async {
      const store = GameLaunchTargetStore();
      await store.write(r'C:\Games\Example', r'C:\Games\Example\Example.exe');

      expect(
        await store.read(r'c:/games/example/'),
        r'C:\Games\Example\Example.exe',
      );
    },
  );

  test('removing a launch target leaves it unresolved', () async {
    const store = GameLaunchTargetStore();
    await store.write(r'C:\Games\Example', r'C:\Games\Example\Example.exe');

    await store.remove(r'c:\games\example');

    expect(await store.read(r'C:\Games\Example'), isNull);
  });
}
