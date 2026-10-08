import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../telegram/client/td_client.dart';
import '../../workspace/models/protocol.dart';
import '../../ui/shared/branding.dart';

class SelectionPicker extends StatefulWidget {
  const SelectionPicker({super.key, required this.app});
  final AppController app;
  @override
  State<SelectionPicker> createState() => _SelectionPickerState();
}

class _SelectionPickerState extends State<SelectionPicker> {
  List<Json> groups = [];
  bool loading = true;
  String? error;
  String query = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final client = widget.app.client!;
      final ids = <int>{};
      for (final list in ['chatListMain', 'chatListArchive']) {
        while (true) {
          try {
            await client.call('loadChats', {
              'chat_list': {'@type': list},
              'limit': 100,
            });
          } on TdException catch (e) {
            if (e.code == 404) break;
            rethrow;
          }
        }
        final result = await client.call('getChats', {
          'chat_list': {'@type': list},
          'limit': 10000,
        });
        ids.addAll(List<int>.from(result['chat_ids']));
      }
      for (final id in ids) {
        final chat = await client.call('getChat', {'chat_id': id});
        if (id != widget.app.workspace!.controlChat &&
            chat['type']?['@type'] == 'chatTypeSupergroup' &&
            chat['type']?['is_channel'] == false) {
          groups.add(chat);
        }
      }
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final workspace = widget.app.workspace!;
    final people = [...workspace.genesis!.participants]..sort(compareDecimal);
    final pair = SelectionTarget('participant_pair', people.join(','));
    return Scaffold(
      appBar: AppBar(title: const Text('Choose shared conversations')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Selecting a whole group includes all of its topics. Topic selections apply when the whole group is off. Your counterpart must already have access, or will see “Access required”.',
          ),
          CheckboxListTile(
            value: workspace.register.includes(pair),
            title: const Text('Conversation with your counterpart'),
            onChanged: (value) => change(pair, value!),
          ),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Find a group',
            ),
            onChanged: (value) => setState(() => query = value.toLowerCase()),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          ...groups
              .where(
                (g) => (g['title'] as String).toLowerCase().contains(query),
              )
              .map((group) {
                final target = SelectionTarget(
                  'supergroup',
                  '${group['type']['supergroup_id']}',
                );
                return Card(
                  child: Column(
                    children: [
                      CheckboxListTile(
                        value: workspace.register.includes(target),
                        title: Text(group['title']),
                        onChanged: (v) => change(target, v!),
                      ),
                      TextButton(
                        onPressed: () => runAction(context, () async {
                          final metadata = await widget.app.client!.call(
                            'getSupergroup',
                            {'supergroup_id': int.parse(target.identity)},
                          );
                          if (metadata['is_forum'] != true) {
                            throw StateError(
                              'This group is not a Telegram forum.',
                            );
                          }
                          final topics = await widget.app.telegram!.topics(
                            group['id'],
                          );
                          if (!context.mounted) return;
                          await showDialog<void>(
                            context: context,
                            builder: (dialog) => StatefulBuilder(
                              builder: (dialog, refresh) => AlertDialog(
                                title: Text(group['title']),
                                content: SizedBox(
                                  width: 480,
                                  child: ListView(
                                    shrinkWrap: true,
                                    children: topics.map((topic) {
                                      final selection = SelectionTarget(
                                        'forum_topic',
                                        target.identity,
                                        '${topic['info']['forum_topic_id']}',
                                      );
                                      return CheckboxListTile(
                                        title: Text(topic['info']['name']),
                                        subtitle: Text(
                                          topic['info']['is_closed'] == true
                                              ? 'Closed'
                                              : topic['info']['is_hidden'] ==
                                                    true
                                              ? 'Hidden'
                                              : 'Topic ${selection.topic}',
                                        ),
                                        value: workspace.register.includes(
                                          selection,
                                        ),
                                        onChanged:
                                            workspace.register.includes(target)
                                            ? null
                                            : (v) => runAction(
                                                dialog,
                                                () async {
                                                  await workspace.select(
                                                    selection,
                                                    v!,
                                                  );
                                                  refresh(() {});
                                                  if (mounted) setState(() {});
                                                },
                                              ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialog),
                                    child: const Text('Done'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        child: const Text('Choose individual topics'),
                      ),
                    ],
                  ),
                );
              }),
        ],
      ),
    );
  }

  void change(SelectionTarget target, bool value) =>
      runAction(context, () async {
        await widget.app.workspace!.select(target, value);
        if (mounted) setState(() {});
      });
}
