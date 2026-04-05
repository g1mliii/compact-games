import 'package:compact_games/l10n/app_localizations.dart';

const int _bytesPerGiB = 1024 * 1024 * 1024;
const int _bytesPerMiB = 1024 * 1024;

/// Formats a byte count as a localized human-readable string (e.g. "12.3 GB").
///
/// Uses GiB for values >= 1 GiB, otherwise falls back to MiB.
String formatBytes(AppLocalizations l10n, int bytes) {
  if (bytes <= 0) {
    return l10n.commonGigabytes('0.0');
  }
  final gib = bytes / _bytesPerGiB;
  if (gib >= 1) {
    return l10n.commonGigabytes(gib.toStringAsFixed(1));
  }
  final mib = bytes / _bytesPerMiB;
  return l10n.commonMegabytes(mib.toStringAsFixed(0));
}

/// Formats bytes as GB with 2 decimal places (e.g. "12.34 GB").
String formatBytesDetailed(AppLocalizations l10n, int bytes) {
  final gb = bytes / _bytesPerGiB;
  return l10n.commonGigabytes(gb.toStringAsFixed(2));
}
