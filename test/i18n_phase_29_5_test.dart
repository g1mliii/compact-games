import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pressplay/app.dart';
import 'package:pressplay/core/localization/app_locale.dart';
import 'package:pressplay/core/utils/date_time_format.dart';
import 'package:pressplay/features/games/presentation/widgets/compression_progress_indicator.dart';
import 'package:pressplay/features/games/presentation/widgets/game_details/details_info_card.dart';
import 'package:pressplay/features/settings/presentation/sections/language_section.dart';
import 'package:pressplay/l10n/app_localizations.dart';
import 'package:pressplay/models/app_settings.dart';
import 'package:pressplay/models/compression_algorithm.dart';
import 'package:pressplay/models/game_info.dart';
import 'package:pressplay/providers/compression/compression_progress_provider.dart';
import 'package:pressplay/providers/compression/compression_state.dart';
import 'package:pressplay/providers/localization/locale_pack_provider.dart';
import 'package:pressplay/providers/localization/locale_provider.dart';
import 'package:pressplay/providers/settings/settings_persistence.dart';
import 'package:pressplay/providers/settings/settings_provider.dart';
import 'package:pressplay/services/locale_pack_persistence.dart';
import 'package:pressplay/services/tray_service.dart';

import 'support/localized_test_app.dart';

class _MemorySettingsPersistence implements SettingsPersistence {
  _MemorySettingsPersistence([this.current = const AppSettings()]);

  AppSettings current;

  @override
  Future<AppSettings> load() async => current;

  @override
  Future<void> save(AppSettings settings) async {
    current = settings;
  }
}

class _MemoryLocalePackPersistence implements LocalePackPersistence {
  _MemoryLocalePackPersistence([Set<String>? current])
    : current = current ?? <String>{};

  Set<String> current;

  @override
  Future<Set<String>> loadInstalledPackTags() async => current;

