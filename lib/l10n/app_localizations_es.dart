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
  String get settingsEnableFullMetadataInventoryScan =>
      'Activar escaneo completo de metadatos';

  @override
  String get settingsInventoryAdvancedDescription =>
      'Recopila metadatos más ricos para la tabla del inventario. Puede tardar más durante los escaneos.';

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
  String get settingsSteamGridDbExplanation =>
      'SteamGridDB mejora la calidad de las portadas para juegos agregados manualmente o difíciles de identificar.';

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
  String get homeCollapseOverviewTooltip => 'Contraer resumen';

  @override
  String get homeExpandOverviewTooltip => 'Expandir resumen';

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
  String get homePrimaryOpenInventory => 'Abrir inventario';

  @override
  String get homePrimaryAddGame => 'Agregar juego';

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
  String get homeSelectGameTitle => 'Elige un juego';

  @override
  String get homeSelectGameMessage =>
      'Selecciona un título para revisar su tamaño, historial de compresión y próximas acciones.';

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
      'Conecta SteamGridDB en Configuración para mejorar la coincidencia de portadas.';

  @override
  String get homeGoToSettingsButton => 'Ir a Configuración';

  @override
  String get homeOverviewEyebrow => 'Resumen de compresión';

  @override
  String get homeOverviewEmptyHeadline =>
      'Trae tu biblioteca. Luego haz espacio rápido.';

  @override
  String get homeOverviewEmptySubtitle =>
      'Escanea tus lanzadores o agrega manualmente una carpeta de juego para empezar a mostrar espacio recuperable.';

  @override
  String homeOverviewReadyHeadline(int count) {
    return '$count juegos están listos para recuperar espacio.';
  }

  @override
  String homeOverviewReadySubtitle(String value) {
    return 'Mira qué juegos están listos para comprimir y cuánto espacio podrías ahorrar: $value.';
  }

  @override
  String get homeOverviewProtectedHeadline =>
      'La biblioteca ya está detectada, pero estos títulos siguen protegidos.';

  @override
  String get homeOverviewProtectedSubtitle =>
      'Revisa los juegos con DirectStorage o incompatibles en el inventario antes de forzar la compresión.';

  @override
  String get homeOverviewManagedHeadline =>
      'Tu biblioteca comprimida está aguantando la línea.';

  @override
  String get homeOverviewManagedSubtitle =>
      'Consulta el inventario para ver el espacio ahorrado y revisar títulos nuevos cuando aparezcan.';

  @override
  String get homeOverviewReadyCountLabel => 'Listos';

  @override
  String get homeOverviewCompressedCountLabel => 'Comprimidos';

  @override
  String get homeOverviewProtectedCountLabel => 'Protegidos';

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
  String get inventoryAdvancedMetadataScanOn =>
      'Escaneo avanzado de metadatos: activado';

  @override
  String get inventoryAdvancedMetadataScanOff =>
      'Escaneo avanzado de metadatos: desactivado';

  @override
  String get inventoryRunFullRescan =>
      'Ejecutar reescaneo completo del inventario';

  @override
  String get inventoryRescanUnavailableWhileLoading =>
      'Reescaneo no disponible mientras carga';

  @override
  String inventoryWatcherSummary(String status) {
    return '$status.';
  }

  @override
  String get activityDismissMonitor => 'Cerrar monitor';

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
  String activitySecondsRemaining(int seconds) {
    return 'Quedan ${seconds}s';
  }

  @override
  String activityMinutesRemaining(int minutes) {
    return 'Quedan $minutes min';
  }

  @override
  String activityHoursMinutesRemaining(int hours, int minutes) {
    return 'Quedan $hours h $minutes min';
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
  String get gameMenuCompressNow => 'Comprimir ahora';

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
  String get gameConfirmCompressionTitle => 'Confirmar compresión';

  @override
  String gameConfirmCompressionMessage(String gameName) {
    return '¿Comprimir \"$gameName\"? Esto puede afectar el uso del disco y el rendimiento en ejecución.';
  }

  @override
  String get gameConfirmCompressionAction => 'Comprimir';

  @override
  String get gameDetailsTitleFallback => 'Detalles del juego';

  @override
  String get gameDetailsNotFound => 'Juego no encontrado.';

  @override
  String get gameDetailsActivityCompressingNow => 'Comprimiendo ahora';

  @override
  String get gameDetailsActivityDecompressingNow => 'Descomprimiendo ahora';

  @override
  String gameDetailsLastCompressedBadge(String value) {
    return 'Última compresión $value';
  }

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
  String get trayOpenApp => 'Abrir PressPlay';

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
}
