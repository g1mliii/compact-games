import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../providers/system/platform_shell_provider.dart';

const ValueKey<String> homeAddGamePathFieldKey = ValueKey<String>(
  'addGamePathField',
);
const ValueKey<String> homeConfirmAddGameButtonKey = ValueKey<String>(
  'confirmAddGameButton',
);
const ValueKey<String> homeBrowseGameFolderButtonKey = ValueKey<String>(
  'browseGameFolderButton',
);
const ValueKey<String> homeBrowseGameExeButtonKey = ValueKey<String>(
  'browseGameExeButton',
);

enum AddItemMode { game, application }

typedef AddItemResult = ({String path, AddItemMode mode});

class HomeAddGameDialog extends ConsumerStatefulWidget {
  const HomeAddGameDialog({super.key});

  @override
  ConsumerState<HomeAddGameDialog> createState() => _HomeAddGameDialogState();
}

class _HomeAddGameDialogState extends ConsumerState<HomeAddGameDialog> {
  final TextEditingController _inputController = TextEditingController();
  bool _pickingPath = false;
  AddItemMode _mode = AddItemMode.game;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop((path: text, mode: _mode));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.homeAddGameDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<AddItemMode>(
                segments: [
                  ButtonSegment(
                    value: AddItemMode.game,
                    label: Text(l10n.addItemModeGame),
                    icon: const Icon(LucideIcons.gamepad2, size: 16),
                  ),
                  ButtonSegment(
                    value: AddItemMode.application,
                    label: Text(l10n.addItemModeApplication),
                    icon: const Icon(LucideIcons.archive, size: 16),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selected) {
                  setState(() {
                    _mode = selected.first;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: homeAddGamePathFieldKey,
                controller: _inputController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: _mode == AddItemMode.game
                      ? l10n.homeAddGamePathHint
                      : l10n.addApplicationPathHint,
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stackedButtons = constraints.maxWidth < 420;
                  final folderButton = _buildBrowseButton(
                    key: homeBrowseGameFolderButtonKey,
                    pickExecutable: false,
                    icon: LucideIcons.folderOpen,
                    label: l10n.homeBrowseFolder,
                  );
                  final exeButton = _buildBrowseButton(
                    key: homeBrowseGameExeButtonKey,
                    pickExecutable: true,
                    icon: LucideIcons.fileCode2,
                    label: l10n.homeBrowseExe,
                  );

                  if (stackedButtons) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        folderButton,
                        const SizedBox(height: 8),
                        exeButton,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: folderButton),
                      const SizedBox(width: 8),
                      Expanded(child: exeButton),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: homeConfirmAddGameButtonKey,
          onPressed: _submit,
          child: Text(l10n.commonAdd),
        ),
      ],
    );
  }

  Future<void> _browseAndPopulatePath({required bool pickExecutable}) async {
    if (_pickingPath) {
      return;
    }
    setState(() {
      _pickingPath = true;
    });

    final shell = ref.read(platformShellServiceProvider);
    try {
      final selected = pickExecutable
          ? await shell.pickGameExecutable()
          : await shell.pickGameFolder();
      if (!mounted) {
        return;
      }
      if (selected == null || selected.trim().isEmpty) {
        return;
      }

      final normalized = selected.trim();
      _inputController.text = normalized;
      _inputController.selection = TextSelection.collapsed(
        offset: normalized.length,
      );
    } finally {
      if (mounted) {
        setState(() {
          _pickingPath = false;
        });
      } else {
        _pickingPath = false;
      }
    }
  }

  Widget _buildBrowseButton({
    required Key key,
    required bool pickExecutable,
    required IconData icon,
    required String label,
  }) {
    return OutlinedButton.icon(
      key: key,
      onPressed: _pickingPath
          ? null
          : () => unawaited(
              _browseAndPopulatePath(pickExecutable: pickExecutable),
            ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}
