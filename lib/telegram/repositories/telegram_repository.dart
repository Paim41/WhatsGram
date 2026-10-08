import '../client/td_client.dart';
import '../../workspace/models/protocol.dart';

class Conversation {
  const Conversation(this.target, this.chat, {this.topicInfo, this.error});
  final SelectionTarget target;
  final Json? chat;
  final Json? topicInfo;
  final String? error;
  int get chatId => chat?['id'] as int? ?? 0;
  int? get topicId => target.topic == null ? null : int.parse(target.topic!);
  String get title =>
      topicInfo?['info']?['name'] as String? ??
      chat?['title'] as String? ??
      'Access required';
  Json? get topic => topicId == null
      ? null
      : {'@type': 'messageTopicForum', 'forum_topic_id': topicId};
  bool contains(Json message) =>
      message['chat_id'] == chatId &&
      (topicId == null ||
          message['topic_id']?['@type'] == 'messageTopicForum' &&
              message['topic_id']['forum_topic_id'] == topicId);
}

class TelegramRepository {
  const TelegramRepository(this.client);
  final TdClient client;
  Future<Conversation> resolve(SelectionTarget target, String self) async {
    try {
      final Json chat;
      if (target.kind == 'participant_pair') {
        final other = target.identity
            .split(',')
            .singleWhere((id) => id != self);
        chat = await client.call('createPrivateChat', {
          'user_id': int.parse(other),
          'force': false,
        });
      } else {
        chat = await client.call('createSupergroupChat', {
          'supergroup_id': int.parse(target.identity),
          'force': false,
        });
        final group = await client.call('getSupergroup', {
          'supergroup_id': int.parse(target.identity),
        });
        if (group['is_channel'] == true ||
            [
              'chatMemberStatusLeft',
              'chatMemberStatusBanned',
            ].contains(group['status']?['@type']) ||
            (group['status']?['@type'] == 'chatMemberStatusRestricted' &&
                group['status']?['is_member'] != true)) {
          throw StateError('Membership required');
        }
      }
      final info = target.topic == null
          ? null
          : await client.call('getForumTopic', {
              'chat_id': chat['id'],
              'forum_topic_id': int.parse(target.topic!),
            });
      return Conversation(target, chat, topicInfo: info);
    } catch (_) {
      return Conversation(
        target,
        null,
        error: 'Access required. Open/join the group in Telegram and refresh.',
      );
    }
  }

  Future<List<Json>> history(Conversation chat, {int before = 0}) async {
    final result = await client.call(
      chat.topicId == null ? 'getChatHistory' : 'getForumTopicHistory',
      {
        'chat_id': chat.chatId,
        if (chat.topicId != null) 'forum_topic_id': chat.topicId,
        'from_message_id': before,
        'offset': 0,
        'limit': 50,
        if (chat.topicId == null) 'only_local': false,
      },
    );
    return List<Json>.from(result['messages']);
  }

  Future<List<Json>> search(
    Conversation chat,
    String query, {
    int before = 0,
  }) async {
    final result = await client.call('searchChatMessages', {
      'chat_id': chat.chatId,
      'topic_id': chat.topic,
      'query': query,
      'from_message_id': before,
      'offset': 0,
      'limit': 50,
    });
    return List<Json>.from(result['messages']);
  }

  Future<Json> formatted(String text, {bool markdown = false}) async => markdown
      ? client.call('parseTextEntities', {
          'text': text,
          'parse_mode': {'@type': 'textParseModeMarkdown', 'version': 2},
        })
      : {'@type': 'formattedText', 'text': text, 'entities': <Json>[]};

  Future<Json> send(Conversation conversation, Json content, {Json? reply}) {
    if (reply != null && !conversation.contains(reply)) {
      throw StateError('Reply belongs to a different chat or topic');
    }
    return client.call('sendMessage', {
      'chat_id': conversation.chatId,
      'topic_id': conversation.topic,
      'reply_to': reply == null
          ? null
          : {'@type': 'inputMessageReplyToMessage', 'message_id': reply['id']},
      'input_message_content': content,
    });
  }

