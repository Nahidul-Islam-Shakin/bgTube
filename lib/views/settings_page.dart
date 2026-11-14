import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/shortcut.dart';
import '../viewmodels/settings_view_model.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsViewModel>();
    final unusedPresets = kShortcutPresets
        .where((p) => !settings.shortcuts.any((s) => s.url == p.url))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Block ads'),
            subtitle: const Text(
              'On by default. Changing it reloads the page and stops playback. '
              'Best effort: YouTube may still show some ads.',
            ),
            value: settings.adBlockEnabled,
            onChanged: settings.setAdBlock,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Shortcuts', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Shown under the top bar. They open in this app, and playback '
              'stops when you leave YouTube.',
            ),
          ),
          for (final shortcut in settings.shortcuts)
            ListTile(
              title: Text(shortcut.name),
              subtitle: Text(Shortcut.displayHost(shortcut.url)),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => settings.removeShortcut(shortcut),
              ),
            ),
          if (unusedPresets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in unusedPresets)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: Text(preset.name),
                      onPressed: () => settings.addShortcut(preset),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.add_link),
                label: const Text('Add custom shortcut'),
                onPressed: () => _addCustom(context, settings),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addCustom(BuildContext context, SettingsViewModel settings) async {
    final shortcut = await showDialog<Shortcut>(
      context: context,
      builder: (_) => const _AddShortcutDialog(),
    );
    if (shortcut == null) return;
    final added = await settings.addShortcut(shortcut);
    if (!added && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That shortcut already exists')),
      );
    }
  }
}

class _AddShortcutDialog extends StatefulWidget {
  const _AddShortcutDialog();

  @override
  State<_AddShortcutDialog> createState() => _AddShortcutDialogState();
}

class _AddShortcutDialogState extends State<_AddShortcutDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _url = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final url = Shortcut.normalizeUrl(_url.text);
    if (url == null) {
      setState(() => _error = 'Enter a valid address, for example facebook.com');
      return;
    }
    final typedName = _name.text.trim();
    final name = typedName.isEmpty ? Shortcut.displayHost(url) : typedName;
    Navigator.of(context).pop(Shortcut(name: name, url: url));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add shortcut'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name (optional)'),
          ),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Address',
              hintText: 'facebook.com',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}