  @override
  Future<void> saveInstalledPackTags(Set<String> tags) async {
    final sanitized = <String>{};
    for (final tag in tags) {
      final canonical = canonicalLocaleTag(tag);
      final definition = appLocaleDefinitionForTag(canonical);
      if (canonical == null || definition == null || definition.isBundled) {
        continue;
      }
      sanitized.add(canonical);
    }
    current = sanitized;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('en');
    await initializeDateFormatting('es');
    await initializeDateFormatting('zh');
  });

  test('AppSettings JSON round-trip preserves localeTag', () {
    const settings = AppSettings(localeTag: 'es');

    final roundTrip = AppSettings.fromJson(settings.toJson());

    expect(roundTrip.localeTag, 'es');
  });

  test('resolveSupportedAppLocale honors preferred and system locales', () {
    expect(
      resolveSupportedAppLocale(
        preferredLocaleTag: null,
        systemLocale: const Locale('es', 'MX'),
      ),
      const Locale('es'),
    );
    expect(
      resolveSupportedAppLocale(
        preferredLocaleTag: 'es',
        systemLocale: const Locale('en'),
      ),
      const Locale('es'),
    );
    expect(
      resolveSupportedAppLocale(
        preferredLocaleTag: 'fr-CA',
        systemLocale: const Locale('fr', 'CA'),
      ),
      const Locale('en'),
    );
    expect(
      resolveSupportedAppLocale(
        preferredLocaleTag: 'zh-CN',
        systemLocale: const Locale('en'),
      ),
      const Locale('zh'),
    );
    expect(
      resolveSupportedAppLocale(
        preferredLocaleTag: null,
        systemLocale: const Locale('zh', 'CN'),
      ),
      const Locale('zh'),
    );
  });

  test('locale registry separates bundled and future pack locales', () {
    final selectable = buildSelectableAppLocaleDefinitions();
    final selectableTags = selectable.map((locale) => locale.tag).toList();
    final installable = buildInstallableAppLocaleDefinitions();
    final installableTags = installable.map((locale) => locale.tag).toList();

    expect(selectableTags, containsAll(<String>['en', 'es', 'zh-CN']));
    expect(selectableTags, isNot(contains('pt-BR')));
    expect(selectableTags, isNot(contains('de')));
    expect(selectableTags, isNot(contains('fr')));
    expect(installableTags, containsAll(<String>['pt-BR', 'de', 'fr']));
  });

  test(
    'installed locale pack persistence only keeps non-bundled tags',
    () async {
      final persistence = _MemoryLocalePackPersistence();

      await persistence.saveInstalledPackTags(<String>{'pt-BR', 'en', 'zh-CN'});

      expect(await persistence.loadInstalledPackTags(), <String>{'pt-BR'});
    },
  );

  test('tray presentation uses localized labels and tooltips', () {
    const status = TrayStatus(
      mode: TrayStatusMode.compressing,
      activeGameName: 'Halo',
      progressPercent: 42,
      autoCompressionEnabled: false,
      strings: TrayStrings(
        openAppLabel: 'Abrir PressPlay',
        pauseAutoCompressionLabel: 'Pausar compresión automática',
        resumeAutoCompressionLabel: 'Reanudar compresión automática',
        quitLabel: 'Salir',
        compressingLabel: 'Comprimiendo',
        pausedStatusLabel: 'Pausado',
        errorStatusLabel: 'Error',
      ),
    );

    final items = buildTrayMenuItems(
      status: status,
      hasToggleHandler: true,
      toggleInFlight: false,
    );

    expect(items[2].label, 'Comprimiendo: Halo');
    expect(items[4].label, 'Abrir PressPlay');
    expect(items[5].label, 'Reanudar compresión automática');
    expect(trayTooltipForStatus(status), 'PressPlay - Comprimiendo Halo (42%)');
  });

  test('formatLocalMonthDayTime uses locale-aware month formatting', () {
    final value = DateTime(2026, 3, 5, 13, 4);
    final english = formatLocalMonthDayTime(value, locale: const Locale('en'));
    final spanish = formatLocalMonthDayTime(value, locale: const Locale('es'));

    expect(english, isNot(spanish));
    expect(english, contains('Mar'));
    expect(spanish.toLowerCase(), contains('mar'));
    expect(spanish, startsWith('5'));
  });

  testWidgets(
    'language selector is fixed-height, opens immediately, updates provider, and persists',
    (tester) async {
      final persistence = _MemorySettingsPersistence();
      final container = ProviderContainer(
        overrides: [
          settingsPersistenceProvider.overrideWithValue(persistence),
          localePackPersistenceProvider.overrideWithValue(
            _MemoryLocalePackPersistence(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(
            home: const Scaffold(body: LanguageSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final selectorFinder = find.byType(InputDecorator).first;
      expect(tester.getSize(selectorFinder).height, 40);
      expect(find.text('System default'), findsOneWidget);

      await tester.tap(selectorFinder);
      await tester.pump();

      expect(find.text('Spanish'), findsOneWidget);
      expect(find.text('Chinese (Simplified)'), findsOneWidget);
      expect(find.text('Português (Brasil)'), findsNothing);
      final spanishInkWell = tester.widget<InkWell>(
        find.ancestor(of: find.text('Spanish'), matching: find.byType(InkWell)),
      );
      expect(spanishInkWell.hoverColor, isNot(Colors.transparent));
      expect(spanishInkWell.focusColor, isNot(Colors.transparent));
      expect(spanishInkWell.splashColor, Colors.transparent);
      expect(spanishInkWell.highlightColor, Colors.transparent);

      await tester.tap(find.text('Spanish'));
      await tester.pump();

      expect(
        container.read(settingsProvider).valueOrNull?.settings.localeTag,
        'es',
      );

      await tester.pump(const Duration(milliseconds: 600));
      expect(persistence.current.localeTag, 'es');

      final reloadedContainer = ProviderContainer(
        overrides: [settingsPersistenceProvider.overrideWithValue(persistence)],
      );
      addTearDown(reloadedContainer.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: reloadedContainer,
          child: buildLocalizedTestApp(
            home: const Scaffold(body: LanguageSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Spanish'), findsOneWidget);
    },
  );

  testWidgets(
    'language selector subtree stays stable for unrelated settings updates',
    (tester) async {
      final persistence = _MemorySettingsPersistence();
      final container = ProviderContainer(
        overrides: [
          settingsPersistenceProvider.overrideWithValue(persistence),
          localePackPersistenceProvider.overrideWithValue(
            _MemoryLocalePackPersistence(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(
            home: const Scaffold(body: LanguageSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final selectorHostFinder = find.byKey(
        const ValueKey<String>('settingsLanguageSelector'),
      );
      final initialSelectorHost = tester.widget<SizedBox>(selectorHostFinder);

      container
          .read(settingsProvider.notifier)
          .updateAlgorithm(CompressionAlgorithm.lzx);
      await tester.pump();

      final updatedSelectorHost = tester.widget<SizedBox>(selectorHostFinder);
      expect(identical(updatedSelectorHost, initialSelectorHost), isTrue);
      expect(
        container.read(settingsProvider).valueOrNull?.settings.algorithm,
        CompressionAlgorithm.lzx,
      );

      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'locale pack catalog stays off the selector until runtime pack loading exists',
    (tester) async {
      final persistence = _MemorySettingsPersistence();
      final localePackPersistence = _MemoryLocalePackPersistence();
      final container = ProviderContainer(
        overrides: [
          settingsPersistenceProvider.overrideWithValue(persistence),
          localePackPersistenceProvider.overrideWithValue(
            localePackPersistence,
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(installedLocalePackTagsProvider.notifier)
          .markInstalled('pt-BR');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(
            home: const Scaffold(body: LanguageSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(InputDecorator).first);
      await tester.pump();

      expect(find.text('Chinese (Simplified)'), findsOneWidget);
      expect(find.text('Português (Brasil)'), findsNothing);
      expect(localePackPersistence.current, contains('pt-BR'));
    },
  );

  testWidgets(
    'unsupported persisted locale falls back to system default in the selector',
    (tester) async {
      final persistence = _MemorySettingsPersistence(
        const AppSettings(localeTag: 'pt-BR'),
      );
      final container = ProviderContainer(
        overrides: [
          settingsPersistenceProvider.overrideWithValue(persistence),
          localePackPersistenceProvider.overrideWithValue(
            _MemoryLocalePackPersistence(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(
            home: const Scaffold(body: LanguageSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(effectiveLocaleProvider), const Locale('en'));
      expect(find.text('System default'), findsOneWidget);
      expect(find.text('Português (Brasil)'), findsNothing);
    },
  );

  testWidgets(
    'PressPlayApp applies persisted Spanish locale to home and settings',
    (tester) async {
      final spanishL10n = lookupAppLocalizations(const Locale('es'));
      final persistence = _MemorySettingsPersistence(
        const AppSettings(localeTag: 'es'),
      );
      final container = ProviderContainer(
        overrides: [
          settingsPersistenceProvider.overrideWithValue(persistence),
          localePackPersistenceProvider.overrideWithValue(
            _MemoryLocalePackPersistence(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PressPlayApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(spanishL10n.homeHeaderTagline), findsOneWidget);

      await tester.tap(find.byTooltip('Abrir configuración'));
      await tester.pumpAndSettle();

      expect(find.text('Configuración'), findsOneWidget);
    },
  );

  testWidgets(
    'PressPlayApp applies persisted Spanish locale to inventory shell',
    (tester) async {
      final persistence = _MemorySettingsPersistence(
        const AppSettings(localeTag: 'es'),
      );
      final container = ProviderContainer(
        overrides: [
          settingsPersistenceProvider.overrideWithValue(persistence),
          localePackPersistenceProvider.overrideWithValue(
            _MemoryLocalePackPersistence(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PressPlayApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Abrir inventario de compresión'));
      await tester.pumpAndSettle();

      expect(find.text('Inventario de compresión'), findsOneWidget);
    },
  );

  testWidgets(
    'Spanish locale reaches compression activity and game details copy',
    (tester) async {
      final persistence = _MemorySettingsPersistence();
      final container = ProviderContainer(
        overrides: [
          settingsPersistenceProvider.overrideWithValue(persistence),
          localePackPersistenceProvider.overrideWithValue(
            _MemoryLocalePackPersistence(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final game = GameInfo(
        name: 'Halo',
        path: r'C:\Games\Halo',
        platform: Platform.steam,
        sizeBytes: 120 * 1024 * 1024 * 1024,
        compressedSize: 90 * 1024 * 1024 * 1024,
        isCompressed: true,
        lastCompressedAt: DateTime(2026, 3, 4, 16, 5),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(
            locale: const Locale('es'),
            home: Scaffold(
              body: Column(
                children: [
                  CompressionProgressIndicator(
                    activity: CompressionActivityUiModel(
                      type: CompressionJobType.compression,
                      gameName: 'Halo',
                      filesProcessed: 5,
                      filesTotal: 10,
                      percent: 50,
                      bytesDelta: 2147483648,
                      hasKnownFileTotal: true,
                      isFileCountApproximate: false,
                      canCancel: true,
                      etaSeconds: 240,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: GameDetailsInfoCard(
                        game: game,
                        currentSize: 90 * 1024 * 1024 * 1024,
                        savedBytes: 30 * 1024 * 1024 * 1024,
                        savingsPercent: '25.0',
                        lastCompressedText: '4 mar, 16:05',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Comprimiendo'), findsOneWidget);
      expect(find.text('Quedan 4 min'), findsOneWidget);
      expect(find.text('Ahorra 2.0 GB'), findsOneWidget);
      expect(find.text('Plataforma'), findsOneWidget);
      expect(find.text('Ruta de instalación'), findsOneWidget);
      expect(find.textContaining('Comprimido 4 mar, 16:05'), findsOneWidget);
    },
  );

  testWidgets('PressPlayApp applies persisted Chinese locale to home', (
    tester,
  ) async {
    final chineseL10n = lookupAppLocalizations(const Locale('zh'));
    final persistence = _MemorySettingsPersistence(
      const AppSettings(localeTag: 'zh-CN'),
    );
    final container = ProviderContainer(
      overrides: [
        settingsPersistenceProvider.overrideWithValue(persistence),
        localePackPersistenceProvider.overrideWithValue(
          _MemoryLocalePackPersistence(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PressPlayApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(chineseL10n.homeHeaderTagline), findsOneWidget);
    expect(find.byTooltip('打开设置'), findsOneWidget);
  });
}
