import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('zh'),
  ];

  /// Localized message for algorithm xpress4k.
  ///
  /// In en, this message translates to:
  /// **'XPRESS 4K (Fast)'**
  String get algorithmXpress4k;

  /// Localized message for algorithm xpress8k.
  ///
  /// In en, this message translates to:
  /// **'XPRESS 8K (Balanced)'**
  String get algorithmXpress8k;

  /// Localized message for algorithm xpress16k.
  ///
  /// In en, this message translates to:
  /// **'XPRESS 16K (Better Ratio)'**
  String get algorithmXpress16k;

  /// Localized message for algorithm lzx.
  ///
  /// In en, this message translates to:
  /// **'LZX (Maximum)'**
  String get algorithmLzx;

  /// Localized message for platform steam.
  ///
  /// In en, this message translates to:
  /// **'Steam'**
  String get platformSteam;

  /// Localized message for platform epic games.
  ///
  /// In en, this message translates to:
  /// **'Epic Games'**
  String get platformEpicGames;

  /// Localized message for platform gog galaxy.
  ///
  /// In en, this message translates to:
  /// **'GOG Galaxy'**
  String get platformGogGalaxy;

  /// Localized message for platform ubisoft connect.
  ///
  /// In en, this message translates to:
  /// **'Ubisoft Connect'**
  String get platformUbisoftConnect;

  /// Localized message for platform ea app.
  ///
  /// In en, this message translates to:
  /// **'EA App'**
  String get platformEaApp;

  /// Localized message for platform battle net.
  ///
  /// In en, this message translates to:
  /// **'Battle.net'**
  String get platformBattleNet;

  /// Localized message for platform xbox game pass.
  ///
  /// In en, this message translates to:
  /// **'Xbox Game Pass'**
  String get platformXboxGamePass;

  /// Localized message for platform custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get platformCustom;

  /// Localized message for common add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// Localized message for common cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Localized message for common dismiss tooltip.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get commonDismissTooltip;

  /// Localized message for common enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get commonEnable;

  /// Localized message for common open folder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get commonOpenFolder;

  /// Localized message for common quit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get commonQuit;

  /// Localized message for common retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Localized message for common not available.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get commonNotAvailable;

  /// Localized message for common gigabytes.
  ///
  /// In en, this message translates to:
  /// **'{value} GB'**
  String commonGigabytes(String value);

  /// Localized message for common megabytes.
  ///
  /// In en, this message translates to:
  /// **'{count} MB'**
  String commonMegabytes(String count);

  /// Localized message for route not found title.
  ///
  /// In en, this message translates to:
  /// **'Route Not Found'**
  String get routeNotFoundTitle;

  /// Localized message for route not found message.
  ///
  /// In en, this message translates to:
  /// **'The requested route does not exist.'**
  String get routeNotFoundMessage;

  /// Localized message for settings title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Localized message for settings load failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load settings: {errorMessage}'**
  String settingsLoadFailed(String errorMessage);

  /// Localized message for settings automation section title.
  ///
  /// In en, this message translates to:
  /// **'Automation'**
  String get settingsAutomationSectionTitle;

  /// Localized message for settings idle threshold label.
  ///
  /// In en, this message translates to:
  /// **'Idle threshold'**
  String get settingsIdleThresholdLabel;

  /// Localized message for settings minutes short.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String settingsMinutesShort(int minutes);

  /// Localized message for settings cpu threshold label.
  ///
  /// In en, this message translates to:
  /// **'CPU threshold'**
  String get settingsCpuThresholdLabel;

  /// Localized message for settings percent short.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String settingsPercentShort(String percent);

  /// Localized message for settings minimize to tray on close label.
  ///
  /// In en, this message translates to:
  /// **'Minimize to tray on close'**
  String get settingsMinimizeToTrayOnCloseLabel;

  /// Localized message for settings paths section title.
  ///
  /// In en, this message translates to:
  /// **'Custom Paths'**
  String get settingsPathsSectionTitle;

  /// Localized message for settings paths hint.
  ///
  /// In en, this message translates to:
  /// **'Add an extra library folder path'**
  String get settingsPathsHint;

  /// Localized message for settings no custom paths.
  ///
  /// In en, this message translates to:
  /// **'No custom library paths configured.'**
  String get settingsNoCustomPaths;

  /// Localized message for settings remove path tooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove path'**
  String get settingsRemovePathTooltip;

  /// Localized message for settings compression section title.
  ///
  /// In en, this message translates to:
  /// **'Compression'**
  String get settingsCompressionSectionTitle;

  /// Localized message for settings algorithm label.
  ///
  /// In en, this message translates to:
  /// **'Algorithm'**
  String get settingsAlgorithmLabel;

  /// Localized message for settings algorithm tooltip.
  ///
  /// In en, this message translates to:
  /// **'Select the compression algorithm.'**
  String get settingsAlgorithmTooltip;

  /// Localized message for settings algorithm recommended hint.
  ///
  /// In en, this message translates to:
  /// **'XPRESS 8K is the recommended default for most games.'**
  String get settingsAlgorithmRecommendedHint;

  /// Localized message for settings io threads tooltip.
  ///
  /// In en, this message translates to:
  /// **'Override parallel I/O thread count.'**
  String get settingsIoThreadsTooltip;

  /// Localized message for settings io threads label.
  ///
  /// In en, this message translates to:
  /// **'I/O threads'**
  String get settingsIoThreadsLabel;

  /// Localized message for settings io threads auto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get settingsIoThreadsAuto;

  /// Localized message for settings io threads count.
  ///
  /// In en, this message translates to:
  /// **'{count} threads'**
  String settingsIoThreadsCount(int count);

  /// Localized message for settings io threads help.
  ///
  /// In en, this message translates to:
  /// **'Auto matches the current hardware recommendation.'**
  String get settingsIoThreadsHelp;

  /// Localized message for settings inventory section title.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get settingsInventorySectionTitle;

  /// Localized message for settings pause watcher.
  ///
  /// In en, this message translates to:
  /// **'Pause watcher'**
  String get settingsPauseWatcher;

  /// Localized message for settings resume watcher.
  ///
  /// In en, this message translates to:
  /// **'Resume watcher'**
  String get settingsResumeWatcher;

  /// Localized message for settings watcher automation enabled.
  ///
  /// In en, this message translates to:
  /// **'Automation is currently watching the compression inventory.'**
  String get settingsWatcherAutomationEnabled;

  /// Localized message for settings watcher automation disabled.
  ///
  /// In en, this message translates to:
  /// **'Automation is currently paused for the compression inventory.'**
  String get settingsWatcherAutomationDisabled;

  /// Localized message for settings enable full metadata inventory scan.
  ///
  /// In en, this message translates to:
  /// **'Enable full metadata inventory scan'**
  String get settingsEnableFullMetadataInventoryScan;

  /// Localized message for settings inventory advanced description.
  ///
  /// In en, this message translates to:
  /// **'Collect richer metadata for the inventory table. This may take longer during scans.'**
  String get settingsInventoryAdvancedDescription;

  /// Localized message for settings steam grid db managed once.
  ///
  /// In en, this message translates to:
  /// **'SteamGridDB artwork is only fetched once per game unless you refresh it.'**
  String get settingsSteamGridDbManagedOnce;

  /// Localized message for settings language section title.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageSectionTitle;

  /// Localized message for settings language selector label.
  ///
  /// In en, this message translates to:
  /// **'Display language'**
  String get settingsLanguageSelectorLabel;

  /// Localized message for settings language selector tooltip.
  ///
  /// In en, this message translates to:
  /// **'Choose the app language.'**
  String get settingsLanguageSelectorTooltip;

  /// Localized message for settings language system default.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystemDefault;

  /// Localized message for settings language english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// Localized message for settings language spanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get settingsLanguageSpanish;

  /// Localized message for settings language chinese simplified.
  ///
  /// In en, this message translates to:
  /// **'Chinese (Simplified)'**
  String get settingsLanguageChineseSimplified;

  /// Localized message for settings integrations section title.
  ///
  /// In en, this message translates to:
  /// **'Integrations'**
  String get settingsIntegrationsSectionTitle;

  /// Localized message for settings api key saved message.
  ///
  /// In en, this message translates to:
  /// **'API key saved.'**
  String get settingsApiKeySavedMessage;

  /// Localized message for settings api key copied message.
  ///
  /// In en, this message translates to:
  /// **'API key copied.'**
  String get settingsApiKeyCopiedMessage;

  /// Localized message for settings steam grid db connected status.
  ///
  /// In en, this message translates to:
  /// **'SteamGridDB API key connected'**
  String get settingsSteamGridDbConnectedStatus;

  /// Localized message for settings steam grid db missing status.
  ///
  /// In en, this message translates to:
  /// **'SteamGridDB API key missing'**
  String get settingsSteamGridDbMissingStatus;

  /// Localized message for settings steam grid db explanation.
  ///
  /// In en, this message translates to:
  /// **'SteamGridDB improves cover art quality for manually added or hard-to-match games.'**
  String get settingsSteamGridDbExplanation;

  /// Localized message for settings steam grid db step1.
  ///
  /// In en, this message translates to:
  /// **'Open your SteamGridDB account preferences page.'**
  String get settingsSteamGridDbStep1;

  /// Localized message for settings steam grid db step2.
  ///
  /// In en, this message translates to:
  /// **'Generate or copy your personal API key.'**
  String get settingsSteamGridDbStep2;

  /// Localized message for settings steam grid db step3.
  ///
  /// In en, this message translates to:
  /// **'Paste it here to enable richer cover art lookups.'**
  String get settingsSteamGridDbStep3;

  /// Localized message for settings steam grid db open button.
  ///
  /// In en, this message translates to:
  /// **'Open SteamGridDB API Page'**
  String get settingsSteamGridDbOpenButton;

  /// Localized message for settings steam grid db api key label.
  ///
  /// In en, this message translates to:
  /// **'SteamGridDB API key'**
  String get settingsSteamGridDbApiKeyLabel;

  /// Localized message for settings steam grid db api key hint.
  ///
  /// In en, this message translates to:
  /// **'Paste your SteamGridDB API key'**
  String get settingsSteamGridDbApiKeyHint;

  /// Localized message for settings steam grid db show key tooltip.
  ///
  /// In en, this message translates to:
  /// **'Show key'**
  String get settingsSteamGridDbShowKeyTooltip;

  /// Localized message for settings steam grid db hide key tooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide key'**
  String get settingsSteamGridDbHideKeyTooltip;

  /// Localized message for settings steam grid db copy key tooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy key'**
  String get settingsSteamGridDbCopyKeyTooltip;

  /// Localized message for settings steam grid db save button.
  ///
  /// In en, this message translates to:
  /// **'Save key'**
  String get settingsSteamGridDbSaveButton;

  /// Localized message for settings steam grid db remove button.
  ///
  /// In en, this message translates to:
  /// **'Remove key'**
  String get settingsSteamGridDbRemoveButton;

  /// Localized message for settings safety section title.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get settingsSafetySectionTitle;

  /// Localized message for settings allow direct storage override.
  ///
  /// In en, this message translates to:
  /// **'Allow DirectStorage override'**
  String get settingsAllowDirectStorageOverride;

  /// Localized message for settings direct storage warning lead.
  ///
  /// In en, this message translates to:
  /// **'Use this only if you understand the risk.'**
  String get settingsDirectStorageWarningLead;

  /// Localized message for settings direct storage warning body.
  ///
  /// In en, this message translates to:
  /// **'DirectStorage games may load slower or behave unpredictably after compression.'**
  String get settingsDirectStorageWarningBody;

  /// Localized message for settings enable direct storage override title.
  ///
  /// In en, this message translates to:
  /// **'Enable DirectStorage override?'**
  String get settingsEnableDirectStorageOverrideTitle;

  /// Localized message for settings enable direct storage override message.
  ///
  /// In en, this message translates to:
  /// **'This allows compression on games flagged for DirectStorage. It can affect loading performance and stability.'**
  String get settingsEnableDirectStorageOverrideMessage;

  /// Localized message for settings watcher status active.
  ///
  /// In en, this message translates to:
  /// **'Watcher active'**
  String get settingsWatcherStatusActive;

  /// Localized message for settings watcher status paused.
  ///
  /// In en, this message translates to:
  /// **'Watcher paused'**
  String get settingsWatcherStatusPaused;

  /// Localized message for home refresh games tooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh games'**
  String get homeRefreshGamesTooltip;

  /// Localized message for home compression inventory tooltip.
  ///
  /// In en, this message translates to:
  /// **'Open compression inventory'**
  String get homeCompressionInventoryTooltip;

  /// Localized message for home add game tooltip.
  ///
  /// In en, this message translates to:
  /// **'Add game'**
  String get homeAddGameTooltip;

  /// Localized message for home settings tooltip.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get homeSettingsTooltip;

  /// Localized message for home switch to list view tooltip.
  ///
  /// In en, this message translates to:
  /// **'Switch to list view'**
  String get homeSwitchToListViewTooltip;

  /// Localized message for home switch to grid view tooltip.
  ///
  /// In en, this message translates to:
  /// **'Switch to grid view'**
  String get homeSwitchToGridViewTooltip;

  /// Localized message for home header tagline.
  ///
  /// In en, this message translates to:
  /// **'Compact your library without losing control.'**
  String get homeHeaderTagline;

  /// Localized message for home header ready line.
  ///
  /// In en, this message translates to:
  /// **'{count} games are ready to reclaim space.'**
  String homeHeaderReadyLine(int count);

  /// Localized message for home search games hint.
  ///
  /// In en, this message translates to:
  /// **'Search games...'**
  String get homeSearchGamesHint;

  /// Localized message for home primary review eligible action.
  ///
  /// In en, this message translates to:
  /// **'Review eligible games'**
  String get homePrimaryReviewEligible;

  /// Localized message for home primary open inventory action.
  ///
  /// In en, this message translates to:
  /// **'Open inventory'**
  String get homePrimaryOpenInventory;

  /// Localized message for home primary add game action.
  ///
  /// In en, this message translates to:
  /// **'Add a game'**
  String get homePrimaryAddGame;

  /// Localized message for home empty title.
  ///
  /// In en, this message translates to:
  /// **'No games in view'**
  String get homeEmptyTitle;

  /// Localized message for home empty message.
  ///
  /// In en, this message translates to:
  /// **'Games from Steam, Epic, GOG, and other launchers appear here automatically.'**
  String get homeEmptyMessage;

  /// Localized message for home empty guidance.
  ///
  /// In en, this message translates to:
  /// **'Refresh discovery or add a game folder manually to start reviewing compression opportunities.'**
  String get homeEmptyGuidance;

  /// Localized message for home load error title.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your library'**
  String get homeLoadErrorTitle;

  /// Localized message for home load error guidance.
  ///
  /// In en, this message translates to:
  /// **'Retry discovery. If this keeps happening, check launcher paths or add a game folder manually.'**
  String get homeLoadErrorGuidance;

  /// Localized message for home list empty title.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches this view'**
  String get homeListEmptyTitle;

  /// Localized message for home list empty message.
  ///
  /// In en, this message translates to:
  /// **'Clear the current search or filters, or add a game folder manually.'**
  String get homeListEmptyMessage;

  /// Localized message for home select game title.
  ///
  /// In en, this message translates to:
  /// **'Choose a game'**
  String get homeSelectGameTitle;

  /// Localized message for home select game message.
  ///
  /// In en, this message translates to:
  /// **'Select a title to inspect its size, compression history, and next actions.'**
  String get homeSelectGameMessage;

  /// Localized message for home ready-to-compress status.
  ///
  /// In en, this message translates to:
  /// **'Ready to compress'**
  String get homeStatusReadyToCompress;

  /// Localized message for home added to library message.
  ///
  /// In en, this message translates to:
  /// **'\"{gameName}\" added to the library.'**
  String homeAddedToLibraryMessage(String gameName);

  /// Localized message for home updated in library message.
  ///
  /// In en, this message translates to:
  /// **'\"{gameName}\" updated in the library.'**
  String homeUpdatedInLibraryMessage(String gameName);

  /// Localized message for home failed to add game message.
  ///
  /// In en, this message translates to:
  /// **'Failed to add game: {errorMessage}'**
  String homeFailedToAddGameMessage(String errorMessage);

  /// Localized message for home invalid path message.
  ///
  /// In en, this message translates to:
  /// **'The selected path is not valid.'**
  String get homeInvalidPathMessage;

  /// Localized message for home add game dialog title.
  ///
  /// In en, this message translates to:
  /// **'Add Game'**
  String get homeAddGameDialogTitle;

  /// Localized message for home add game path hint.
  ///
  /// In en, this message translates to:
  /// **'Choose a game folder or executable'**
  String get homeAddGamePathHint;

  /// Localized message for home browse folder.
  ///
  /// In en, this message translates to:
  /// **'Browse folder'**
  String get homeBrowseFolder;

  /// Localized message for home browse exe.
  ///
  /// In en, this message translates to:
  /// **'Browse .exe'**
  String get homeBrowseExe;

  /// Localized message for home cover art nudge message.
  ///
  /// In en, this message translates to:
  /// **'Connect SteamGridDB in Settings to improve cover art matching.'**
  String get homeCoverArtNudgeMessage;

  /// Localized message for home go to settings button.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get homeGoToSettingsButton;

  /// Localized message for home overview eyebrow.
  ///
  /// In en, this message translates to:
  /// **'COMPRESS READY'**
  String get homeOverviewEyebrow;

  /// Localized message for home overview empty headline.
  ///
  /// In en, this message translates to:
  /// **'Bring your library in. Then make room fast.'**
  String get homeOverviewEmptyHeadline;

  /// Localized message for home overview empty subtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan your launchers or add a game folder manually to start surfacing reclaimable space.'**
  String get homeOverviewEmptySubtitle;

  /// Localized message for home overview ready headline.
  ///
  /// In en, this message translates to:
  /// **'{count} games are ready to reclaim space.'**
  String homeOverviewReadyHeadline(int count);

  /// Localized message for home overview ready subtitle.
  ///
  /// In en, this message translates to:
  /// **'Start with the clearest savings opportunities first. Estimated reclaimable space: {value}.'**
  String homeOverviewReadySubtitle(String value);

  /// Localized message for home overview protected headline.
  ///
  /// In en, this message translates to:
  /// **'Your library is discovered, but these titles stay protected.'**
  String get homeOverviewProtectedHeadline;

  /// Localized message for home overview protected subtitle.
  ///
  /// In en, this message translates to:
  /// **'Review DirectStorage and unsupported games in the inventory before forcing compression.'**
  String get homeOverviewProtectedSubtitle;

  /// Localized message for home overview managed headline.
  ///
  /// In en, this message translates to:
  /// **'Your compressed library is holding the line.'**
  String get homeOverviewManagedHeadline;

  /// Localized message for home overview managed subtitle.
  ///
  /// In en, this message translates to:
  /// **'Check the inventory for saved space and review new titles as they appear.'**
  String get homeOverviewManagedSubtitle;

  /// Localized message for home overview ready count label.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get homeOverviewReadyCountLabel;

  /// Localized message for home overview compressed count label.
  ///
  /// In en, this message translates to:
  /// **'Compressed'**
  String get homeOverviewCompressedCountLabel;

  /// Localized message for home overview protected count label.
  ///
  /// In en, this message translates to:
  /// **'Protected'**
  String get homeOverviewProtectedCountLabel;

  /// Localized message for home overview reclaimable label.
  ///
  /// In en, this message translates to:
  /// **'Potential space'**
  String get homeOverviewReclaimableLabel;

  /// Localized message for inventory title.
  ///
  /// In en, this message translates to:
  /// **'Compression Inventory'**
  String get inventoryTitle;

  /// Localized message for inventory refresh tooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh inventory'**
  String get inventoryRefreshTooltip;

  /// Localized message for inventory load failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load inventory: {errorMessage}'**
  String inventoryLoadFailed(String errorMessage);

  /// Localized message for inventory search hint.
  ///
  /// In en, this message translates to:
  /// **'Search inventory...'**
  String get inventorySearchHint;

  /// Localized message for inventory sort direction descending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get inventorySortDirectionDescending;

  /// Localized message for inventory sort direction ascending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get inventorySortDirectionAscending;

  /// Localized message for inventory sort label.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get inventorySortLabel;

  /// Localized message for inventory sort savings percent.
  ///
  /// In en, this message translates to:
  /// **'Savings %'**
  String get inventorySortSavingsPercent;

  /// Localized message for inventory sort original size.
  ///
  /// In en, this message translates to:
  /// **'Original size'**
  String get inventorySortOriginalSize;

  /// Localized message for inventory sort name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get inventorySortName;

  /// Localized message for inventory sort platform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get inventorySortPlatform;

  /// Localized message for inventory header game.
  ///
  /// In en, this message translates to:
  /// **'GAME'**
  String get inventoryHeaderGame;

  /// Localized message for inventory header platform.
  ///
  /// In en, this message translates to:
  /// **'PLATFORM'**
  String get inventoryHeaderPlatform;

  /// Localized message for inventory header original.
  ///
  /// In en, this message translates to:
  /// **'ORIGINAL'**
  String get inventoryHeaderOriginal;

  /// Localized message for inventory header current.
  ///
  /// In en, this message translates to:
  /// **'CURRENT'**
  String get inventoryHeaderCurrent;

  /// Localized message for inventory header savings.
  ///
  /// In en, this message translates to:
  /// **'SAVINGS'**
  String get inventoryHeaderSavings;

  /// Localized message for inventory header last checked.
  ///
  /// In en, this message translates to:
  /// **'LAST CHECKED'**
  String get inventoryHeaderLastChecked;

  /// Localized message for inventory header watcher.
  ///
  /// In en, this message translates to:
  /// **'WATCHER'**
  String get inventoryHeaderWatcher;

  /// Localized message for inventory empty.
  ///
  /// In en, this message translates to:
  /// **'No games match the current inventory filters.'**
  String get inventoryEmpty;

  /// Localized message for inventory watcher not watched.
  ///
  /// In en, this message translates to:
  /// **'Not watched'**
  String get inventoryWatcherNotWatched;

  /// Localized message for inventory watcher watched.
  ///
  /// In en, this message translates to:
  /// **'Watched'**
  String get inventoryWatcherWatched;

  /// Localized message for inventory watcher paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get inventoryWatcherPaused;

  /// Localized message for inventory watcher active.
  ///
  /// In en, this message translates to:
  /// **'Watcher active'**
  String get inventoryWatcherActive;

  /// Localized message for inventory algorithm badge label.
  ///
  /// In en, this message translates to:
  /// **'Algorithm'**
  String get inventoryAlgorithmBadgeLabel;

  /// Localized message for inventory watcher badge label.
  ///
  /// In en, this message translates to:
  /// **'Watcher'**
  String get inventoryWatcherBadgeLabel;

  /// Localized message for inventory watcher badge active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get inventoryWatcherBadgeActive;

  /// Localized message for inventory watcher badge paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get inventoryWatcherBadgePaused;

  /// Localized message for inventory pause watcher.
  ///
  /// In en, this message translates to:
  /// **'Pause watcher'**
  String get inventoryPauseWatcher;

  /// Localized message for inventory resume watcher.
  ///
  /// In en, this message translates to:
  /// **'Resume watcher'**
  String get inventoryResumeWatcher;

  /// Localized message for inventory advanced metadata scan on.
  ///
  /// In en, this message translates to:
  /// **'Advanced metadata scan: on'**
  String get inventoryAdvancedMetadataScanOn;

  /// Localized message for inventory advanced metadata scan off.
  ///
  /// In en, this message translates to:
  /// **'Advanced metadata scan: off'**
  String get inventoryAdvancedMetadataScanOff;

  /// Localized message for inventory run full rescan.
  ///
  /// In en, this message translates to:
  /// **'Run full inventory rescan'**
  String get inventoryRunFullRescan;

  /// Localized message for inventory rescan unavailable while loading.
  ///
  /// In en, this message translates to:
  /// **'Rescan unavailable while loading'**
  String get inventoryRescanUnavailableWhileLoading;

  /// Localized message for inventory watcher summary.
  ///
  /// In en, this message translates to:
  /// **'{status}. Interactive controls are shown below.'**
  String inventoryWatcherSummary(String status);

  /// Localized message for activity dismiss monitor.
  ///
  /// In en, this message translates to:
  /// **'Dismiss monitor'**
  String get activityDismissMonitor;

  /// Localized message for activity compressing.
  ///
  /// In en, this message translates to:
  /// **'Compressing'**
  String get activityCompressing;

  /// Localized message for activity decompressing.
  ///
  /// In en, this message translates to:
  /// **'Decompressing'**
  String get activityDecompressing;

  /// Localized message for activity preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get activityPreparing;

  /// Localized message for activity scanning files.
  ///
  /// In en, this message translates to:
  /// **'Scanning files...'**
  String get activityScanningFiles;

  /// Localized message for activity scanning compressed files.
  ///
  /// In en, this message translates to:
  /// **'Scanning compressed files...'**
  String get activityScanningCompressedFiles;

  /// Localized message for activity amount saved.
  ///
  /// In en, this message translates to:
  /// **'Saved {value}'**
  String activityAmountSaved(String value);

  /// Localized message for activity amount restoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring {value}'**
  String activityAmountRestoring(String value);

  /// Localized message for activity approx file progress.
  ///
  /// In en, this message translates to:
  /// **'~{processed}/{total} files'**
  String activityApproxFileProgress(int processed, int total);

  /// Localized message for activity file progress.
  ///
  /// In en, this message translates to:
  /// **'{processed}/{total} files'**
  String activityFileProgress(int processed, int total);

  /// Localized message for activity seconds remaining.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s left'**
  String activitySecondsRemaining(int seconds);

  /// Localized message for activity minutes remaining.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m left'**
  String activityMinutesRemaining(int minutes);

  /// Localized message for activity hours minutes remaining.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m left'**
  String activityHoursMinutesRemaining(int hours, int minutes);

  /// Localized message for game status direct storage.
  ///
  /// In en, this message translates to:
  /// **'DirectStorage'**
  String get gameStatusDirectStorage;

  /// Localized message for game status unsupported.
  ///
  /// In en, this message translates to:
  /// **'Unsupported'**
  String get gameStatusUnsupported;

  /// Localized message for game status not compressed.
  ///
  /// In en, this message translates to:
  /// **'Not compressed'**
  String get gameStatusNotCompressed;

  /// Localized message for game saved gigabytes.
  ///
  /// In en, this message translates to:
  /// **'Saved {gigabytes} GB'**
  String gameSavedGigabytes(String gigabytes);

  /// Localized message for game estimated saveable gigabytes.
  ///
  /// In en, this message translates to:
  /// **'{gigabytes} GB saveable'**
  String gameEstimatedSaveableGigabytes(String gigabytes);

  /// Localized message for game marked unsupported.
  ///
  /// In en, this message translates to:
  /// **'\"{gameName}\" marked as unsupported.'**
  String gameMarkedUnsupported(String gameName);

  /// Localized message for game marked supported.
  ///
  /// In en, this message translates to:
  /// **'\"{gameName}\" marked as supported.'**
  String gameMarkedSupported(String gameName);

  /// Localized message for game menu view details.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get gameMenuViewDetails;

  /// Localized message for game menu compress now.
  ///
  /// In en, this message translates to:
  /// **'Compress Now'**
  String get gameMenuCompressNow;

  /// Localized message for game menu decompress.
  ///
  /// In en, this message translates to:
  /// **'Decompress'**
  String get gameMenuDecompress;

  /// Localized message for game menu mark unsupported.
  ///
  /// In en, this message translates to:
  /// **'Mark as Unsupported'**
  String get gameMenuMarkUnsupported;

  /// Localized message for game menu mark supported.
  ///
  /// In en, this message translates to:
  /// **'Mark as Supported'**
  String get gameMenuMarkSupported;

  /// Localized message for game menu exclude from auto compression.
  ///
  /// In en, this message translates to:
  /// **'Exclude From Auto-Compression'**
  String get gameMenuExcludeFromAutoCompression;

  /// Localized message for game menu include in auto compression.
  ///
  /// In en, this message translates to:
  /// **'Include In Auto-Compression'**
  String get gameMenuIncludeInAutoCompression;

  /// Localized message for game menu remove from library.
  ///
  /// In en, this message translates to:
  /// **'Remove from Library'**
  String get gameMenuRemoveFromLibrary;

  /// Localized message for game removed from library.
  ///
  /// In en, this message translates to:
  /// **'\"{gameName}\" removed from library.'**
  String gameRemovedFromLibrary(String gameName);

  /// Localized message for game removal persist failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to persist removal for \"{gameName}\". Refreshing library.'**
  String gameRemovalPersistFailed(String gameName);

  /// Localized message for game confirm compression title.
  ///
  /// In en, this message translates to:
  /// **'Confirm Compression'**
  String get gameConfirmCompressionTitle;

  /// Localized message for game confirm compression message.
  ///
  /// In en, this message translates to:
  /// **'Compress \"{gameName}\"? This can affect disk usage and runtime performance.'**
  String gameConfirmCompressionMessage(String gameName);

  /// Localized message for game confirm compression action.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get gameConfirmCompressionAction;

  /// Localized message for game details title fallback.
  ///
  /// In en, this message translates to:
  /// **'Game Details'**
  String get gameDetailsTitleFallback;

  /// Localized message for game details not found.
  ///
  /// In en, this message translates to:
  /// **'Game not found.'**
  String get gameDetailsNotFound;

  /// Localized message for game details activity compressing now.
  ///
  /// In en, this message translates to:
  /// **'Compressing now'**
  String get gameDetailsActivityCompressingNow;

  /// Localized message for game details activity decompressing now.
  ///
  /// In en, this message translates to:
  /// **'Decompressing now'**
  String get gameDetailsActivityDecompressingNow;

  /// Localized message for game details last compressed badge.
  ///
  /// In en, this message translates to:
  /// **'Last compressed {value}'**
  String gameDetailsLastCompressedBadge(String value);

  /// Localized message for game details status compressed.
  ///
  /// In en, this message translates to:
  /// **'Compressed'**
  String get gameDetailsStatusCompressed;

  /// Localized message for game details status ready.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get gameDetailsStatusReady;

  /// Localized message for game details direct storage warning.
  ///
  /// In en, this message translates to:
  /// **'DirectStorage detected. Compression can impact runtime performance.'**
  String get gameDetailsDirectStorageWarning;

  /// Localized message for game details unsupported warning.
  ///
  /// In en, this message translates to:
  /// **'This game is known to have issues after WOF compression.'**
  String get gameDetailsUnsupportedWarning;

  /// Localized message for game details status group title.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get gameDetailsStatusGroupTitle;

  /// Localized message for game details platform label.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get gameDetailsPlatformLabel;

  /// Localized message for game details compression label.
  ///
  /// In en, this message translates to:
  /// **'Compression'**
  String get gameDetailsCompressionLabel;

  /// Localized message for game details compression compressed.
  ///
  /// In en, this message translates to:
  /// **'Compressed'**
  String get gameDetailsCompressionCompressed;

  /// Localized message for game details compression not compressed.
  ///
  /// In en, this message translates to:
  /// **'Not compressed'**
  String get gameDetailsCompressionNotCompressed;

  /// Localized message for game details direct storage label.
  ///
  /// In en, this message translates to:
  /// **'DirectStorage'**
  String get gameDetailsDirectStorageLabel;

  /// Localized message for game details direct storage detected.
  ///
  /// In en, this message translates to:
  /// **'Detected'**
  String get gameDetailsDirectStorageDetected;

  /// Localized message for game details direct storage not detected.
  ///
  /// In en, this message translates to:
  /// **'Not detected'**
  String get gameDetailsDirectStorageNotDetected;

  /// Localized message for game details unsupported label.
  ///
  /// In en, this message translates to:
  /// **'Unsupported'**
  String get gameDetailsUnsupportedLabel;

  /// Localized message for game details unsupported flagged.
  ///
  /// In en, this message translates to:
  /// **'Flagged'**
  String get gameDetailsUnsupportedFlagged;

  /// Localized message for game details unsupported not flagged.
  ///
  /// In en, this message translates to:
  /// **'Not flagged'**
  String get gameDetailsUnsupportedNotFlagged;

  /// Localized message for game details auto compress label.
  ///
  /// In en, this message translates to:
  /// **'Auto-compress'**
  String get gameDetailsAutoCompressLabel;

  /// Localized message for game details auto compress excluded.
  ///
  /// In en, this message translates to:
  /// **'Excluded'**
  String get gameDetailsAutoCompressExcluded;

  /// Localized message for game details auto compress included.
  ///
  /// In en, this message translates to:
  /// **'Included'**
  String get gameDetailsAutoCompressIncluded;

  /// Localized message for game details storage group title.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get gameDetailsStorageGroupTitle;

  /// Localized message for game details original size label.
  ///
  /// In en, this message translates to:
  /// **'Original size'**
  String get gameDetailsOriginalSizeLabel;

  /// Localized message for game details current size label.
  ///
  /// In en, this message translates to:
  /// **'Current size'**
  String get gameDetailsCurrentSizeLabel;

  /// Localized message for game details space saved label.
  ///
  /// In en, this message translates to:
  /// **'Space saved'**
  String get gameDetailsSpaceSavedLabel;

  /// Localized message for game details savings label.
  ///
  /// In en, this message translates to:
  /// **'Savings'**
  String get gameDetailsSavingsLabel;

  /// Localized message for game details install path group title.
  ///
  /// In en, this message translates to:
  /// **'Install Path'**
  String get gameDetailsInstallPathGroupTitle;

  /// Localized message for game details compressed at.
  ///
  /// In en, this message translates to:
  /// **'Compressed {value}'**
  String gameDetailsCompressedAt(String value);

  /// Localized message for game details removed from library.
  ///
  /// In en, this message translates to:
  /// **'Removed \"{gameName}\" from library. It will not reappear unless reinstalled.'**
  String gameDetailsRemovedFromLibrary(String gameName);

  /// Localized message for game details copy path tooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get gameDetailsCopyPathTooltip;

  /// Localized message for game details install path copied.
  ///
  /// In en, this message translates to:
  /// **'Install path copied.'**
  String get gameDetailsInstallPathCopied;

  /// Localized message for game details storage legend current.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get gameDetailsStorageLegendCurrent;

  /// Localized message for game details storage legend original.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get gameDetailsStorageLegendOriginal;

  /// Localized message for game details storage legend saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get gameDetailsStorageLegendSaved;

  /// Localized message for tray open app.
  ///
  /// In en, this message translates to:
  /// **'Open PressPlay'**
  String get trayOpenApp;

  /// Localized message for tray pause auto compression.
  ///
  /// In en, this message translates to:
  /// **'Pause Auto-Compression'**
  String get trayPauseAutoCompression;

  /// Localized message for tray resume auto compression.
  ///
  /// In en, this message translates to:
  /// **'Resume Auto-Compression'**
  String get trayResumeAutoCompression;

  /// Localized message for tray compressing.
  ///
  /// In en, this message translates to:
  /// **'Compressing'**
  String get trayCompressing;

  /// Localized message for tray paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get trayPaused;

  /// Localized message for tray error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get trayError;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
