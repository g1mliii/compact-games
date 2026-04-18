import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Shared desktop route back button that avoids Material icon font glyphs.
Widget? buildRouteBackIconButton(BuildContext context, {Key? buttonKey}) {
  if (!Navigator.of(context).canPop()) {
    return null;
  }

  return Padding(
    padding: const EdgeInsets.only(left: 8),
    child: SizedBox(
      key: buttonKey,
      width: 56,
      height: 56,
      child: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.maybePop(context),
        icon: const Icon(LucideIcons.arrowLeft, size: 18),
      ),
    ),
  );
}

/// Builds an AppBar with the shared route back button wired in.
AppBar buildRouteAppBar(
  BuildContext context, {
  required Widget title,
  List<Widget>? actions,
  Key? backButtonKey,
}) {
  final canPop = Navigator.of(context).canPop();
  return AppBar(
    automaticallyImplyLeading: false,
    leadingWidth: canPop ? 64 : null,
    leading: buildRouteBackIconButton(context, buttonKey: backButtonKey),
    title: title,
    actions: actions,
  );
}
