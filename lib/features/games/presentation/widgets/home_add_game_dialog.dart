part of 'home_header.dart';

class _AddGameDialog extends ConsumerStatefulWidget {
  const _AddGameDialog();

  @override
  ConsumerState<_AddGameDialog> createState() => _AddGameDialogState();
}

class _AddGameDialogState extends ConsumerState<_AddGameDialog> {
  final TextEditingController _inputController = TextEditingController();
  bool _pickingPath = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Game'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SizedBox(
          width: double.maxFinite,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final inlineActions = constraints.maxWidth >= 560;
              final field = TextField(
                key: _addGamePathFieldKey,
                controller: _inputController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: r'C:\Games\MyGame or C:\Games\MyGame\game.exe',
                ),
                onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
              );
              final actionButtons = Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  _buildBrowseButton(
                    key: _browseGameFolderButtonKey,
                    pickExecutable: false,
                    icon: LucideIcons.folderOpen,
                    label: 'Browse Folder',
                  ),
                  _buildBrowseButton(
                    key: _browseGameExeButtonKey,
                    pickExecutable: true,
                    icon: LucideIcons.fileCode2,
                    label: 'Browse EXE',
                  ),
                ],
              );

              if (inlineActions) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: field),
                    const SizedBox(width: 8),
                    actionButtons,
                  ],
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field,
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: actionButtons),
                ],
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: _confirmAddGameButtonKey,
          onPressed: () =>
              Navigator.of(context).pop(_inputController.text.trim()),
          child: const Text('Add'),
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
