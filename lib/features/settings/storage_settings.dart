import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/controller.dart';
import '../../ui/shared/branding.dart';
import '../../ui/shared/settings_card.dart';

class StorageSettings extends StatelessWidget {
  const StorageSettings({super.key, required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context) {
    final manager = app.exports;
    if (manager == null) return const SizedBox.shrink();
    final prefs = manager.preferences;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Media storage', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text(
          'Previews use app-private cache. Exported media is separate from the encrypted TDLib database.',
        ),
        SwitchListTile(
          title: const Text('Automatically save incoming media'),
          value: prefs.enabled,
          onChanged: (enabled) => runAction(context, () async {
            if (enabled && prefs.destination.isEmpty) {
              await manager.chooseDestination();
            }
            if (enabled && prefs.destination.isEmpty) return;
            prefs.enabled = enabled;
            await app.savePreferences();
          }),
        ),
        ListTile(
          title: const Text('Download destination'),
          subtitle: Text(
            prefs.destination.isEmpty
                ? 'Choose a folder on this device'
                : prefs.destination,
          ),
          trailing: IconButton(
            tooltip: 'Choose download folder',
            icon: const Icon(Icons.folder_open),
            onPressed: () => runAction(context, () async {
              await manager.chooseDestination();
              await app.savePreferences();
            }),
          ),
        ),
        const SizedBox(height: 16),
        Text('Media types', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final columns = constraints.maxWidth >= 560 * scale
                ? 4
                : constraints.maxWidth >= 260 * scale
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: ['photo', 'video', 'document', 'audio'].map((category) {
                final selected = prefs.categories.contains(category);
                return SizedBox(
                  width: width,
                  child: Semantics(
                    selected: selected,
                    child: OutlinedButton(
                      key: ValueKey('media-$category'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        backgroundColor: selected
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: .12)
                            : Colors.transparent,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: selected ? .6 : .2),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => runAction(context, () async {
                        selected
                            ? prefs.categories.remove(category)
                            : prefs.categories.add(category);
                        await app.savePreferences();
                      }),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '${category[0].toUpperCase()}${category.substring(1)}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 12),
        SettingsField<int>(
          value: prefs.maximumBytes,
          label: 'Maximum automatic export size',
          items: [5, 20, 50, 100, 500]
              .map(
                (mb) => DropdownMenuItem(
                  value: mb * 1024 * 1024,
                  child: Text('$mb MB'),
                ),
              )
              .toList(),
          onChanged: (size) => runAction(context, () async {
            prefs.maximumBytes = size!;
            await app.savePreferences();
          }),
        ),
        SwitchListTile(
          title: const Text('Only on an unmetered connection'),
          subtitle: Text(
            Platform.isAndroid
                ? 'Uses Android’s metered-network status.'
                : 'Windows network cost is unavailable here. When enabled, automatic export waits; turn off to allow it on this connection.',
          ),
          value: prefs.unmeteredOnly,
          onChanged: (value) => runAction(context, () async {
            prefs.unmeteredOnly = value;
            await app.savePreferences();
          }),
        ),
        if (manager.error != null) Text(manager.error!),
        Text('${manager.pending.length} automatic exports pending'),
        const SizedBox(height: 12),
        SettingsField<int>(
          value: prefs.retentionDays,
          label: 'Cache retention',
          items: [7, 30, 90]
              .map(
                (days) =>
                    DropdownMenuItem(value: days, child: Text('$days days')),
              )
              .toList(),
          onChanged: (days) => runAction(context, () async {
            prefs.retentionDays = days!;
            await app.savePreferences();
            await app.client!.call('optimizeStorage', {
              'size': -1,
              'ttl': days * 86400,
              'count': -1,
              'immunity_delay': 3600,
              'file_types': [],
              'chat_ids': [],
              'exclude_chat_ids': [],
              'return_deleted_file_statistics': false,
              'chat_limit': 0,
            });
          }),
        ),
        Wrap(
          children: [
            TextButton(
              onPressed: () => runAction(context, () async {
                final stats = await app.client!.call(
                  'getStorageStatisticsFast',
                );
                if (!context.mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('App cache'),
                    content: Text(
                      'Media: ${((stats['files_size'] as num) / 1024 / 1024).toStringAsFixed(1)} MB\nDatabase: ${((stats['database_size'] as num) / 1024 / 1024).toStringAsFixed(1)} MB',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              }),
              child: const Text('Cache size'),
            ),
            TextButton(
              onPressed: () => runAction(context, () async {
                if (!await confirm(
                  context,
                  'Clear downloaded cache?',
                  'Telegram cloud messages and exported files remain. Cached media can be downloaded again.',
                )) {
                  return;
                }
                await app.client!.call('optimizeStorage', {
                  'size': 0,
                  'ttl': 0,
                  'count': 0,
                  'immunity_delay': 0,
                  'file_types': [],
                  'chat_ids': [],
                  'exclude_chat_ids': [],
                  'return_deleted_file_statistics': true,
                  'chat_limit': 0,
                });
              }),
              child: const Text('Clear cache'),
            ),
            if (Platform.isWindows && prefs.destination.isNotEmpty)
              TextButton(
                onPressed: () => runAction(context, () async {
                  if (!await launchUrl(Uri.directory(prefs.destination))) {
                    throw StateError('Cannot open this folder.');
                  }
                }),
                child: const Text('Open folder'),
              ),
          ],
        ),
      ],
    );
  }
}
