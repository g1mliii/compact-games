// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get algorithmXpress4k => 'XPRESS 4K（快速）';

  @override
  String get algorithmXpress8k => 'XPRESS 8K（平衡）';

  @override
  String get algorithmXpress16k => 'XPRESS 16K（更高压缩率）';

  @override
  String get algorithmLzx => 'LZX（最高）';

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
  String get platformCustom => '自定义';

  @override
  String get platformApplication => '应用程序';

  @override
  String get addItemModeGame => '游戏';

  @override
  String get addItemModeApplication => '应用程序';

  @override
  String get addApplicationPathHint => '粘贴应用程序文件夹路径或浏览...';

  @override
  String get commonAdd => '添加';

  @override
  String get commonCancel => '取消';

  @override
  String get commonDismissTooltip => '关闭';

  @override
  String get commonEnable => '启用';

  @override
  String get commonSet => '设置';

  @override
  String get commonOpenFolder => '打开文件夹';

  @override
  String get commonQuit => '退出';

  @override
  String get commonRetry => '重试';

  @override
  String get commonNotAvailable => '无';

  @override
  String commonGigabytes(String value) {
    return '$value GB';
  }

  @override
  String commonMegabytes(String count) {
    return '$count MB';
  }

  @override
  String get routeNotFoundTitle => '未找到路由';

  @override
  String get routeNotFoundMessage => '请求的路由不存在。';

  @override
  String get settingsTitle => '设置';

  @override
  String settingsLoadFailed(String errorMessage) {
    return '加载设置失败：$errorMessage';
  }

  @override
  String get settingsAutomationSectionTitle => '自动化';

  @override
  String get settingsIdleThresholdLabel => '空闲阈值';

  @override
  String settingsMinutesShort(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get settingsCpuThresholdLabel => 'CPU 阈值';

  @override
  String settingsPercentShort(String percent) {
    return '$percent%';
  }

  @override
  String get settingsExactValueHint => '输入精确值';

  @override
  String settingsRangeMinutes(int min, int max) {
    return '范围 $min-$max 分钟';
  }

  @override
  String settingsRangePercent(int min, int max) {
    return '范围 $min-$max%';
  }

  @override
  String get settingsMinimizeToTrayOnCloseLabel => '关闭时最小化到托盘';

  @override
  String get settingsPathsSectionTitle => '自定义路径';

  @override
  String get settingsPathsHint => '添加额外的游戏库文件夹路径';

  @override
  String get settingsNoCustomPaths => '尚未配置自定义游戏库路径。';

  @override
  String get settingsRemovePathTooltip => '移除路径';

  @override
  String get settingsCompressionSectionTitle => '压缩';

  @override
  String get settingsAlgorithmLabel => '算法';

  @override
  String get settingsAlgorithmTooltip => '选择压缩算法。';

  @override
  String get settingsAlgorithmRecommendedHint => 'XPRESS 8K 是大多数游戏的推荐默认选项。';

  @override
  String get settingsIoThreadsTooltip => '覆盖并行 I/O 线程数。';

  @override
  String get settingsIoThreadsLabel => 'I/O 线程';

  @override
  String get settingsIoThreadsAuto => '自动';

  @override
  String settingsIoThreadsCount(int count) {
    return '$count 个线程';
  }

  @override
  String get settingsIoThreadsHelp => '自动会匹配当前硬件建议值。';

  @override
  String get settingsInventorySectionTitle => '清单';

  @override
  String get settingsPauseWatcher => '暂停监视器';

  @override
  String get settingsResumeWatcher => '恢复监视器';

  @override
  String get settingsWatcherAutomationEnabled => '自动化当前正在监视压缩清单。';

  @override
  String get settingsWatcherAutomationDisabled => '自动化当前已暂停，不会监视压缩清单。';

  @override
  String get settingsEnableFullMetadataInventoryScan => '启用完整元数据清单扫描';

  @override
  String get settingsInventoryAdvancedDescription => '为清单表收集更丰富的元数据。扫描时可能会更慢。';

  @override
  String get settingsSteamGridDbManagedOnce =>
      'SteamGridDB 封面每个游戏只会获取一次，除非你手动刷新。';

  @override
  String get settingsLanguageSectionTitle => '语言';

  @override
  String get settingsLanguageSelectorLabel => '显示语言';

  @override
  String get settingsLanguageSelectorTooltip => '选择应用语言。';

  @override
  String get settingsLanguageSystemDefault => '跟随系统';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageSpanish => 'Español';

  @override
  String get settingsLanguageChineseSimplified => '简体中文';

  @override
  String get settingsIntegrationsSectionTitle => '集成';

  @override
  String get settingsApiKeySavedMessage => 'API 密钥已保存。';

  @override
  String get settingsApiKeyCopiedMessage => 'API 密钥已复制。';

  @override
  String get settingsSteamGridDbConnectedStatus => 'SteamGridDB API 密钥已连接';

  @override
  String get settingsSteamGridDbMissingStatus => '缺少 SteamGridDB API 密钥';

  @override
  String get settingsSteamGridDbExplanation =>
      'SteamGridDB 可提升手动添加或难以匹配游戏的封面质量。';

  @override
  String get settingsSteamGridDbStep1 => '打开你的 SteamGridDB 账户偏好设置页面。';

  @override
  String get settingsSteamGridDbStep2 => '生成或复制你的个人 API 密钥。';

  @override
  String get settingsSteamGridDbStep3 => '将其粘贴到这里，以启用更丰富的封面查询。';

  @override
  String get settingsSteamGridDbOpenButton => '打开 SteamGridDB API 页面';

  @override
  String get settingsSteamGridDbApiKeyLabel => 'SteamGridDB API 密钥';

  @override
  String get settingsSteamGridDbApiKeyHint => '粘贴你的 SteamGridDB API 密钥';

  @override
  String get settingsSteamGridDbShowKeyTooltip => '显示密钥';

  @override
  String get settingsSteamGridDbHideKeyTooltip => '隐藏密钥';

  @override
  String get settingsSteamGridDbCopyKeyTooltip => '复制密钥';

  @override
  String get settingsSteamGridDbSaveButton => '保存密钥';

  @override
  String get settingsSteamGridDbRemoveButton => '移除密钥';

  @override
  String get settingsSafetySectionTitle => '安全';

  @override
  String get settingsAllowDirectStorageOverride => '允许绕过 DirectStorage 保护';

  @override
  String get settingsDirectStorageWarningLead => '仅在你清楚风险时使用。';

  @override
  String get settingsDirectStorageWarningBody => 'DirectStorage 游戏在压缩后可能加载更慢。';

  @override
  String get settingsEnableDirectStorageOverrideTitle => '启用 DirectStorage 绕过？';

  @override
  String get settingsEnableDirectStorageOverrideMessage =>
      '这会允许压缩被标记为 DirectStorage 的游戏，可能影响加载性能和稳定性。';

  @override
  String get settingsWatcherStatusActive => '监视器已启用';

  @override
  String get settingsWatcherStatusPaused => '监视器已暂停';

  @override
  String get homeRefreshGamesTooltip => '刷新游戏';

  @override
  String get homeCompressionInventoryTooltip => '打开压缩清单';

  @override
  String get homeAddGameTooltip => '添加游戏';

  @override
  String get homeSettingsTooltip => '打开设置';

  @override
  String get homeSwitchToListViewTooltip => '切换到列表视图';

  @override
  String get homeSwitchToGridViewTooltip => '切换到网格视图';

  @override
  String get homeCollapseOverviewTooltip => '收起概览';

  @override
  String get homeExpandOverviewTooltip => '展开概览';

  @override
  String get homeHeaderTagline => '为你的电脑节省空间。';

  @override
  String homeHeaderReadyLine(int count) {
    return '$count 款游戏已可释放空间。';
  }

  @override
  String get homeSearchGamesHint => '搜索游戏...';

  @override
  String get homePrimaryReviewEligible => '查看可压缩游戏';

  @override
  String get homePrimaryOpenInventory => '打开清单';

  @override
  String get homePrimaryAddGame => '添加游戏';

  @override
  String get homeEmptyTitle => '当前视图中没有游戏';

  @override
  String get homeEmptyMessage => 'Steam、Epic、GOG 和其他启动器中的游戏会自动出现在这里。';

  @override
  String get homeEmptyGuidance => '刷新扫描，或手动添加游戏文件夹，以开始查看可回收空间。';

  @override
  String get homeLoadErrorTitle => '无法加载你的游戏库';

  @override
  String get homeLoadErrorGuidance => '请重试扫描。如果问题仍然存在，请检查启动器路径，或手动添加游戏文件夹。';

  @override
  String get homeListEmptyTitle => '当前视图没有匹配项';

  @override
  String get homeListEmptyMessage => '清除当前搜索或筛选条件，或手动添加一个游戏文件夹。';

  @override
  String get homeSelectGameTitle => '选择一个游戏';

  @override
  String get homeSelectGameMessage => '选中一个标题以查看体积、压缩历史和下一步操作。';

  @override
  String get homeStatusReadyToCompress => '就绪';

  @override
  String homeAddedToLibraryMessage(String gameName) {
    return '“$gameName”已添加到库中。';
  }

  @override
  String homeUpdatedInLibraryMessage(String gameName) {
    return '“$gameName”已在库中更新。';
  }

  @override
  String homeFailedToAddGameMessage(String errorMessage) {
    return '添加游戏失败：$errorMessage';
  }

  @override
  String get homeInvalidPathMessage => '所选路径无效。';

  @override
  String get homeAddGameDialogTitle => '添加游戏';

  @override
  String get homeAddGamePathHint => '选择游戏文件夹或可执行文件';

  @override
  String get homeBrowseFolder => '浏览文件夹';

  @override
  String get homeBrowseExe => '浏览 .exe';

  @override
  String get homeCoverArtNudgeMessage => '在设置中连接 SteamGridDB，以改进封面匹配。';

  @override
  String get homeGoToSettingsButton => '前往设置';

  @override
  String get homeOverviewEyebrow => '压缩概览';

  @override
  String get homeOverviewEmptyHeadline => '先导入你的游戏库，再快速腾出空间。';

  @override
  String get homeOverviewEmptySubtitle => '扫描你的启动器，或手动添加游戏文件夹，开始显示可回收空间。';

  @override
  String homeOverviewReadyHeadline(int count) {
    return '$count 款游戏已可释放空间。';
  }

  @override
  String homeOverviewReadySubtitle(String value) {
    return '查看哪些游戏已准备好压缩，以及你可能节省多少空间：$value。';
  }

  @override
  String get homeOverviewProtectedHeadline => '游戏库已发现完成，但这些标题仍保持受保护状态。';

  @override
  String get homeOverviewProtectedSubtitle =>
      '在强制压缩之前，请先在清单中检查 DirectStorage 和不受支持的游戏。';

  @override
  String get homeOverviewManagedHeadline => '你的已压缩游戏库正在稳住空间占用。';

  @override
  String get homeOverviewManagedSubtitle => '前往清单查看已节省的空间，并在新游戏出现时及时处理。';

  @override
  String get homeOverviewReadyCountLabel => '待压缩';

  @override
  String get homeOverviewCompressedCountLabel => '已压缩';

  @override
  String get homeOverviewProtectedCountLabel => '受保护';

  @override
  String get homeOverviewReclaimableLabel => '潜在空间';

  @override
  String get inventoryTitle => '压缩清单';

  @override
  String get inventoryRefreshTooltip => '刷新清单';

  @override
  String inventoryLoadFailed(String errorMessage) {
    return '加载清单失败：$errorMessage';
  }

  @override
  String get inventorySearchHint => '搜索清单...';

  @override
  String get inventorySortDirectionDescending => '降序';

  @override
  String get inventorySortDirectionAscending => '升序';

  @override
  String get inventorySortLabel => '排序方式';

  @override
  String get inventorySortSavingsPercent => '节省 %';

  @override
  String get inventorySortOriginalSize => '原始大小';

  @override
  String get inventorySortName => '名称';

  @override
  String get inventorySortPlatform => '平台';

  @override
  String get inventoryHeaderGame => '游戏';

  @override
  String get inventoryHeaderPlatform => '平台';

  @override
  String get inventoryHeaderOriginal => '原始';

  @override
  String get inventoryHeaderCurrent => '当前';

  @override
  String get inventoryHeaderSavings => '节省';

  @override
  String get inventoryHeaderLastChecked => '最近检查';

  @override
  String get inventoryHeaderWatcher => '监视器';

  @override
  String get inventoryEmpty => '当前清单筛选条件下没有匹配的游戏。';

  @override
  String get inventoryWatcherNotWatched => '未监视';

  @override
  String get inventoryWatcherWatched => '已监视';

  @override
  String get inventoryWatcherPaused => '已暂停';

  @override
  String get inventoryWatcherActive => '监视器已启用';

  @override
  String get inventoryAlgorithmBadgeLabel => '算法';

  @override
  String get inventoryWatcherBadgeLabel => '监视器';

  @override
  String get inventoryWatcherBadgeActive => '启用';

  @override
  String get inventoryWatcherBadgePaused => '暂停';

  @override
  String get inventoryPauseWatcher => '暂停监视器';

  @override
  String get inventoryResumeWatcher => '恢复监视器';

  @override
  String get inventoryAdvancedMetadataScanOn => '高级元数据扫描：开启';

  @override
  String get inventoryAdvancedMetadataScanOff => '高级元数据扫描：关闭';

  @override
  String get inventoryRunFullRescan => '执行完整清单重扫';

  @override
  String get inventoryRescanUnavailableWhileLoading => '加载期间无法重新扫描';

  @override
  String inventoryWatcherSummary(String status) {
    return '$status。';
  }

  @override
  String get activityDismissMonitor => '关闭监视器';

  @override
  String get activityCompressing => '正在压缩';

  @override
  String get activityDecompressing => '正在解压';

  @override
  String get activityPreparing => '准备中...';

  @override
  String get activityScanningFiles => '正在扫描文件...';

  @override
  String get activityScanningCompressedFiles => '正在扫描已压缩文件...';

  @override
  String activityAmountSaved(String value) {
    return '已节省 $value';
  }

  @override
  String activityAmountRestoring(String value) {
    return '正在恢复 $value';
  }

  @override
  String activityApproxFileProgress(int processed, int total) {
    return '~$processed/$total 个文件';
  }

  @override
  String activityFileProgress(int processed, int total) {
    return '$processed/$total 个文件';
  }

  @override
  String activitySecondsRemaining(int seconds) {
    return '剩余 $seconds 秒';
  }

  @override
  String activityMinutesRemaining(int minutes) {
    return '剩余 $minutes 分钟';
  }

  @override
  String activityHoursMinutesRemaining(int hours, int minutes) {
    return '剩余 $hours 小时 $minutes 分钟';
  }

  @override
  String get gameStatusDirectStorage => 'DirectStorage';

  @override
  String get gameStatusUnsupported => '不支持';

  @override
  String get gameStatusNotCompressed => '未压缩';

  @override
  String gameSavedGigabytes(String gigabytes) {
    return '已节省 $gigabytes GB';
  }

  @override
  String gameEstimatedSaveableGigabytes(String gigabytes) {
    return '可节省 $gigabytes GB';
  }

  @override
  String gameMarkedUnsupported(String gameName) {
    return '“$gameName”已标记为不支持。';
  }

  @override
  String gameMarkedSupported(String gameName) {
    return '“$gameName”已标记为支持。';
  }

  @override
  String get gameMenuViewDetails => '查看详情';

  @override
  String get gameMenuCompressNow => '立即压缩';

  @override
  String get gameMenuDecompress => '解压';

  @override
  String get gameMenuMarkUnsupported => '标记为不支持';

  @override
  String get gameMenuMarkSupported => '标记为支持';

  @override
  String get gameMenuExcludeFromAutoCompression => '从自动压缩中排除';

  @override
  String get gameMenuIncludeInAutoCompression => '加入自动压缩';

  @override
  String get gameMenuRemoveFromLibrary => '从库中移除';

  @override
  String gameRemovedFromLibrary(String gameName) {
    return '“$gameName”已从库中移除。';
  }

  @override
  String gameRemovalPersistFailed(String gameName) {
    return '无法保存“$gameName”的移除操作，正在刷新游戏库。';
  }

  @override
  String get gameConfirmCompressionTitle => '确认压缩';

  @override
  String gameConfirmCompressionMessage(String gameName) {
    return '要压缩“$gameName”吗？这可能影响磁盘占用和运行时性能。';
  }

  @override
  String get gameConfirmCompressionAction => '压缩';

  @override
  String get gameDetailsTitleFallback => '游戏详情';

  @override
  String get gameDetailsNotFound => '未找到游戏。';

  @override
  String get gameDetailsActivityCompressingNow => '正在压缩';

  @override
  String get gameDetailsActivityDecompressingNow => '正在解压';

  @override
  String gameDetailsLastCompressedBadge(String value) {
    return '上次压缩 $value';
  }

  @override
  String get gameDetailsStatusCompressed => '已压缩';

  @override
  String get gameDetailsStatusReady => '就绪';

  @override
  String get gameDetailsDirectStorageWarning =>
      '检测到 DirectStorage。压缩可能影响运行时性能。';

  @override
  String get gameDetailsUnsupportedWarning => '已由社区标记为不受支持。';

  @override
  String get gameDetailsStatusGroupTitle => '状态';

  @override
  String get gameDetailsPlatformLabel => '平台';

  @override
  String get gameDetailsCompressionLabel => '压缩';

  @override
  String get gameDetailsCompressionCompressed => '已压缩';

  @override
  String get gameDetailsCompressionNotCompressed => '未压缩';

  @override
  String get gameDetailsDirectStorageLabel => 'DirectStorage';

  @override
  String get gameDetailsDirectStorageDetected => '已检测';

  @override
  String get gameDetailsDirectStorageNotDetected => '未检测';

  @override
  String get gameDetailsUnsupportedLabel => '兼容性';

  @override
  String get gameDetailsUnsupportedFlagged => '已标记';

  @override
  String get gameDetailsUnsupportedNotFlagged => '未标记';

  @override
  String get gameDetailsAutoCompressLabel => '自动压缩';

  @override
  String get gameDetailsAutoCompressExcluded => '已排除';

  @override
  String get gameDetailsAutoCompressIncluded => '已包含';

  @override
  String get gameDetailsStorageGroupTitle => '存储';

  @override
  String get gameDetailsOriginalSizeLabel => '原始大小';

  @override
  String get gameDetailsCurrentSizeLabel => '当前大小';

  @override
  String get gameDetailsSpaceSavedLabel => '已节省空间';

  @override
  String get gameDetailsSavingsLabel => '节省';

  @override
  String get gameDetailsInstallPathGroupTitle => '安装路径';

  @override
  String gameDetailsCompressedAt(String value) {
    return '压缩于 $value';
  }

  @override
  String gameDetailsRemovedFromLibrary(String gameName) {
    return '“$gameName”已从库中移除。除非重新安装，否则不会再次出现。';
  }

  @override
  String get gameDetailsCopyPathTooltip => '复制路径';

  @override
  String get gameDetailsInstallPathCopied => '安装路径已复制。';

  @override
  String get gameDetailsStorageLegendCurrent => '当前';

  @override
  String get gameDetailsStorageLegendOriginal => '原始';

  @override
  String get gameDetailsStorageLegendSaved => '已节省';

  @override
  String get trayOpenApp => '打开 Compact Games';

  @override
  String get trayPauseAutoCompression => '暂停自动压缩';

  @override
  String get trayResumeAutoCompression => '恢复自动压缩';

  @override
  String get trayCompressing => '正在压缩';

  @override
  String get trayPaused => '已暂停';

  @override
  String get trayError => '错误';
}
