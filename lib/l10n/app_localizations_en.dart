// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get algorithmXpress4k => 'XPRESS 4K (Fast)';

  @override
  String get algorithmXpress8k => 'XPRESS 8K (Balanced)';

  @override
  String get algorithmXpress16k => 'XPRESS 16K (Better Ratio)';

  @override
  String get algorithmLzx => 'LZX (Maximum)';

  @override
  String get platformSteam => 'Steam';

  @override
  String get platformEpicGames => 'Epic Games';

  @override
  String get platformGogGalaxy => 'GOG Galaxy';

  @override
  String get platformUbisoftConnect => 'Ubisoft Connect';

  @override
  String get platformEaApp => 'EA App';

  @override
  String get platformBattleNet => 'Battle.net';

  @override
  String get platformXboxGamePass => 'Xbox Game Pass';

  @override
  String get platformCustom => 'Custom';

  @override
  String get platformApplication => 'Application';

  @override
  String get addItemModeGame => 'Game';

  @override
  String get addItemModeApplication => 'Application';

  @override
  String get addApplicationPathHint =>
      'Paste application folder path or browse...';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDismissTooltip => 'Dismiss';

  @override
  String get commonEnable => 'Enable';

  @override
  String get commonSet => 'Set';

  @override
  String get commonOpenFolder => 'Open Folder';

  @override
  String get commonQuit => 'Quit';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonNotAvailable => 'N/A';

  @override
  String commonGigabytes(String value) {
    return '$value GB';
  }

  @override
  String commonMegabytes(String count) {
    return '$count MB';
  }

  @override
  String get routeNotFoundTitle => 'Route Not Found';

  @override
  String get routeNotFoundMessage => 'The requested route does not exist.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String settingsLoadFailed(String errorMessage) {
    return 'Failed to load settings: $errorMessage';
  }

  @override
  String get settingsAutomationSectionTitle => 'Automation';

  @override
  String get settingsIdleThresholdLabel => 'Idle threshold';

  @override
  String settingsMinutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String get settingsCpuThresholdLabel => 'CPU threshold';

  @override
  String settingsPercentShort(String percent) {
    return '$percent%';
  }

  @override
  String get settingsExactValueHint => 'Enter an exact value';

  @override
  String settingsRangeMinutes(int min, int max) {
    return 'Range $min-$max min';
  }

  @override
  String settingsRangePercent(int min, int max) {
    return 'Range $min-$max%';
  }

  @override
  String get settingsMinimizeToTrayOnCloseLabel => 'Minimize to tray on close';

  @override
  String get settingsPathsSectionTitle => 'Custom Paths';

  @override
  String get settingsPathsHint => 'Add an extra library folder path';

  @override
  String get settingsNoCustomPaths => 'No custom library paths configured.';

  @override
  String get settingsRemovePathTooltip => 'Remove path';

  @override
  String get settingsCompressionSectionTitle => 'Compression';

  @override
  String get settingsAlgorithmLabel => 'Algorithm';

  @override
  String get settingsAlgorithmTooltip => 'Select the compression algorithm.';

  @override
  String get settingsAlgorithmRecommendedHint =>
      'XPRESS 8K is the recommended default for most games.';

  @override
  String get settingsIoThreadsTooltip => 'Override parallel I/O thread count.';

  @override
  String get settingsIoThreadsLabel => 'I/O threads';

  @override
  String get settingsIoThreadsAuto => 'Auto';

  @override
  String settingsIoThreadsCount(int count) {
    return '$count threads';
  }

  @override
  String get settingsIoThreadsHelp =>
      'Auto matches the current hardware recommendation.';

  @override
  String get settingsInventorySectionTitle => 'Inventory';

  @override
  String get settingsPauseWatcher => 'Pause watcher';

  @override
  String get settingsResumeWatcher => 'Resume watcher';

  @override
  String get settingsWatcherAutomationEnabled =>
      'Automation is currently watching the compression inventory.';

  @override
  String get settingsWatcherAutomationDisabled =>
      'Automation is currently paused for the compression inventory.';

  @override
  String get settingsEnableFullMetadataInventoryScan =>
      'Enable full metadata inventory scan';

  @override
  String get settingsInventoryAdvancedDescription =>
      'Collect richer metadata for the inventory table. This may take longer during scans.';

  @override
  String get settingsSteamGridDbManagedOnce =>
      'SteamGridDB artwork is only fetched once per game unless you refresh it.';

  @override
  String get settingsLanguageSectionTitle => 'Language';

  @override
  String get settingsLanguageSelectorLabel => 'Display language';

  @override
  String get settingsLanguageSelectorTooltip => 'Choose the app language.';

  @override
  String get settingsLanguageSystemDefault => 'System default';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageSpanish => 'Spanish';

  @override
  String get settingsLanguageChineseSimplified => 'Chinese (Simplified)';

  @override
  String get settingsIntegrationsSectionTitle => 'Integrations';

  @override
  String get settingsApiKeySavedMessage => 'API key saved.';

  @override
  String get settingsApiKeyCopiedMessage => 'API key copied.';

  @override
  String get settingsSteamGridDbConnectedStatus =>
      'SteamGridDB API key connected';

  @override
  String get settingsSteamGridDbMissingStatus => 'SteamGridDB API key missing';

  @override
  String get settingsSteamGridDbExplanation =>
      'SteamGridDB improves cover art quality for manually added or hard-to-match games.';

  @override
  String get settingsSteamGridDbStep1 =>
      'Open your SteamGridDB account preferences page.';

  @override
  String get settingsSteamGridDbStep2 =>
      'Generate or copy your personal API key.';

  @override
  String get settingsSteamGridDbStep3 =>
      'Paste it here to enable richer cover art lookups.';

  @override
  String get settingsSteamGridDbOpenButton => 'Open SteamGridDB API Page';

  @override
  String get settingsSteamGridDbApiKeyLabel => 'SteamGridDB API key';

  @override
  String get settingsSteamGridDbApiKeyHint => 'Paste your SteamGridDB API key';

  @override
  String get settingsSteamGridDbShowKeyTooltip => 'Show key';

  @override
  String get settingsSteamGridDbHideKeyTooltip => 'Hide key';

  @override
  String get settingsSteamGridDbCopyKeyTooltip => 'Copy key';

  @override
  String get settingsSteamGridDbSaveButton => 'Save key';

  @override
  String get settingsSteamGridDbRemoveButton => 'Remove key';

  @override
  String get settingsSafetySectionTitle => 'Safety';

  @override
  String get settingsAllowDirectStorageOverride =>
      'Allow DirectStorage override';

  @override
  String get settingsDirectStorageWarningLead =>
      'Use this only if you understand the risk.';

  @override
  String get settingsDirectStorageWarningBody =>
      'DirectStorage games may load slower after compression.';

  @override
  String get settingsEnableDirectStorageOverrideTitle =>
      'Enable DirectStorage override?';

  @override
  String get settingsEnableDirectStorageOverrideMessage =>
      'This allows compression on games flagged for DirectStorage. It can affect loading performance and stability.';

  @override
  String get settingsWatcherStatusActive => 'Watcher active';

  @override
  String get settingsWatcherStatusPaused => 'Watcher paused';

  @override
  String get homeRefreshGamesTooltip => 'Refresh games';

  @override
  String get homeCompressionInventoryTooltip => 'Open compression inventory';

  @override
  String get homeAddGameTooltip => 'Add game';

  @override
  String get homeSettingsTooltip => 'Open settings';

  @override
  String get homeSwitchToListViewTooltip => 'Switch to list view';

  @override
  String get homeSwitchToGridViewTooltip => 'Switch to grid view';

  @override
  String get homeCollapseOverviewTooltip => 'Collapse overview';

  @override
  String get homeExpandOverviewTooltip => 'Expand overview';

  @override
  String get homeHeaderTagline => 'Save space on your computer.';

  @override
  String homeHeaderReadyLine(int count) {
    return '$count games are ready to reclaim space.';
  }

  @override
  String get homeSearchGamesHint => 'Search games...';

  @override
  String get homePrimaryReviewEligible => 'Review eligible games';

  @override
  String get homePrimaryOpenInventory => 'Open inventory';

  @override
  String get homePrimaryAddGame => 'Add a game';

  @override
  String get homeEmptyTitle => 'No games in view';

  @override
  String get homeEmptyMessage =>
      'Games from Steam, Epic, GOG, and other launchers appear here automatically.';

  @override
  String get homeEmptyGuidance =>
      'Refresh discovery or add a game folder manually to start reviewing compression opportunities.';

  @override
  String get homeLoadErrorTitle => 'Couldn\'t load your library';

  @override
  String get homeLoadErrorGuidance =>
      'Retry discovery. If this keeps happening, check launcher paths or add a game folder manually.';

  @override
  String get homeListEmptyTitle => 'Nothing matches this view';

  @override
  String get homeListEmptyMessage =>
      'Clear the current search or filters, or add a game folder manually.';

  @override
  String get homeSelectGameTitle => 'Choose a game';

  @override
  String get homeSelectGameMessage =>
      'Select a title to inspect its size, compression history, and next actions.';

  @override
  String get homeStatusReadyToCompress => 'Ready';

  @override
  String homeAddedToLibraryMessage(String gameName) {
    return '\"$gameName\" added to the library.';
  }

  @override
  String homeUpdatedInLibraryMessage(String gameName) {
    return '\"$gameName\" updated in the library.';
  }

  @override
  String homeFailedToAddGameMessage(String errorMessage) {
    return 'Failed to add game: $errorMessage';
  }

  @override
  String get homeInvalidPathMessage => 'The selected path is not valid.';

  @override
  String get homeAddGameDialogTitle => 'Add Game';

  @override
  String get homeAddGamePathHint => 'Choose a game folder or executable';

  @override
  String get homeBrowseFolder => 'Browse folder';

  @override
  String get homeBrowseExe => 'Browse .exe';

  @override
  String get homeCoverArtNudgeMessage =>
      'Connect SteamGridDB in Settings to improve cover art matching.';

  @override
  String get homeGoToSettingsButton => 'Go to Settings';

  @override
  String get homeOverviewEyebrow => 'Compression overview';

  @override
  String get homeOverviewEmptyHeadline =>
      'Bring your library in. Then make room fast.';

  @override
  String get homeOverviewEmptySubtitle =>
      'Scan your launchers or add a game folder manually to start surfacing reclaimable space.';

  @override
  String homeOverviewReadyHeadline(int count) {
    return '$count games are ready to reclaim space.';
  }

  @override
  String homeOverviewReadySubtitle(String value) {
    return 'See which games are ready to compress and how much space you could save: $value.';
  }

  @override
  String get homeOverviewProtectedHeadline =>
      'Your library is discovered, but these titles stay protected.';

  @override
  String get homeOverviewProtectedSubtitle =>
      'Review DirectStorage and unsupported games in the inventory before forcing compression.';

  @override
  String get homeOverviewManagedHeadline =>
      'Your compressed library is holding the line.';

  @override
  String get homeOverviewManagedSubtitle =>
      'Check the inventory for saved space and review new titles as they appear.';

  @override
  String get homeOverviewReadyCountLabel => 'Ready';

  @override
  String get homeOverviewCompressedCountLabel => 'Compressed';

  @override
  String get homeOverviewProtectedCountLabel => 'Protected';

  @override
  String get homeOverviewReclaimableLabel => 'Potential space';

  @override
  String get inventoryTitle => 'Compression Inventory';

  @override
  String get inventoryRefreshTooltip => 'Refresh inventory';

  @override
  String inventoryLoadFailed(String errorMessage) {
    return 'Failed to load inventory: $errorMessage';
  }

  @override
  String get inventorySearchHint => 'Search inventory...';

  @override
  String get inventorySortDirectionDescending => 'Descending';

  @override
  String get inventorySortDirectionAscending => 'Ascending';

  @override
  String get inventorySortLabel => 'Sort by';

  @override
  String get inventorySortSavingsPercent => 'Savings %';

  @override
  String get inventorySortOriginalSize => 'Original size';

  @override
  String get inventorySortName => 'Name';

  @override
  String get inventorySortPlatform => 'Platform';

  @override
  String get inventoryHeaderGame => 'GAME';

  @override
  String get inventoryHeaderPlatform => 'PLATFORM';

  @override
  String get inventoryHeaderOriginal => 'ORIGINAL';

  @override
  String get inventoryHeaderCurrent => 'CURRENT';

  @override
  String get inventoryHeaderSavings => 'SAVINGS';

  @override
  String get inventoryHeaderLastChecked => 'LAST CHECKED';

  @override
  String get inventoryHeaderWatcher => 'WATCHER';

  @override
  String get inventoryEmpty => 'No games match the current inventory filters.';

  @override
  String get inventoryWatcherNotWatched => 'Not watched';

  @override
  String get inventoryWatcherWatched => 'Watched';

  @override
  String get inventoryWatcherPaused => 'Paused';

  @override
  String get inventoryWatcherActive => 'Watcher active';

  @override
  String get inventoryAlgorithmBadgeLabel => 'Algorithm';

  @override
  String get inventoryWatcherBadgeLabel => 'Watcher';

  @override
  String get inventoryWatcherBadgeActive => 'Active';

  @override
  String get inventoryWatcherBadgePaused => 'Paused';

  @override
  String get inventoryPauseWatcher => 'Pause watcher';

  @override
  String get inventoryResumeWatcher => 'Resume watcher';

  @override
  String get inventoryAdvancedMetadataScanOn => 'Advanced metadata scan: on';

  @override
  String get inventoryAdvancedMetadataScanOff => 'Advanced metadata scan: off';

  @override
  String get inventoryRunFullRescan => 'Run full inventory rescan';

  @override
  String get inventoryRescanUnavailableWhileLoading =>
      'Rescan unavailable while loading';

  @override
  String inventoryWatcherSummary(String status) {
    return '$status.';
  }

  @override
  String get activityDismissMonitor => 'Dismiss monitor';

  @override
  String get activityCompressing => 'Compressing';

  @override
  String get activityDecompressing => 'Decompressing';

  @override
  String get activityPreparing => 'Preparing...';

  @override
  String get activityScanningFiles => 'Scanning files...';

  @override
  String get activityScanningCompressedFiles => 'Scanning compressed files...';

  @override
  String activityAmountSaved(String value) {
    return 'Saved $value';
  }

  @override
  String activityAmountRestoring(String value) {
    return 'Restoring $value';
  }

  @override
  String activityApproxFileProgress(int processed, int total) {
    return '~$processed/$total files';
  }

  @override
  String activityFileProgress(int processed, int total) {
    return '$processed/$total files';
  }

  @override
  String activitySecondsRemaining(int seconds) {
    return '${seconds}s left';
  }

  @override
  String activityMinutesRemaining(int minutes) {
    return '${minutes}m left';
  }

  @override
  String activityHoursMinutesRemaining(int hours, int minutes) {
    return '${hours}h ${minutes}m left';
  }

  @override
  String get gameStatusDirectStorage => 'DirectStorage';

  @override
  String get gameStatusUnsupported => 'Unsupported';

  @override
  String get gameStatusNotCompressed => 'Not compressed';

  @override
  String gameSavedGigabytes(String gigabytes) {
    return 'Saved $gigabytes GB';
  }

  @override
  String gameEstimatedSaveableGigabytes(String gigabytes) {
    return '$gigabytes GB saveable';
  }

  @override
  String gameMarkedUnsupported(String gameName) {
    return '\"$gameName\" marked as unsupported.';
  }

  @override
  String gameMarkedSupported(String gameName) {
    return '\"$gameName\" marked as supported.';
  }

  @override
  String get gameMenuViewDetails => 'View Details';

  @override
  String get gameMenuCompressNow => 'Compress Now';

  @override
  String get gameMenuDecompress => 'Decompress';

  @override
  String get gameMenuMarkUnsupported => 'Mark as Unsupported';

  @override
  String get gameMenuMarkSupported => 'Mark as Supported';

  @override
  String get gameMenuExcludeFromAutoCompression =>
      'Exclude From Auto-Compression';

  @override
  String get gameMenuIncludeInAutoCompression => 'Include In Auto-Compression';

  @override
  String get gameMenuRemoveFromLibrary => 'Remove from Library';

  @override
  String gameRemovedFromLibrary(String gameName) {
    return '\"$gameName\" removed from library.';
  }

  @override
  String gameRemovalPersistFailed(String gameName) {
    return 'Failed to persist removal for \"$gameName\". Refreshing library.';
  }

  @override
  String get gameConfirmCompressionTitle => 'Confirm Compression';

  @override
  String gameConfirmCompressionMessage(String gameName) {
    return 'Compress \"$gameName\"? This can affect disk usage and runtime performance.';
  }

  @override
  String get gameConfirmCompressionAction => 'Compress';

  @override
  String get gameDetailsTitleFallback => 'Game Details';

  @override
  String get gameDetailsNotFound => 'Game not found.';

  @override
  String get gameDetailsActivityCompressingNow => 'Compressing now';

  @override
  String get gameDetailsActivityDecompressingNow => 'Decompressing now';

  @override
  String gameDetailsLastCompressedBadge(String value) {
    return 'Last compressed $value';
  }

  @override
  String get gameDetailsStatusCompressed => 'Compressed';

  @override
  String get gameDetailsStatusReady => 'Ready';

  @override
  String get gameDetailsDirectStorageWarning =>
      'DirectStorage detected. Compression can impact runtime performance.';

  @override
  String get gameDetailsUnsupportedWarning =>
      'Marked by the community as unsupported.';

  @override
  String get gameDetailsStatusGroupTitle => 'Status';

  @override
  String get gameDetailsPlatformLabel => 'Platform';

  @override
  String get gameDetailsCompressionLabel => 'Compression';

  @override
  String get gameDetailsCompressionCompressed => 'Compressed';

  @override
  String get gameDetailsCompressionNotCompressed => 'Not compressed';

  @override
  String get gameDetailsDirectStorageLabel => 'DirectStorage';

  @override
  String get gameDetailsDirectStorageDetected => 'Detected';

  @override
  String get gameDetailsDirectStorageNotDetected => 'Not detected';

  @override
  String get gameDetailsUnsupportedLabel => 'Unsupported';

  @override
  String get gameDetailsUnsupportedFlagged => 'Flagged';

  @override
  String get gameDetailsUnsupportedNotFlagged => 'Not flagged';

  @override
  String get gameDetailsAutoCompressLabel => 'Auto-compress';

  @override
  String get gameDetailsAutoCompressExcluded => 'Excluded';

  @override
  String get gameDetailsAutoCompressIncluded => 'Included';

  @override
  String get gameDetailsStorageGroupTitle => 'Storage';

  @override
  String get gameDetailsOriginalSizeLabel => 'Original size';

  @override
  String get gameDetailsCurrentSizeLabel => 'Current size';

  @override
  String get gameDetailsSpaceSavedLabel => 'Space saved';

  @override
  String get gameDetailsSavingsLabel => 'Savings';

  @override
  String get gameDetailsInstallPathGroupTitle => 'Install Path';

  @override
  String gameDetailsCompressedAt(String value) {
    return 'Compressed $value';
  }

  @override
  String gameDetailsRemovedFromLibrary(String gameName) {
    return 'Removed \"$gameName\" from library. It will not reappear unless reinstalled.';
  }

  @override
  String get gameDetailsCopyPathTooltip => 'Copy path';

  @override
  String get gameDetailsInstallPathCopied => 'Install path copied.';

  @override
  String get gameDetailsStorageLegendCurrent => 'Current';

  @override
  String get gameDetailsStorageLegendOriginal => 'Original';

  @override
  String get gameDetailsStorageLegendSaved => 'Saved';

  @override
  String get trayOpenApp => 'Open Compact Games';

  @override
  String get trayPauseAutoCompression => 'Pause Auto-Compression';

  @override
  String get trayResumeAutoCompression => 'Resume Auto-Compression';

  @override
  String get trayCompressing => 'Compressing';

  @override
  String get trayPaused => 'Paused';

  @override
  String get trayError => 'Error';
}
