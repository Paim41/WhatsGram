import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../features/chats/selection_picker.dart';
import '../../features/conversation/conversation_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../telegram/repositories/telegram_repository.dart';
import '../../workspace/models/protocol.dart';
import 'branding.dart';
import 'chat_avatar.dart';
import 'package:url_launcher/url_launcher.dart';

class WhatsGramShell extends StatefulWidget {
  const WhatsGramShell({super.key, required this.app});
  final AppController app;
  @override
  State<WhatsGramShell> createState() => _WhatsGramShellState();
}

class _WhatsGramShellState extends State<WhatsGramShell> {
  int page = 0;
  String filter = 'All', query = '', signature = '';
  List<Conversation> conversations = [];
  Conversation? selected;
  bool resolving = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    widget.app.addListener(changed);
    timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
    changed();
  }

  @override
  void dispose() {
    widget.app.removeListener(changed);
    timer?.cancel();
    super.dispose();
  }

  void changed() {
    final destination = widget.app.notificationDestination;
    if (destination != null) {
      widget.app.notificationDestination = null;
      final genesis = widget.app.workspace?.genesis;
      if (genesis != null) {
        final target = SelectionTarget.parse(
          Map<String, dynamic>.from(destination['target']),
          genesis.participants,
        );
        if (widget.app.workspace!.register.includes(target)) {
          widget.app.telegram!.resolve(target, '${widget.app.me!['id']}').then((
            conversation,
          ) {
            if (mounted) open(conversation);
          });
        }
      }
    }
    final workspace = widget.app.workspace;
    final next =
        '${workspace?.genesis?.workspaceId}:${workspace?.register.records.values.map((e) => '${e.eventId}:${e.selected}').join(',')}';
    if (signature != next) {
      signature = next;
      refresh();
    }
  }

  Future<void> refresh() async {
    if (resolving || widget.app.workspace == null) return;
    resolving = true;
    try {
      final register = widget.app.workspace!.register;
      final targets = register.records.values
          .where(
            (e) =>
                e.selected &&
                !(e.target.kind == 'forum_topic' &&
                    register.includes(
                      SelectionTarget('supergroup', e.target.identity),
                    )),
          )
          .map((e) => e.target)
          .toList();
      final results = <Conversation>[];
      for (final target in targets) {
        results.add(
          await widget.app.telegram!.resolve(target, '${widget.app.me!['id']}'),
        );
      }
      if (mounted) {
        setState(() {
          conversations = results;
          if (selected != null && !register.includes(selected!.target)) {
            selected = null;
            widget.app.visible = null;
          }
        });
      }
    } finally {
      resolving = false;
    }
  }

  void open(Conversation conversation) {
    if (conversation.chat == null) {
      runAction(context, () async {
        final link = await askText(
          context,
          'Access required',
          hint:
              'Paste a Telegram invite or public group link to open it intentionally in Telegram.',
        );
        if (link == null || !context.mounted) return;
        final uri = Uri.tryParse(link.trim());
        if (uri == null ||
            uri.scheme != 'https' ||
            !['t.me', 'telegram.me'].contains(uri.host)) {
          throw const FormatException('Use an https://t.me/ Telegram link.');
        }
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw StateError('Could not open Telegram.');
        }
      });
      return;
    }
    setState(() {
      selected = conversation;
      page = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final workspace = app.workspace!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final list = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
              child: Row(
                children: [
                  const Brand(size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'WhatsGram',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Choose shared chats',
                    onPressed: workspace.genesis == null
                        ? null
                        : () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => SelectionPicker(app: app),
                              ),
                            );
                            refresh();
                          },
                    icon: const Icon(Icons.add_comment_outlined),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search selected chats',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => query = v.toLowerCase()),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: ['All', 'Unread', 'Groups', 'Topics']
                    .map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(f),
                          selected: filter == f,
                          onSelected: (_) => setState(() => filter = f),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            if (workspace.pending.isNotEmpty || workspace.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  workspace.error ??
                      '${workspace.pending.length} selection changes pending',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Expanded(
              child: conversations.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.forum_outlined, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              workspace.genesis == null
                                  ? 'Create or join a workspace to start.'
                                  : 'Choose a conversation with the + button.',
                              textAlign: TextAlign.center,
                            ),
                            if (workspace.genesis == null)
                              TextButton(
                                onPressed: () => setState(() => page = 2),
                                child: const Text('Open workspace settings'),
                              ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      children: _filtered(app).map((conversation) {
                        final chat =
                            app.chats[conversation.chatId] ?? conversation.chat;
                        final unread =
                            conversation.topicInfo?['unread_count'] ??
                            chat?['unread_count'] ??
                            0;
                        final last =
                            conversation.topicInfo?['last_message'] ??
                            chat?['last_message'];
                        final pin = app.pinned.contains(
                          conversation.target.key,
                        );
                        return ListTile(
                          selected:
                              selected?.target.key == conversation.target.key,
                          leading: ChatAvatar(
                            app: app,
                            chat: chat,
                            topic: conversation.topicId != null,
                          ),
                          title: Text(
                            conversation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            conversation.chat == null
                                ? 'Access required'
                                : last == null
                                ? 'No messages yet'
                                : messageText(Map<String, dynamic>.from(last)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              if (pin) const Icon(Icons.push_pin, size: 16),
                              if (app.muted.contains(conversation.target.key))
                                const Icon(Icons.volume_off, size: 16),
                              if (unread > 0) Badge(label: Text('$unread')),
                            ],
                          ),
                          onTap: () => open(conversation),
                          onLongPress: () => runAction(context, () async {
                            pin
                                ? app.pinned.remove(conversation.target.key)
                                : app.pinned.add(conversation.target.key);
                            await app.savePreferences();
                          }),
                        );
                      }).toList(),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                app.connection,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
        final conversation = selected == null
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Brand(size: 104),
                    SizedBox(height: 24),
                    Text('Select a chat to start messaging'),
                  ],
                ),
              )
            : ConversationScreen(
                key: ValueKey(selected!.target.key),
                app: app,
                conversation: selected!,
                onBack: () => setState(() => selected = null),
                onOpen: open,
              );
        final settings = SettingsScreen(app: app);
        final destinations = const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            label: 'Groups / Topics',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ];
        return PopScope(
          canPop: wide || selected == null || page == 2,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              setState(() => selected = null);
              app.visible = null;
            }
          },
          child: Scaffold(
            body: SafeArea(
              child: wide
                  ? Row(
                      children: [
                        NavigationRail(
                          selectedIndex: page,
                          onDestinationSelected: navigate,
                          labelType: NavigationRailLabelType.all,
                          destinations: destinations
                              .map(
                                (d) => NavigationRailDestination(
                                  icon: d.icon,
                                  label: Text(d.label),
                                ),
                              )
                              .toList(),
                        ),
                        const VerticalDivider(width: 1),
                        if (page == 2)
                          Expanded(child: settings)
                        else ...[
                          SizedBox(width: 350, child: list),
                          const VerticalDivider(width: 1),
                          Expanded(child: conversation),
                        ],
                      ],
                    )
                  : page == 2
                  ? settings
                  : selected == null
                  ? list
                  : conversation,
            ),
            bottomNavigationBar: wide || selected != null && page != 2
                ? null
                : NavigationBar(
                    selectedIndex: page,
                    onDestinationSelected: navigate,
                    destinations: destinations,
                  ),
          ),
        );
      },
    );
  }

  void navigate(int value) => setState(() {
    page = value;
    if (value == 1) {
      filter = 'Groups';
      selected = null;
    }
    if (value == 0) filter = 'All';
    if (value == 2) widget.app.visible = null;
  });
  List<Conversation> _filtered(AppController app) {
    final result = conversations.where((c) {
      if (!c.title.toLowerCase().contains(query)) return false;
      if (filter == 'Topics' && c.topicId == null) return false;
      if (filter == 'Groups' && c.target.kind == 'participant_pair') {
        return false;
      }
      if (filter == 'Unread' &&
          (c.topicInfo?['unread_count'] ??
                  app.chats[c.chatId]?['unread_count'] ??
                  c.chat?['unread_count'] ??
                  0) ==
              0) {
        return false;
      }
      return true;
    }).toList();
    result.sort(
      (a, b) => (app.pinned.contains(b.target.key) ? 1 : 0).compareTo(
        app.pinned.contains(a.target.key) ? 1 : 0,
      ),
    );
    return result;
  }
}