  Future<Json> sendText(
    Conversation chat,
    String text, {
    Json? reply,
    bool markdown = false,
  }) async => send(chat, {
    '@type': 'inputMessageText',
    'text': await formatted(text, markdown: markdown),
    'clear_draft': true,
  }, reply: reply);

  Future<Json> sendFile(
    Conversation chat,
    String path,
    String kind,
    String caption, {
    int duration = 0,
    Json? reply,
  }) async {
    final file = {'@type': 'inputFileLocal', 'path': path};
    final Json content;
    switch (kind) {
      case 'photo':
        content = {
          '@type': 'inputMessagePhoto',
          'photo': {
            '@type': 'inputPhoto',
            'photo': file,
            'added_sticker_file_ids': <int>[],
          },
        };
      case 'video':
        content = {
          '@type': 'inputMessageVideo',
          'video': {
            '@type': 'inputVideo',
            'video': file,
            'added_sticker_file_ids': <int>[],
            'supports_streaming': true,
          },
        };
      case 'voice':
        content = {
          '@type': 'inputMessageVoiceNote',
          'voice_note': {
            '@type': 'inputVoiceNote',
            'voice_note': file,
            'duration': duration,
            'waveform': '',
          },
        };
      default:
        content = {
          '@type': 'inputMessageDocument',
          'document': {
            '@type': 'inputDocument',
            'document': file,
            'disable_content_type_detection': true,
          },
        };
    }
    content['caption'] = await formatted(caption);
    return send(chat, content, reply: reply);
  }

  Future<void> markViewed(Conversation chat, List<Json> visible) async {
    final ids = visible
        .where(
          (m) =>
              chat.contains(m) &&
              m['sending_state'] == null &&
              (m['id'] as int) > 0,
        )
        .map((m) => m['id'])
        .toList();
    if (ids.isEmpty) return;
    await client.call('viewMessages', {
      'chat_id': chat.chatId,
      'message_ids': ids,
      'source': {
        '@type': chat.topicId == null
            ? 'messageSourceChatHistory'
            : 'messageSourceForumTopicHistory',
      },
      'force_read': true,
    });
  }

  Future<List<Json>> topics(int chatId) async {
    final topics = <Json>[];
    var date = 0, message = 0, topic = 0;
    final cursors = <String>{};
    do {
      if (!cursors.add('$date:$message:$topic')) break;
      final result = await client.call('getForumTopics', {
        'chat_id': chatId,
        'query': '',
        'offset_date': date,
        'offset_message_id': message,
        'offset_forum_topic_id': topic,
        'limit': 100,
      });
      topics.addAll(List<Json>.from(result['topics']));
      date = result['next_offset_date'] as int;
      message = result['next_offset_message_id'] as int;
      topic = result['next_offset_forum_topic_id'] as int;
    } while (topic != 0);
    return topics;
  }
}

String messageText(Json message) {
  final content = message['content'] as Json? ?? {};
  if (content['@type'] == 'messageText') {
    return content['text']['text'] as String;
  }
  final type = (content['@type'] as String? ?? 'Unsupported message')
      .replaceFirst('message', '');
  final caption = content['caption']?['text'] as String? ?? '';
  return caption.isEmpty ? '[$type]' : '[$type] $caption';
}

Json? messageFile(Json message) {
  final c = message['content'] as Json? ?? {};
  switch (c['@type']) {
    case 'messagePhoto':
      final sizes = c['photo']['sizes'] as List;
      return sizes.isEmpty ? null : sizes.last['photo'] as Json;
    case 'messageDocument':
      return c['document']['document'] as Json;
    case 'messageVideo':
      return c['video']['video'] as Json;
    case 'messageVoiceNote':
      return c['voice_note']['voice'] as Json;
    case 'messageAudio':
      return c['audio']['audio'] as Json;
    case 'messageAnimation':
      return c['animation']['animation'] as Json;
    case 'messageSticker':
      return c['sticker']['sticker'] as Json;
    default:
      return null;
  }
}
