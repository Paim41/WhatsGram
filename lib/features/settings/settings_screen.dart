import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../app/controller.dart';
import '../../ui/shared/branding.dart';
import '../../ui/shared/settings_card.dart';
import 'storage_settings.dart';
import '../media/media_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context) {
    final workspace = app.workspace!;
    return SingleChildScrollView(
      key: const PageStorageKey('settings-scroll'),
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('Your workspace, your look, your device.'),
              const SizedBox(height: 24),
              SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(
                        '${app.me?['first_name'] ?? ''} ${app.me?['last_name'] ?? ''}',
                      ),
                      subtitle: Text('Telegram user ID ${app.me?['id']}'),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Workspace',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A private Telegram settings group keeps two people’s chat selections in sync. Settings records are visible to group members in official Telegram. Each person still needs access to the selected groups.',
                    ),
                    const SizedBox(height: 16),
                    if (workspace.genesis == null)
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: () =>
                                runAction(context, () => create(context)),
                            icon: const Icon(Icons.add),
                            label: const Text('Create workspace'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                runAction(context, () => join(context)),
                            icon: const Icon(Icons.link),
                            label: const Text('Join workspace'),
                          ),
                        ],
                      )
                    else ...[
                      SelectableText(
                        'Workspace ${workspace.genesis!.workspaceId}',
                      ),
                      Text(
                        '${workspace.pending.length} pending changes • ${workspace.syncing
                            ? 'Synchronizing'
                            : workspace.verified
                            ? 'Verified'
                            : 'Awaiting verification'}',
                      ),
                      if (workspace.error != null)
                        Text(
                          workspace.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: () => showPairing(
                              context,
                              jsonEncode(workspace.pairing),
                            ),
                            child: const Text('Show pairing QR'),
                          ),
                          TextButton(
                            onPressed: () =>
                                runAction(context, workspace.reconcile),
                            child: const Text('Reconcile now'),
                          ),
                          TextButton(
                            onPressed: () => runAction(context, () async {
                              if (await confirm(
                                context,
                                'Disconnect workspace?',
                                'Stop selection sync and discard local pending settings changes. Telegram messages and group memberships are retained.',
                              )) {
                                await workspace.disconnect();
                              }
                            }),
                            child: const Text('Disconnect'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Appearance & notifications',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    SettingsField<ThemeMode>(
                      value: app.theme,
                      label: 'Appearance',
                      items: ThemeMode.values
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(switch (m) {
                                ThemeMode.system => 'System',
                                ThemeMode.light => 'Light',
                                ThemeMode.dark => 'Dark',
                              }),
                            ),
                          )
                          .toList(),
                      onChanged: (m) {
                        app.theme = m!;
                        runAction(context, app.savePreferences);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Enter sends a message'),
                      subtitle: const Text(
                        'Shift+Enter always inserts a new line.',
                      ),
                      value: app.enterSends,
                      onChanged: (value) {
                        app.enterSends = value;
                        runAction(context, app.savePreferences);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Notifications on this device'),
                      subtitle: const Text(
                        'Only selected chats while WhatsGram is running.',
                      ),
                      value: app.notificationsEnabled,
                      onChanged: (enabled) => runAction(context, () async {
                        if (enabled) {
                          await app.notifications.requestPermission();
                        }
                        app.notificationsEnabled = enabled;
                        await app.savePreferences();
                      }),
                    ),
                    SwitchListTile(
                      title: const Text('Show message previews'),
                      value: app.notificationPreviews,
                      onChanged: (enabled) => runAction(context, () async {
                        app.notificationPreviews = enabled;
                        await app.savePreferences();
                      }),
                    ),
                  ],
                ),
              ),
              SettingsCard(child: StorageSettings(app: app)),
              SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Help & account',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.bug_report_outlined),
                      title: const Text('Export diagnostic log'),
                      subtitle: const Text(
                        'Only technical event names and times. No messages, user IDs or credentials.',
                      ),
                      onTap: () => runAction(context, () async {
                        final path = await app.diagnostics.export();
                        await MediaService(
                          app.client!,
                        ).save(path, 'whatsgram-diagnostics.json');
                      }),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('About WhatsGram'),
                      subtitle: const Text('Version 0.1.1 • TDLib 1.8.67'),
                      onTap: () => showAboutDialog(
                        context: context,
                        applicationName: 'WhatsGram',
                        applicationVersion: '0.1.1',
                        applicationIcon: const Brand(),
                        children: const [
                          Text(
                            'WhatsGram is an unofficial client using the Telegram API.',
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Ordinary Telegram cloud chats and the private settings group are not end-to-end encrypted Secret Chats. No analytics or application backend is used. Each device has its own Telegram session.',
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Live reception requires a running process. Force-stop, Doze and battery restrictions can delay Android reception. Quitting Windows stops reception.',
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => runAction(context, () async {
                        if (await confirm(
                          context,
                          'Log out of Telegram?',
                          'This ends this device’s session. The other person’s account is unaffected.',
                        )) {
                          await app.logout();
                        }
                      }),
                      icon: const Icon(Icons.logout),
                      label: const Text('Log out'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> create(BuildContext context) async {
    final identity = await askText(
      context,
      'Choose your counterpart',
      hint: '@username or Telegram user ID',
    );
    if (identity == null || identity.trim().isEmpty) return;
    var id = int.tryParse(identity.trim());
    if (id == null) {
      final chat = await app.client!.call('searchPublicChat', {
        'username': identity.trim().replaceFirst('@', ''),
      });
      if (chat['type']?['@type'] != 'chatTypePrivate') {
        throw StateError('Choose a person, not a group.');
      }
      id = chat['type']['user_id'] as int;
    }
    final person = await app.client!.call('getUser', {'user_id': id});
    if (!context.mounted) return;
    final approved = await confirm(
      context,
      'Create a settings group and invite this person?',
      '${person['first_name']} ${person['last_name']}\nTelegram ID $id\n\nWhatsGram will create a private supergroup, make earlier settings history visible, and add or generate an invite for this person.',
    );
    if (!approved) return;
    final result = await app.workspace!.create('$id');
    if (!context.mounted) return;
    await showPairing(
      context,
      jsonEncode(result['pairing']),
      invite: result['invite_link'] as String?,
    );
  }

  Future<void> join(BuildContext context) async {
    final payload = await askText(
      context,
      'Paste pairing payload',
      hint:
          'First join the owner’s private settings group in official Telegram.',
    );
    if (payload == null) return;
    final verified = await app.workspace!.inspectPairing(payload);
    final owner = await app.client!.call('getUser', {
      'user_id': int.parse(verified.owner),
    });
    if (!context.mounted) return;
    if (!await confirm(
      context,
      'Verify the workspace owner',
      '${owner['first_name']} ${owner['last_name']}\nTelegram ID ${verified.owner}\n\nThe genesis sender matches Telegram’s metadata. Accept this person as your workspace counterpart?',
    )) {
      return;
    }
    await app.workspace!.acceptPairing(payload);
  }

  Future<void> showPairing(
    BuildContext context,
    String payload, {
    String? invite,
  }) => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Pair your other account'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ColoredBox(
                color: Colors.white,
                child: QrImageView(data: payload, size: 250),
              ),
              const SizedBox(height: 12),
              if (invite != null) ...[
                const Text('Send this invite privately to your counterpart:'),
                SelectableText(invite),
              ],
              SelectableText(payload),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: payload)),
          child: const Text('Copy payload'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
