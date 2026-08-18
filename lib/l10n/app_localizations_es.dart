// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get algorithmXpress4k => 'XPRESS 4K (Rápido)';

  @override
  String get algorithmXpress8k => 'XPRESS 8K (Equilibrado)';

  @override
  String get algorithmXpress16k => 'XPRESS 16K (Mejor compresión)';

  @override
  String get algorithmLzx => 'LZX (Máximo)';

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
  String get platformCustom => 'Personalizado';

  @override
  String get platformApplication => 'Aplicación';

  @override
  String get addItemModeGame => 'Juego';

  @override
  String get addItemModeApplication => 'Aplicación';

  @override
  String get addApplicationPathHint =>
      'Pega la ruta de la carpeta de la aplicación o explora...';

  @override
  String get commonAdd => 'Agregar';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonDismissTooltip => 'Descartar';

  @override
  String get commonEnable => 'Activar';

  @override
  String get commonSet => 'Establecer';

  @override
  String get commonOpenFolder => 'Abrir carpeta';

  @override
  String get commonQuit => 'Salir';

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get commonNotAvailable => 'N/D';

  @override
  String commonGigabytes(String value) {
    return '$value GB';
  }

  @override
  String commonMegabytes(String count) {
    return '$count MB';
  }

  @override
  String get routeNotFoundTitle => 'Ruta no encontrada';

  @override
  String get routeNotFoundMessage => 'La ruta solicitada no existe.';

  @override
  String get settingsTitle => 'Configuración';

  @override
  String settingsLoadFailed(String errorMessage) {
    return 'No se pudo cargar la configuración: $errorMessage';
  }

  @override
  String get settingsAutomationSectionTitle => 'Automatización';

  @override
  String get settingsIdleThresholdLabel => 'Umbral de inactividad';

  @override
  String settingsMinutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String get settingsCpuThresholdLabel => 'Umbral de CPU';

  @override
  String settingsPercentShort(String percent) {
    return '$percent%';
  }

  @override
  String get settingsExactValueHint => 'Ingresa un valor exacto';

  @override
  String settingsRangeMinutes(int min, int max) {
    return 'Rango $min-$max min';
  }

  @override
  String settingsRangePercent(int min, int max) {
    return 'Rango $min-$max%';
  }

  @override
  String get settingsMinimizeToTrayOnCloseLabel =>
      'Minimizar a la bandeja al cerrar';

  @override
  String get settingsLaunchAtStartupLabel => 'Iniciar con Windows';

  @override
  String get settingsPathsSectionTitle => 'Rutas personalizadas';

  @override
  String get settingsPathsHint => 'Agrega una ruta extra de biblioteca';

  @override
  String get settingsNoCustomPaths =>
      'No hay rutas personalizadas configuradas.';

  @override
  String get settingsRemovePathTooltip => 'Quitar ruta';

  @override
  String get settingsCompressionSectionTitle => 'Compresión';

  @override
  String get settingsAlgorithmLabel => 'Algoritmo';

  @override
  String get settingsAlgorithmTooltip =>
      'Selecciona el algoritmo de compresión.';

  @override
  String get settingsAlgorithmRecommendedHint =>
      'XPRESS 8K es la opción recomendada para la mayoría de los juegos.';

  @override
  String get settingsIoThreadsTooltip =>
      'Sobrescribe la cantidad de hilos de E/S en paralelo.';

  @override
  String get settingsIoThreadsLabel => 'Hilos de E/S';

  @override
  String get settingsIoThreadsAuto => 'Automático';

  @override
  String settingsIoThreadsCount(int count) {
    return '$count hilos';
  }

  @override
  String get settingsIoThreadsHelp =>
      'Automático usa la recomendación actual del hardware.';

  @override
  String get settingsInventorySectionTitle => 'Inventario';

  @override
  String get settingsPauseWatcher => 'Pausar monitor';

  @override
  String get settingsResumeWatcher => 'Reanudar monitor';

  @override
  String get settingsWatcherAutomationEnabled =>
      'La automatización está supervisando el inventario de compresión.';

  @override
  String get settingsWatcherAutomationDisabled =>
      'La automatización está pausada para el inventario de compresión.';

  @override
  String get settingsSteamGridDbManagedOnce =>
      'Las portadas de SteamGridDB solo se obtienen una vez por juego, salvo que las actualices.';

  @override
  String get settingsLanguageSectionTitle => 'Idioma';

  @override
  String get settingsLanguageSelectorLabel => 'Idioma de la aplicación';

  @override
  String get settingsLanguageSelectorTooltip =>
      'Elige el idioma de la aplicación.';

  @override
  String get settingsLanguageSystemDefault => 'Predeterminado del sistema';

  @override
  String get settingsLanguageEnglish => 'Inglés';

  @override
  String get settingsLanguageSpanish => 'Español';

  @override
  String get settingsLanguageChineseSimplified => 'Chino simplificado';

  @override
  String get settingsIntegrationsSectionTitle => 'Integraciones';

  @override
  String get settingsApiKeySavedMessage => 'Clave API guardada.';

  @override
  String get settingsApiKeyCopiedMessage => 'Clave API copiada.';

  @override
  String get settingsSteamGridDbConnectedStatus =>
      'Clave API de SteamGridDB conectada';

  @override
  String get settingsSteamGridDbMissingStatus =>
      'Falta la clave API de SteamGridDB';

  @override
  String get settingsSteamGridDbBuiltInStatus =>
      'Servicio de portadas integrado activado';

  @override
  String get settingsSteamGridDbBuiltInModeLabel => 'Integrado';

  @override
  String get settingsSteamGridDbUserKeyModeLabel => 'Mi clave';

  @override
  String get settingsSteamGridDbExplanation =>
      'Compact Games puede obtener portadas de SteamGridDB mediante el servicio integrado. También puedes usar tu propia clave de SteamGridDB.';

  @override
  String get settingsSteamGridDbStep1 =>
      'Abre la página de preferencias de tu cuenta de SteamGridDB.';

  @override
  String get settingsSteamGridDbStep2 =>
      'Genera o copia tu clave API personal.';

  @override
  String get settingsSteamGridDbStep3 =>
      'Pégala aquí para habilitar búsquedas de portadas más completas.';

  @override
  String get settingsSteamGridDbUserKeyHelp =>
      'Tu clave permanece en almacenamiento seguro y solo se usa en el modo de clave propia, o como respaldo si el servicio integrado no está disponible temporalmente.';

  @override
  String get settingsSteamGridDbOpenButton => 'Abrir página API de SteamGridDB';

  @override
  String get settingsSteamGridDbApiKeyLabel => 'Clave API de SteamGridDB';

  @override
  String get settingsSteamGridDbApiKeyHint =>
      'Pega tu clave API de SteamGridDB';

  @override
  String get settingsSteamGridDbShowKeyTooltip => 'Mostrar clave';

  @override
  String get settingsSteamGridDbHideKeyTooltip => 'Ocultar clave';

  @override
  String get settingsSteamGridDbCopyKeyTooltip => 'Copiar clave';

  @override
  String get settingsSteamGridDbSaveButton => 'Guardar clave';

  @override
  String get settingsSteamGridDbRemoveButton => 'Quitar clave';

  @override
  String get settingsAboutSectionTitle => 'Acerca de';

  @override
  String get settingsAboutVersionLabel => 'Versión';

  @override
  String get settingsAboutCompactGuiCredit =>
      'Los datos de estimación de compresión los proporciona CompactGUI / IridiumIO y se obtienen en tiempo de ejecución desde las versiones de Compact Games.';

  @override
  String get settingsAboutSteamGridDbCredit =>
      'Las portadas las proporciona SteamGridDB. El servicio integrado devuelve URL de imágenes de SteamGridDB; la app descarga y guarda las imágenes localmente.';

  @override
  String get settingsAboutAutoCheckUpdatesLabel =>
      'Buscar actualizaciones automáticamente';

  @override
  String get settingsAboutUpdatesManagedBySteam =>
      'Steam administra las actualizaciones automáticamente.';

  @override
  String get settingsAboutCheckingForUpdatesStatus =>
      'Buscando actualizaciones...';

  @override
  String get settingsAboutUpToDateStatus => 'Tienes la versión más reciente';

  @override
  String get settingsAboutCheckAgainAction => 'Comprobar de nuevo';

  @override
  String get settingsAboutUpdateCheckFailedTitle =>
      'No se pudo comprobar si hay actualizaciones';

  @override
  String get settingsAboutUpdateFailedTitle => 'La actualización falló';

  @override
  String get settingsAboutRetryDownloadAction => 'Reintentar descarga';

  @override
  String get settingsAboutRetryCheckAction => 'Reintentar búsqueda';

  @override
  String get settingsAboutCheckForUpdatesAction => 'Buscar actualizaciones';

  @override
  String settingsAboutUpdateAvailableStatus(Object version) {
    return 'Actualización disponible: v$version';
  }

  @override
  String settingsAboutReleasedLabel(Object publishedAt) {
    return 'Publicado: $publishedAt';
  }

  @override
  String get settingsAboutDownloadUpdateAction => 'Descargar actualización';

  @override
  String get settingsAboutDownloadingUpdateStatus =>
      'Descargando actualización...';

  @override
  String get settingsAboutUpdateReadyToInstallStatus =>
      'La actualización se descargó y está lista para instalarse';

  @override
  String get settingsAboutWaitingForCompressionStatus =>
      'Esperando a que termine la compresión...';

  @override
  String get settingsAboutInstallUpdateAndRestartAction =>
      'Instalar actualización y reiniciar';

  @override
  String get settingsSafetySectionTitle => 'Seguridad';

  @override
  String get settingsAllowDirectStorageOverride =>
      'Permitir anulación de DirectStorage';

  @override
  String get settingsDirectStorageWarningLead =>
      'Úsalo solo si entiendes el riesgo.';

  @override
  String get settingsDirectStorageWarningBody =>
      'Los juegos con DirectStorage pueden cargar más lento después de la compresión.';

  @override
  String get settingsEnableDirectStorageOverrideTitle =>
      '¿Activar anulación de DirectStorage?';

  @override
  String get settingsEnableDirectStorageOverrideMessage =>
      'Esto permite comprimir juegos marcados con DirectStorage. Puede afectar el rendimiento de carga y la estabilidad.';

  @override
  String get settingsShareUnsupportedReportsLabel =>
      'Compartir informes de juegos no compatibles';

  @override
  String get settingsShareUnsupportedReportsDescription =>
      'Desactivado de forma predeterminada. Al activarlo, los informes estables pueden compartir el nombre de la carpeta del juego y metadatos de diagnóstico seudónimos; nunca se envían rutas completas ni resultados de compresión.';

  @override
  String get settingsShareUnsupportedReportsConfirmTitle =>
      '¿Compartir informes de juegos no compatibles?';

  @override
  String get settingsShareUnsupportedReportsConfirmMessage =>
      'Los informes que permanezcan activos durante siete días pueden enviar a Compact Games, a través de Cloudflare, el nombre de la carpeta del juego, un identificador seudónimo de instalación, la versión de la aplicación, marcas de tiempo y recuentos de informes. Nunca se envían rutas completas ni resultados de compresión. Puedes desactivarlo en cualquier momento para detener futuros envíos.';

  @override
  String get settingsWatcherStatusActive => 'Monitor activo';

  @override
  String get settingsWatcherStatusPaused => 'Monitor pausado';

  @override
  String get homeRefreshGamesTooltip => 'Actualizar juegos';

  @override
  String get homeCompressionInventoryTooltip =>
      'Abrir inventario de compresión';

  @override
  String get homeAddGameTooltip => 'Agregar juego';

  @override
  String get homeSettingsTooltip => 'Abrir configuración';

  @override
  String get homeSwitchToListViewTooltip => 'Cambiar a vista de lista';

  @override
  String get homeSwitchToGridViewTooltip => 'Cambiar a vista de cuadrícula';

  @override
  String get homeHeaderTagline => 'Ahorra espacio en tu computadora.';

  @override
  String homeHeaderReadyLine(int count) {
    return '$count juegos están listos para recuperar espacio.';
  }

  @override
  String get homeSearchGamesHint => 'Buscar juegos...';

  @override
  String get homePrimaryReviewEligible => 'Revisar juegos elegibles';

  @override
  String get homeEmptyTitle => 'No hay juegos en esta vista';

  @override
  String get homeEmptyMessage =>
      'Los juegos de Steam, Epic, GOG y otros lanzadores aparecerán aquí automáticamente.';

  @override
  String get homeEmptyGuidance =>
      'Actualiza el descubrimiento o agrega manualmente una carpeta de juego para empezar a revisar oportunidades de compresión.';

  @override
  String get homeLoadErrorTitle => 'No se pudo cargar tu biblioteca';

  @override
  String get homeLoadErrorGuidance =>
      'Vuelve a intentar el descubrimiento. Si sigue fallando, revisa las rutas de los lanzadores o agrega manualmente una carpeta de juego.';

  @override
  String get homeListEmptyTitle => 'Nada coincide con esta vista';

  @override
  String get homeListEmptyMessage =>
      'Limpia la búsqueda o los filtros actuales, o agrega manualmente una carpeta de juego.';

  @override
  String get homeStatusReadyToCompress => 'Listo';

  @override
  String homeAddedToLibraryMessage(String gameName) {
    return '\"$gameName\" se agregó a la biblioteca.';
  }

  @override
  String homeUpdatedInLibraryMessage(String gameName) {
    return '\"$gameName\" se actualizó en la biblioteca.';
  }

  @override
  String homeFailedToAddGameMessage(String errorMessage) {
    return 'No se pudo agregar el juego: $errorMessage';
  }

  @override
  String get homeInvalidPathMessage => 'La ruta seleccionada no es válida.';

  @override
  String get homeAddGameDialogTitle => 'Agregar juego';

  @override
  String get homeAddGamePathHint =>
      'Elige una carpeta de juego o un ejecutable';

  @override
  String get homeBrowseFolder => 'Explorar carpeta';

  @override
  String get homeBrowseExe => 'Explorar .exe';

  @override
  String get homeCoverArtNudgeMessage =>
      'El servicio de portadas integrado está disponible. Vuelve a activarlo en Configuración o agrega tu propia clave de SteamGridDB.';

  @override
  String get homeGoToSettingsButton => 'Ir a Configuración';

  @override
  String get homeOverviewEyebrow => 'Resumen de compresión';

  @override
  String homeOverviewReadyHeadline(int count) {
    return '$count juegos están listos para recuperar espacio.';
  }

  @override
  String homeOverviewReadySubtitle(String value) {
    return 'Mira qué juegos están listos para comprimir y cuánto espacio podrías ahorrar: $value.';
  }

  @override
  String get homeOverviewReadyCountLabel => 'Listos';

  @override
  String get homeOverviewReclaimableLabel => 'Espacio potencial';

  @override
  String get inventoryTitle => 'Inventario de compresión';

  @override
  String get inventoryRefreshTooltip => 'Actualizar inventario';

  @override
  String inventoryLoadFailed(String errorMessage) {
    return 'No se pudo cargar el inventario: $errorMessage';
  }

  @override
  String get inventorySearchHint => 'Buscar en el inventario...';

  @override
  String get inventorySortDirectionDescending => 'Descendente';

  @override
  String get inventorySortDirectionAscending => 'Ascendente';

  @override
  String get inventorySortLabel => 'Ordenar por';

  @override
  String get inventorySortSavingsPercent => 'Ahorro %';

  @override
  String get inventorySortOriginalSize => 'Tamaño original';

  @override
  String get inventorySortName => 'Nombre';

  @override
  String get inventorySortPlatform => 'Plataforma';

  @override
  String get inventoryHeaderGame => 'JUEGO';

  @override
  String get inventoryHeaderPlatform => 'PLATAFORMA';

  @override
  String get inventoryHeaderOriginal => 'ORIGINAL';

  @override
  String get inventoryHeaderCurrent => 'ACTUAL';

  @override
  String get inventoryHeaderSavings => 'AHORRO';

  @override
  String get inventoryHeaderLastChecked => 'ÚLTIMA REVISIÓN';

  @override
  String get inventoryHeaderWatcher => 'MONITOR';

  @override
  String get inventoryEmpty =>
      'Ningún juego coincide con los filtros actuales del inventario.';

  @override
  String get inventoryWatcherNotWatched => 'Sin monitor';

  @override
  String get inventoryWatcherWatched => 'Supervisado';

  @override
  String get inventoryWatcherPaused => 'Pausado';

  @override
  String get inventoryWatcherActive => 'Monitor activo';

  @override
  String get inventoryAlgorithmBadgeLabel => 'Algoritmo';

  @override
  String get inventoryWatcherBadgeLabel => 'Monitor';

  @override
  String get inventoryWatcherBadgeActive => 'Activo';

  @override
  String get inventoryWatcherBadgePaused => 'Pausado';

  @override
  String get inventoryPauseWatcher => 'Pausar monitor';

  @override
  String get inventoryResumeWatcher => 'Reanudar monitor';

  @override
  String inventoryWatcherSummary(String status) {
    return '$status.';
  }

  @override
  String get activityDismissMonitor => 'Cerrar monitor';

  @override
  String activityQueuedCount(int count) {
    return 'En cola ($count)';
  }

  @override
  String activityQueuePosition(int position) {
    return 'En cola, puesto $position';
  }

  @override
  String activityRemoveQueuedGame(String gameName) {
    return 'Quitar $gameName de la cola';
  }

  @override
  String get activityClearQueue => 'Vaciar cola';

  @override
  String get activityCompressing => 'Comprimiendo';

  @override
  String get activityDecompressing => 'Descomprimiendo';

  @override
  String get activityPreparing => 'Preparando...';

  @override
  String get activityScanningFiles => 'Escaneando archivos...';

  @override
  String get activityScanningCompressedFiles =>
      'Escaneando archivos comprimidos...';

  @override
  String activityAmountSaved(String value) {
    return 'Ahorra $value';
  }

  @override
  String activityAmountRestoring(String value) {
    return 'Restaurando $value';
  }

  @override
  String activityApproxFileProgress(int processed, int total) {
    return '~$processed/$total archivos';
  }

  @override
  String activityFileProgress(int processed, int total) {
    return '$processed/$total archivos';
  }

  @override
  String get gameStatusDirectStorage => 'DirectStorage';

  @override
  String get gameStatusUnsupported => 'No compatible';

  @override
  String get gameStatusNotCompressed => 'Sin comprimir';

  @override
  String gameSavedGigabytes(String gigabytes) {
    return 'Ahorra $gigabytes GB';
  }

  @override
  String gameEstimatedSaveableGigabytes(String gigabytes) {
    return '$gigabytes GB ahorrables';
  }

  @override
  String get gameEstimateCommunityTooltip =>
      'Basado en datos de la comunidad de CompactGUI';

  @override
  String gameMarkedUnsupported(String gameName) {
    return '\"$gameName\" se marcó como no compatible.';
  }

  @override
  String gameMarkedSupported(String gameName) {
    return '\"$gameName\" se marcó como compatible.';
  }

  @override
  String get gameMenuViewDetails => 'Ver detalles';

  @override
  String get gameMenuLaunch => 'Iniciar juego';

  @override
  String gameLaunchAttempting(String gameName) {
    return 'Intentando iniciar \"$gameName\"...';
  }

  @override
  String gameLaunchTargetNotFound(String gameName) {
    return 'No se encontró un ejecutable para iniciar \"$gameName\".';
  }

  @override
  String gameLaunchFailed(String gameName) {
    return 'No se pudo iniciar \"$gameName\".';
  }

  @override
  String get gameMenuCompressNow => 'Comprimir ahora';

  @override
  String get gameMenuRecompress => 'Volver a comprimir';

  @override
  String get gameMenuDecompress => 'Descomprimir';

  @override
  String get gameMenuMarkUnsupported => 'Marcar como no compatible';

  @override
  String get gameMenuMarkSupported => 'Marcar como compatible';

  @override
  String get gameMenuExcludeFromAutoCompression =>
      'Excluir de la compresión automática';

  @override
  String get gameMenuIncludeInAutoCompression =>
      'Incluir en la compresión automática';

  @override
  String get gameMenuRemoveFromLibrary => 'Quitar de la biblioteca';

  @override
  String gameRemovedFromLibrary(String gameName) {
    return '\"$gameName\" se quitó de la biblioteca.';
  }

  @override
  String gameRemovalPersistFailed(String gameName) {
    return 'No se pudo guardar la eliminación de \"$gameName\". Actualizando la biblioteca.';
  }

  @override
  String get gameDetailsTitleFallback => 'Detalles del juego';

  @override
  String get gameDetailsNotFound => 'Juego no encontrado.';

  @override
  String get gameDetailsActivityCompressingNow => 'Comprimiendo ahora';

  @override
  String get gameDetailsActivityDecompressingNow => 'Descomprimiendo ahora';

  @override
  String get gameDetailsStatusCompressed => 'Comprimido';

  @override
  String get gameDetailsStatusReady => 'Listo';

  @override
  String get gameDetailsDirectStorageWarning =>
      'Se detectó DirectStorage. La compresión puede afectar el rendimiento en ejecución.';

  @override
  String get gameDetailsUnsupportedWarning =>
      'Marcado por la comunidad como no compatible.';

  @override
  String get gameDetailsStatusGroupTitle => 'Estado';

  @override
  String get gameDetailsPlatformLabel => 'Plataforma';

  @override
  String get gameDetailsCompressionLabel => 'Compresión';

  @override
  String get gameDetailsCompressionCompressed => 'Comprimido';

  @override
  String get gameDetailsCompressionNotCompressed => 'Sin comprimir';

  @override
  String get gameDetailsDirectStorageLabel => 'DirectStorage';

  @override
  String get gameDetailsDirectStorageDetected => 'Detectado';

  @override
  String get gameDetailsDirectStorageNotDetected => 'No detectado';

  @override
  String get gameDetailsUnsupportedLabel => 'Compatibilidad';

  @override
  String get gameDetailsUnsupportedFlagged => 'Marcado';

  @override
  String get gameDetailsUnsupportedNotFlagged => 'Sin marcar';

  @override
  String get gameDetailsAutoCompressLabel => 'Compresión automática';

  @override
  String get gameDetailsAutoCompressExcluded => 'Excluido';

  @override
  String get gameDetailsAutoCompressIncluded => 'Incluido';

  @override
  String get gameDetailsStorageGroupTitle => 'Almacenamiento';

  @override
  String get gameDetailsOriginalSizeLabel => 'Tamaño original';

  @override
  String get gameDetailsCurrentSizeLabel => 'Tamaño actual';

  @override
  String get gameDetailsSpaceSavedLabel => 'Espacio ahorrado';

  @override
  String get gameDetailsSavingsLabel => 'Ahorro';

  @override
  String get gameDetailsEstimatedSavingsLabel => 'Estimación';

  @override
  String get gameDetailsInstallPathGroupTitle => 'Ruta de instalación';

  @override
  String gameDetailsCompressedAt(String value) {
    return 'Comprimido $value';
  }

  @override
  String gameDetailsRemovedFromLibrary(String gameName) {
    return 'Se quitó \"$gameName\" de la biblioteca. No volverá a aparecer salvo que se reinstale.';
  }

  @override
  String get gameDetailsCopyPathTooltip => 'Copiar ruta';

  @override
  String get gameDetailsInstallPathCopied => 'Ruta de instalación copiada.';

  @override
  String get gameDetailsStorageLegendCurrent => 'Actual';

  @override
  String get gameDetailsStorageLegendOriginal => 'Original';

  @override
  String get gameDetailsStorageLegendSaved => 'Ahorrado';

  @override
  String get trayOpenApp => 'Abrir Compact Games';

  @override
  String get trayPauseAutoCompression => 'Pausar compresión automática';

  @override
  String get trayResumeAutoCompression => 'Reanudar compresión automática';

  @override
  String get trayCompressing => 'Comprimiendo';

  @override
  String get trayPaused => 'Pausado';

  @override
  String get trayError => 'Error';

  @override
  String get settingsRestoreSectionTitle => 'Restaurar juegos comprimidos';

  @override
  String get settingsRestoreDescription =>
      'Restaura solo los juegos registrados como comprimidos correctamente por Compact Games. El estado real del sistema de archivos se comprueba de nuevo antes de descomprimir.';

  @override
  String get settingsRestoreChecking =>
      'Comprobando juegos administrados y espacio libre...';

  @override
  String get settingsRestoreNoGames =>
      'Ningún juego administrado por Compact Games necesita restauración.';

  @override
  String settingsRestoreSummary(int count, String space) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count juegos necesitan hasta $space de espacio adicional.',
      one: '1 juego necesita hasta $space de espacio adicional.',
    );
    return '$_temp0';
  }

  @override
  String get settingsRestoreLongRuntime =>
      'Esto puede tardar mucho. La automatización se pausará y se rechazarán nuevos trabajos de compresión hasta que termine la restauración o se omitan los errores.';

  @override
  String settingsRestoreDriveSpace(
    String drive,
    String required,
    String available,
  ) {
    return '$drive: se requieren $required, hay $available disponibles';
  }

  @override
  String get settingsRestoreDriveInsufficient =>
      'No hay suficiente espacio libre en una o más unidades. Libera espacio antes de restaurar.';

  @override
  String get settingsRestoreAction =>
      'Restaurar todos los juegos administrados';

  @override
  String get settingsRestoreConfirmTitle =>
      '¿Restaurar todos los juegos administrados?';

  @override
  String settingsRestoreConfirmBody(int count, String space) {
    return 'Se pondrán $count juegos en la cola de descompresión. Pueden requerirse hasta $space de espacio adicional. Mantén Compact Games abierto hasta que termine la cola.';
  }

  @override
  String settingsRestoreProgress(int completed, int total) {
    return 'Restaurados $completed de $total juegos';
  }

  @override
  String get settingsRestoreFailuresTitle => 'Errores de restauración';

  @override
  String get settingsRestoreFailureAlreadyQueued =>
      'El juego ya tiene una operación en cola.';

  @override
  String get settingsRestoreFailureCancelled => 'Se canceló la descompresión.';

  @override
  String get settingsRestoreFailureFailed => 'Error en la descompresión.';

  @override
  String get settingsRestoreFailureIncomplete => 'La descompresión no terminó.';

  @override
  String settingsRestoreFailureError(String error) {
    return 'Error en la descompresión: $error';
  }

  @override
  String get settingsRestoreSkip => 'Omitir';

  @override
  String settingsRestoreSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count juegos omitidos permanecen comprimidos.',
      one: '1 juego omitido permanece comprimido.',
    );
    return '$_temp0';
  }

  @override
  String get settingsRestoreSuccess =>
      'Todos los juegos administrados se restauraron. Ahora puedes desinstalar Compact Games.';

  @override
  String get settingsRestoreUninstallAction => 'Desinstalar Compact Games';

  @override
  String get settingsRestoreUninstallNotFound =>
      'No se encontró el desinstalador de Compact Games.';

  @override
  String get settingsRestoreRefresh => 'Volver a comprobar';

  @override
  String settingsRestoreLoadFailed(String error) {
    return 'No se pudieron comprobar los juegos administrados: $error';
  }

  @override
  String get inventoryRescanCompleted => 'Inventario recalculado';

  @override
  String get inventoryRescanFailed => 'No se pudo recalcular el inventario';

  @override
  String get inventoryRescanAlreadyRunning => 'Ya hay un recálculo en curso';

  @override
  String get libraryHomeRowTitle => 'Inicio de la biblioteca';

  @override
  String get libraryHomeRowSubtitle => 'Resumen';

  @override
  String get libraryHomeHighlightsHeading => 'Destacados de la biblioteca';

  @override
  String get libraryHomeTotalGamesLabel => 'Juegos';

  @override
  String get libraryHomeCompressedLabel => 'Comprimidos';

  @override
  String get libraryHomeSpaceSavedLabel => 'Espacio ahorrado';

  @override
  String get libraryHomeLargestInstallLabel => 'Instalación más grande';

  @override
  String get libraryHomeBiggestSaverLabel => 'Mayor ahorro';

  @override
  String get libraryHomeRecentlyCompressedLabel => 'Comprimido recientemente';

  @override
  String get libraryHomeHighlightEmpty => 'Nada todavía';

  @override
  String get libraryHomeEmptyTitle => 'Aún no se han detectado juegos';

  @override
  String get libraryHomeEmptyMessage =>
      'Añade una carpeta de juegos o vuelve a escanear para crear tu biblioteca.';

  @override
  String get libraryHomeNewsHeading => 'Novedades';

  @override
  String get libraryHomeNewsSourceSteam => 'Comunidad de Steam';

  @override
  String get libraryHomeNewsStale => 'Mostrando elementos guardados';

  @override
  String get settingsAboutWebsiteAction => 'Sitio web';

  @override
  String get settingsAboutPrivacyPolicyAction => 'Política de privacidad';
}
