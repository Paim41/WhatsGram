import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import '../../app/controller.dart';
import '../../telegram/client/td_client.dart';
import '../../telegram/repositories/telegram_repository.dart';
import '../../ui/shared/branding.dart';
import '../../ui/shared/chat_avatar.dart';
import '../../ui/shared/formatted_message.dart';
import '../../workspace/models/protocol.dart';
import '../media/media_service.dart';
import '../media/media_viewer.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.app,
    required this.conversation,
    required this.onBack,
    required this.onOpen,
  });
  final AppController app;
  final Conversation conversation;
  final VoidCallback onBack;
  final void Function(Conversation) onOpen;
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final composer = TextEditingController();
  final scroll = ScrollController();
  final recorder = AudioRecorder();
  final messages = <int, Json>{};
  final bubbleKeys = <int, GlobalKey>{};
  final listKey = GlobalKey();
  StreamSubscription<Json>? subscription;
  Timer? readTimer;
  bool loading = false,
      sending = false,
      recording = false,
      exhausted = false,
      markdown = false;
  DateTime? recordingStart, lastTyping;
  Json? reply;
  String? failure, search;
  String typing = '';
  Conversation get chat => widget.conversation;
  AppController get app => widget.app;

  @override
  void initState() {
    super.initState();
    app.visible = chat;
    subscription = app.client!.updates.listen(update);
    runAction(context, () async {
      await app.client!.call('openChat', {'chat_id': chat.chatId});
      await load();
    });
    readTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => markVisible(),
    );
  }

  @override
  void dispose() {
    subscription?.cancel();
    readTimer?.cancel();
    if (app.visible?.target.key == chat.target.key) app.visible = null;
    app.client
        ?.call('closeChat', {'chat_id': chat.chatId})
        .catchError((Object _) => <String, dynamic>{});
    composer.dispose();
    scroll.dispose();
    recorder.dispose();
    super.dispose();
  }

  void update(Json event) {
    if (!mounted) return;
    final message = event['message'];
    if (message is Json && chat.contains(message) && search == null) {
      setState(() {
        messages.remove(event['old_message_id']);
        messages[message['id']] = message;
      });
    }
    if (event['chat_id'] == chat.chatId) {
      if (event['@type'] == 'updateMessageContent' &&
          messages.containsKey(event['message_id'])) {
        setState(
          () =>
              messages[event['message_id']]!['content'] = event['new_content'],
        );
      }
      if (event['@type'] == 'updateDeleteMessages') {
        setState(() {
          for (final id in event['message_ids']) {
            messages.remove(id);
          }
        });
      }
      if (event['@type'] == 'updateMessageInteractionInfo' &&
          messages.containsKey(event['message_id'])) {
        setState(
          () => messages[event['message_id']]!['interaction_info'] =
              event['interaction_info'],
        );
      }
      if (event['@type'] == 'updateChatAction' &&
          (chat.topicId == null ||
              event['topic_id']?['forum_topic_id'] == chat.topicId)) {
        setState(
          () => typing = event['action']?['@type'] == 'chatActionTyping'
              ? 'Typing…'
              : '',
        );
        Future<void>.delayed(const Duration(seconds: 6), () {
          if (mounted) setState(() => typing = '');
        });
      }
    }
  }

  Future<void> load({bool older = false}) async {
    if (loading || older && exhausted) return;
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      final before = older && messages.isNotEmpty
          ? messages.keys.reduce((a, b) => a < b ? a : b)
          : 0;
      final page = search == null
          ? await app.telegram!.history(chat, before: before)
          : await app.telegram!.search(chat, search!, before: before);
      if (!mounted) return;
      setState(() {
        var added = 0;
        for (final message in page.where(chat.contains)) {
          if (!messages.containsKey(message['id'])) added++;
          messages[message['id']] = message;
        }
        exhausted = page.isEmpty || older && added == 0;
      });
    } catch (e) {
      if (mounted) setState(() => failure = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void markVisible() {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (!mounted ||
        !app.active ||
        app.visible?.target.key != chat.target.key ||
        search != null) {
      return;
    }
    final viewport = listKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) return;
    final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
    final visible = <Json>[];
    for (final entry in bubbleKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box != null &&
          box.hasSize &&
          bounds.overlaps(box.localToGlobal(Offset.zero) & box.size) &&
          messages.containsKey(entry.key)) {
        visible.add(messages[entry.key]!);
      }
    }
    if (visible.isNotEmpty) {
      app.telegram!.markViewed(chat, visible).catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final peer = chat.chat?['type']?['user_id'];
    final status = app.users[peer]?['status'];
    final statusLabel = switch (status?['@type']) {
      'userStatusOnline' => 'Online',
      'userStatusRecently' => 'Last seen recently',
      'userStatusLastWeek' => 'Last seen within a week',
      'userStatusLastMonth' => 'Last seen within a month',
      'userStatusOffline' =>
        'Last seen ${DateTime.fromMillisecondsSinceEpoch((status['was_online'] as int) * 1000).toLocal()}',
      _ => 'Telegram conversation',
    };
    final ordered = messages.values.toList()
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DropTarget(
      onDragDone: (details) => runAction(context, () async {
        for (final file in details.files) {
          await attachment(file.path);
        }
      }),
      child: Column(
        children: [
          Material(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: widget.onBack,
                      tooltip: 'Back to chats',
                      icon: const Icon(Icons.arrow_back),
                    ),
                    ChatAvatar(
                      app: app,
                      chat: chat.chat,
                      topic: chat.topicId != null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            typing.isNotEmpty
                                ? typing
                                : chat.topicId == null
                                ? statusLabel
                                : 'Topic ${chat.topicId}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (chat.target.kind != 'participant_pair')
                      IconButton(
                        tooltip: 'Topics in this group',
                        icon: const Icon(Icons.tag),
                        onPressed: () => runAction(context, () async {
                          final topics = await app.telegram!.topics(
                            chat.chatId,
                          );
                          if (!context.mounted) return;
                          final chosen = await showDialog<Conversation>(
                            context: context,
                            builder: (dialog) => SimpleDialog(
                              title: const Text('Selected topics'),
                              children: topics
                                  .where(
                                    (t) => app.workspace!.register.includes(
                                      SelectionTarget(
                                        'forum_topic',
                                        chat.target.identity,
                                        '${t['info']['forum_topic_id']}',
                                      ),
                                    ),
                                  )
                                  .map(
                                    (t) => SimpleDialogOption(
                                      onPressed: () => Navigator.pop(
                                        dialog,
                                        Conversation(
                                          SelectionTarget(
                                            'forum_topic',
                                            chat.target.identity,
                                            '${t['info']['forum_topic_id']}',
                                          ),
                                          chat.chat,
                                          topicInfo: t,
                                        ),
                                      ),
                                      child: Text(
                                        '${t['info']['name']}${t['info']['is_closed'] == true ? ' • Closed' : ''}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          );
                          if (chosen != null) widget.onOpen(chosen);
                        }),
                      ),
                    IconButton(
                      tooltip: 'Search this conversation',
                      icon: const Icon(Icons.search),
                      onPressed: () => runAction(context, () async {
                        final value = await askText(context, 'Search messages');
                        if (value == null) return;
                        setState(() {
                          search = value.isEmpty ? null : value;
                          messages.clear();
                          exhausted = false;
                        });
                        await load();
                      }),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) => runAction(context, () async {
                        if (value == 'mute') {
                          app.muted.contains(chat.target.key)
                              ? app.muted.remove(chat.target.key)
                              : app.muted.add(chat.target.key);
                          await app.savePreferences();
                        } else {
                          await showDialog<void>(
                            context: context,
                            builder: (dialog) => AlertDialog(
                              title: Text(chat.title),
                              content: SelectableText(
                                'TDLib chat ID: ${chat.chatId}\nSelection: ${chat.target.key}\n${chat.chat?['permissions'] ?? ''}',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        }
                      }),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'mute',
                          child: Text(
                            app.muted.contains(chat.target.key)
                                ? 'Unmute on this device'
                                : 'Mute on this device',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'info',
                          child: Text('Conversation information'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (search != null)
            ListTile(
              title: Text('Search: $search'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close search',
                onPressed: () {
                  setState(() {
                    search = null;
                    messages.clear();
                    exhausted = false;
                  });
                  load();
                },
              ),
            ),
          if (failure != null)
            ListTile(
              title: Text(failure!),
              trailing: TextButton(onPressed: load, child: const Text('Retry')),
            ),
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              key: listKey,
              controller: scroll,
              reverse: true,
              padding: const EdgeInsets.all(16),
              itemCount: ordered.length + 1,
              itemBuilder: (context, index) {
                if (index == ordered.length) {
                  return Center(
                    child: TextButton(
                      onPressed: loading || exhausted
                          ? null
                          : () => load(older: true),
                      child: Text(
                        exhausted
                            ? 'Beginning of available history'
                            : 'Load older messages',
                      ),
                    ),
                  );
                }
                final message = ordered[index];
                final id = message['id'] as int;
                final outgoing = message['is_outgoing'] == true;
                final date = DateTime.fromMillisecondsSinceEpoch(
                  (message['date'] as int) * 1000,
                ).toLocal();
                final next = index + 1 < ordered.length
                    ? DateTime.fromMillisecondsSinceEpoch(
                        (ordered[index + 1]['date'] as int) * 1000,
                      ).toLocal()
                    : null;
                final divider =
                    next == null ||
                    next.year != date.year ||
                    next.month != date.month ||
                    next.day != date.day;
                final file = messageFile(message);
                final liveFile = file == null
                    ? null
                    : app.files[file['id']] ?? file;
                final transfer =
                    liveFile?['local']?['is_downloading_active'] == true ||
                    liveFile?['remote']?['is_uploading_active'] == true;
                final key = bubbleKeys.putIfAbsent(id, GlobalKey.new);
                final readThrough =
                    app.forumTopics['${chat.chatId}:${chat.topicId}']?['last_read_outbox_message_id'] ??
                    chat.topicInfo?['last_read_outbox_message_id'] ??
                    app.chats[chat.chatId]?['last_read_outbox_message_id'] ??
                    chat.chat?['last_read_outbox_message_id'] ??
                    0;
                return Column(
                  children: [
                    if (divider)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '${date.day}/${date.month}/${date.year}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    Align(
                      alignment: outgoing
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () => actions(message),
                        onSecondaryTap: () => actions(message),
                        child: Container(
                          key: key,
                          constraints: const BoxConstraints(maxWidth: 560),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
                          decoration: BoxDecoration(
                            color: outgoing
                                ? (dark
                                      ? const Color(0xff173b55)
                                      : const Color(0xffddefff))
                                : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (message['reply_to'] != null)
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    message['reply_to']['content'] == null
                                        ? 'Reply to message ${message['reply_to']['message_id'] ?? ''}'
                                        : messageText({
                                            'content':
                                                message['reply_to']['content'],
                                          }),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (message['content']?['@type'] ==
                                      'messagePhoto' &&
                                  liveFile?['local']?['is_downloading_completed'] ==
                                      true &&
                                  File(liveFile!['local']['path']).existsSync())
                                GestureDetector(
                                  onTap: () => runAction(
                                    context,
                                    () => openMedia(message, file!),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(liveFile['local']['path']),
                                      height: 180,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              if (message['content']?['@type'] == 'messageText')
                                FormattedMessage(
                                  text: Map<String, dynamic>.from(
                                    message['content']['text'],
                                  ),
                                )
                              else
                                SelectableText(messageText(message)),
                              if (message['interaction_info']?['reactions']?['reactions']
                                  is List)
                                Wrap(
                                  spacing: 4,
                                  children:
                                      (message['interaction_info']['reactions']['reactions']
                                              as List)
                                          .map(
                                            (reaction) => Chip(
                                              label: Text(
                                                '${reaction['type']?['emoji'] ?? 'Reaction'} ${reaction['total_count']}',
                                              ),
                                            ),
                                          )
                                          .toList(),
                                ),
                              if (file != null)
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => runAction(
                                        context,
                                        () => openMedia(message, file),
                                      ),
                                      icon: const Icon(Icons.download_outlined),
                                      label: Text(
                                        '${((file['size'] as num? ?? 0) / 1024).toStringAsFixed(0)} KB • Open',
                                      ),
                                    ),
                                    if (message['can_be_saved'] == true &&
                                        message['self_destruct_type'] == null)
                                      TextButton(
                                        onPressed: () => runAction(
                                          context,
                                          () => export(message, file),
                                        ),
                                        child: const Text('Save'),
                                      ),
                                    if (transfer)
                                      IconButton(
                                        tooltip: 'Cancel download',
                                        icon: const Icon(Icons.close),
                                        onPressed: () =>
                                            runAction(context, () async {
                                              await app.client!
                                                  .call('cancelDownloadFile', {
                                                    'file_id': file['id'],
                                                    'only_if_pending': false,
                                                  });
                                            }),
                                      ),
                                  ],
                                ),
                              if (transfer)
                                LinearProgressIndicator(
                                  value: (liveFile?['size'] as num? ?? 0) > 0
                                      ? ((liveFile?['local']?['downloaded_size'] ??
                                                    liveFile?['remote']?['uploaded_size'] ??
                                                    0)
                                                as num) /
                                            (liveFile!['size'] as num)
                                      : null,
                                ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                  const SizedBox(width: 6),
                                  if (outgoing)
                                    Icon(
                                      message['sending_state']?['@type'] ==
                                              'messageSendingStateFailed'
                                          ? Icons.error_outline
                                          : message['sending_state'] != null
                                          ? Icons.schedule
                                          : id <= readThrough
                                          ? Icons.done_all
                                          : Icons.done,
                                      size: 16,
                                      semanticLabel:
                                          message['sending_state'] != null
                                          ? 'Sending or failed'
                                          : id <= readThrough
                                          ? 'Read'
                                          : 'Sent',
                                    ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Message actions',
                                    onPressed: () => actions(message),
                                    icon: const Icon(
                                      Icons.more_horiz,
                                      size: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (reply != null)
            ListTile(
              dense: true,
              title: const Text('Replying to'),
              subtitle: Text(
                messageText(reply!),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'Cancel reply',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => reply = null),
              ),
            ),
          if (recording)
            ListTile(
              leading: const Icon(Icons.fiber_manual_record, color: Colors.red),
              title: const Text('Recording voice message…'),
              trailing: Wrap(
                children: [
                  TextButton(
                    onPressed: () => runAction(context, () async {
                      await recorder.cancel();
                      setState(() => recording = false);
                    }),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => runAction(context, finishRecording),
                    child: const Text('Send'),
                  ),
                ],
              ),
            )
          else
            Material(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Attach photo, video or file',
                        onPressed: sending
                            ? null
                            : () => runAction(context, () async {
                                final files = await openFiles();
                                for (final file in files) {
                                  await attachment(file.path);
                                }
                              }),
                        icon: const Icon(Icons.attach_file),
                      ),
                      Expanded(
                        child: Focus(
                          onKeyEvent: (_, event) {
                            if (app.enterSends &&
                                event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.enter &&
                                !HardwareKeyboard.instance.isShiftPressed) {
                              if (!sending) sendText();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextField(
                            controller: composer,
                            minLines: 1,
                            maxLines: 6,
                            textInputAction: TextInputAction.newline,
                            decoration: const InputDecoration(
                              hintText: 'Message',
                            ),
                            onChanged: (_) {
                              if (lastTyping == null ||
                                  DateTime.now().difference(lastTyping!) >
                                      const Duration(seconds: 4)) {
                                lastTyping = DateTime.now();
                                app.client!
                                    .call('sendChatAction', {
                                      'chat_id': chat.chatId,
                                      'topic_id': chat.topic,
                                      'action': {'@type': 'chatActionTyping'},
                                    })
                                    .catchError(
                                      (Object _) => <String, dynamic>{},
                                    );
                              }
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Record voice message',
                        onPressed: sending
                            ? null
                            : () => runAction(context, startRecording),
                        icon: const Icon(Icons.mic_none),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Emoji and formatting',
                        onSelected: (choice) async {
                          if (choice == 'format') {
                            setState(() => markdown = !markdown);
                            return;
                          }
                          final value = await showModalBottomSheet<String>(
                            context: context,
                            builder: (sheet) => SafeArea(
                              child: Wrap(
                                children:
                                    [
                                          '😀',
                                          '😊',
                                          '❤️',
                                          '👍',
                                          '🙏',
                                          '🎉',
                                          '😂',
                                          '🥰',
                                          '👋',
                                          '✅',
                                          '🔥',
                                          '😢',
                                          '🤔',
                                          '💙',
                                          '✨',
                                          '🎂',
                                        ]
                                        .map(
                                          (emoji) => TextButton(
                                            onPressed: () =>
                                                Navigator.pop(sheet, emoji),
                                            child: Text(
                                              emoji,
                                              style: const TextStyle(
                                                fontSize: 30,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                              ),
                            ),
                          );
                          if (value != null && mounted) {
                            final selection = composer.selection;
                            final start = selection.isValid
                                ? selection.start
                                : composer.text.length;
                            final end = selection.isValid
                                ? selection.end
                                : start;
                            composer.value = TextEditingValue(
                              text: composer.text.replaceRange(
                                start,
                                end,
                                value,
                              ),
                              selection: TextSelection.collapsed(
                                offset: start + value.length,
                              ),
                            );
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'emoji',
                            child: Text('Insert emoji'),
                          ),
                          PopupMenuItem(
                            value: 'format',
                            child: Text(
                              markdown
                                  ? 'Markdown formatting: on'
                                  : 'Markdown formatting: off',
                            ),
                          ),
                        ],
                      ),
                      IconButton.filled(
                        tooltip: 'Send message',
                        onPressed: sending ? null : sendText,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> sendText() async {
    if (composer.text.trim().isEmpty || sending) return;
    final text = composer.text;
    setState(() => sending = true);
    await runAction(context, () async {
      final result = await app.telegram!.sendText(
        chat,
        text,
        reply: reply,
        markdown: markdown,
      );
      if (!mounted) return;
      setState(() {
        messages[result['id']] = result;
        reply = null;
        if (composer.text == text) composer.clear();
      });
    });
    if (mounted) setState(() => sending = false);
  }

  Future<void> attachment(String path) async {
    final caption = TextEditingController();
    var kind = 'document';
    final ext = p.extension(path).toLowerCase();
    final isPhoto = ['.jpg', '.jpeg', '.png', '.webp'].contains(ext);
    final isVideo = ['.mp4', '.mov', '.mkv'].contains(ext);
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, set) => AlertDialog(
          title: Text(p.basename(path)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPhoto)
                    Image.file(File(path), height: 180, fit: BoxFit.contain),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    items: [
                      const DropdownMenuItem(
                        value: 'document',
                        child: Text('Send as original file'),
                      ),
                      if (isPhoto)
                        const DropdownMenuItem(
                          value: 'photo',
                          child: Text('Send as photo'),
                        ),
                      if (isVideo)
                        const DropdownMenuItem(
                          value: 'video',
                          child: Text('Send as video'),
                        ),
                    ],
                    onChanged: (v) => set(() => kind = v!),
                  ),
                  TextField(
                    controller: caption,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Caption'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    final text = caption.text;
    Future<void>.delayed(const Duration(seconds: 1), caption.dispose);
    if (approved != true || !mounted) return;
    final result = await app.telegram!.sendFile(
      chat,
      path,
      kind,
      text,
      reply: reply,
    );
    if (mounted) {
      setState(() {
        messages[result['id']] = result;
        reply = null;
      });
    }
  }

  Future<void> startRecording() async {
    if (!await recorder.hasPermission()) {
      throw StateError('Microphone access is required for a voice message.');
    }
    if (!await recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      throw StateError('AAC recording is unavailable on this device.');
    }
    final directory = await getTemporaryDirectory();
    final path = p.join(directory.path, '${const Uuid().v4()}.m4a');
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 48000,
        numChannels: 1,
      ),
      path: path,
    );
    recordingStart = DateTime.now();
    if (mounted) setState(() => recording = true);
  }

  Future<void> finishRecording() async {
    final path = await recorder.stop();
    final duration = DateTime.now().difference(recordingStart!).inSeconds;
    if (mounted) setState(() => recording = false);
    if (path == null) throw StateError('Recording was not saved.');
    final message = await app.telegram!.sendFile(
      chat,
      path,
      'voice',
      '',
      duration: duration,
      reply: reply,
    );
    if (mounted) {
      setState(() {
        messages[message['id']] = message;
        reply = null;
      });
    }
  }

  Future<void> openMedia(Json message, Json file) async {
    final path = await MediaService(app.client!).download(file);
    final type = message['content']['@type'];
    if (!mounted) return;
    if (type == 'messageDocument') {
      await export(message, file);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MediaViewer(
          path: path,
          image: type == 'messagePhoto' || type == 'messageSticker',
        ),
      ),
    );
  }

  Future<void> export(Json message, Json file) async {
    final props = await app.client!.call('getMessageProperties', {
      'chat_id': chat.chatId,
      'message_id': message['id'],
    });
    if (props['can_be_saved'] != true ||
        message['self_destruct_type'] != null) {
      throw StateError('Telegram does not allow this content to be exported.');
    }
    final media = MediaService(app.client!);
    final path = await media.download(file);
    final name =
        message['content']?['document']?['file_name'] as String? ??
        p.basename(path);
    await media.save(path, name);
  }

  Future<void> actions(Json message) => runAction(context, () async {
    final properties = await app.client!.call('getMessageProperties', {
      'chat_id': chat.chatId,
      'message_id': message['id'],
    });
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (properties['can_be_replied'] == true)
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () => Navigator.pop(sheet, 'reply'),
              ),
            if (properties['can_be_edited'] == true &&
                message['content']['@type'] == 'messageText')
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.pop(sheet, 'edit'),
              ),
            if (properties['can_be_forwarded'] == true)
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Forward to selected conversation'),
                onTap: () => Navigator.pop(sheet, 'forward'),
              ),
            ListTile(
              leading: const Icon(Icons.add_reaction_outlined),
              title: const Text('React'),
              onTap: () => Navigator.pop(sheet, 'react'),
            ),
            if (message['sending_state']?['@type'] ==
                'messageSendingStateFailed')
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Retry sending'),
                onTap: () => Navigator.pop(sheet, 'retry'),
              ),
            if (properties['can_be_deleted_only_for_self'] == true)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete for me'),
                onTap: () => Navigator.pop(sheet, 'deleteSelf'),
              ),
            if (properties['can_be_deleted_for_all_users'] == true)
              ListTile(
                leading: const Icon(Icons.delete_forever),
                title: const Text('Delete for everyone'),
                onTap: () => Navigator.pop(sheet, 'deleteAll'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'reply':
        setState(() => reply = message);
      case 'edit':
        final text = await askText(
          context,
          'Edit message',
          initial: messageText(message),
        );
        if (text != null) {
          await app.client!.call('editMessageText', {
            'chat_id': chat.chatId,
            'message_id': message['id'],
            'input_message_content': {
              '@type': 'inputMessageText',
              'text': await app.telegram!.formatted(text),
            },
          });
        }
      case 'retry':
        await app.client!.call('resendMessages', {
          'chat_id': chat.chatId,
          'message_ids': [message['id']],
          'paid_message_star_count': 0,
        });
      case 'deleteSelf':
      case 'deleteAll':
        if (await confirm(
          context,
          action == 'deleteAll' ? 'Delete for everyone?' : 'Delete for me?',
          'Telegram will apply this deletion to the chosen scope.',
        )) {
          await app.client!.call('deleteMessages', {
            'chat_id': chat.chatId,
            'message_ids': [message['id']],
            'revoke': action == 'deleteAll',
          });
        }
      case 'react':
        final choices = await app.client!.call('getMessageAvailableReactions', {
          'chat_id': chat.chatId,
          'message_id': message['id'],
          'row_size': 8,
        });
        final reactions = [
          ...?choices['top_reactions'] as List?,
          ...?choices['recent_reactions'] as List?,
          ...?choices['popular_reactions'] as List?,
        ].where((r) => r['type']?['@type'] == 'reactionTypeEmoji').toList();
        if (!mounted) return;
        final emoji = await showDialog<String>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Choose a reaction'),
            content: Wrap(
              children: reactions
                  .map(
                    (r) => TextButton(
                      onPressed: () =>
                          Navigator.pop(dialog, r['type']['emoji']),
                      child: Text(
                        r['type']['emoji'],
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
        if (emoji != null) {
          await app.client!.call('addMessageReaction', {
            'chat_id': chat.chatId,
            'message_id': message['id'],
            'reaction_type': {'@type': 'reactionTypeEmoji', 'emoji': emoji},
            'is_big': false,
            'update_recent_reactions': true,
          });
        }
      case 'forward':
        final targets = app.workspace!.register.records.values
            .where((e) => e.selected)
            .map((e) => e.target)
            .toList();
        final destinations = <Conversation>[];
        for (final target in targets) {
          final resolved = await app.telegram!.resolve(
            target,
            '${app.me!['id']}',
          );
          if (resolved.chat != null) destinations.add(resolved);
        }
        if (!mounted) return;
        final destination = await showDialog<Conversation>(
          context: context,
          builder: (dialog) => SimpleDialog(
            title: const Text('Forward to'),
            children: destinations
                .map(
                  (d) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(dialog, d),
                    child: Text(d.title),
                  ),
                )
                .toList(),
          ),
        );
        if (destination != null) {
          await app.client!.call('forwardMessages', {
            'chat_id': destination.chatId,
            'topic_id': destination.topic,
            'from_chat_id': chat.chatId,
            'message_ids': [message['id']],
            'send_copy': false,
            'remove_caption': false,
          });
        }
    }
  });
}
