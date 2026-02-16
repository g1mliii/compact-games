import '../../models/app_settings.dart';

/// Immutable state for settings.
class SettingsState {
  final AppSettings settings;
  final bool isLoaded;
  final bool isSaving;
  final String? error;

  const SettingsState({
    this.settings = const AppSettings(),
    this.isLoaded = false,
    this.isSaving = false,
    this.error,
  });

  SettingsState copyWith({
    AppSettings? settings,
    bool? isLoaded,
    bool? isSaving,
    String? Function()? error,
  }) {
    return SettingsState(
      settings: settings ?? this.settings,
      isLoaded: isLoaded ?? this.isLoaded,
      isSaving: isSaving ?? this.isSaving,
      error: error != null ? error() : this.error,
    );
  }
}
