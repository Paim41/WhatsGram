import 'package:flutter_test/flutter_test.dart';
import 'package:whatsgram/telegram/client/td_client.dart';
import 'package:whatsgram/telegram/repositories/telegram_repository.dart';
import 'package:whatsgram/workspace/models/protocol.dart';
import 'package:whatsgram/features/media/media_service.dart';
import 'package:whatsgram/features/notifications/notification_service.dart';

class FakeClient implements TdClient {
  final requests = <Json>[];
  @override
  Stream<Json> get updates => const Stream.empty();
  @override
  Future<void> close() async {}
  @override
  Future<Json> call(String method, [Json parameters = const {}]) async {
    requests.add({'@type': method, ...parameters});
    if (method == 'createPrivateChat') {
      return {'id': parameters['user_id'], 'title': 'Counterpart'};
    }
    return {'@type': 'ok'};
  }
}

void main() {
  test('each account resolves participant pair to the other user', () async {
    final client = FakeClient();
    final repository = TelegramRepository(client);
    const pair = SelectionTarget('participant_pair', '10,20');
    expect((await repository.resolve(pair, '10')).chatId, 20);
    expect((await repository.resolve(pair, '20')).chatId, 10);
  });
  test('forum sending and reads stay inside the chosen topic', () async {
    final client = FakeClient();
    final repository = TelegramRepository(client);
    const conversation = Conversation(
      SelectionTarget('forum_topic', '123', '4'),
      {'id': -100123},
    );
    await repository.sendText(conversation, 'hello');
    expect(client.requests.last['topic_id'], {
      '@type': 'messageTopicForum',
      'forum_topic_id': 4,
    });
    final valid = <String, dynamic>{
      'id': 1,
      'chat_id': -100123,
      'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': 4},
    };
    final other = <String, dynamic>{
      'id': 2,
      'chat_id': -100123,
      'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': 5},
    };
    await repository.markViewed(conversation, [valid, other]);
    expect(client.requests.last['message_ids'], [1]);
    await expectLater(
      repository.sendText(conversation, 'bad reply', reply: other),
      throwsStateError,
    );
  });
  test(
    'unselected topics and control group never qualify for notifications',
    () {
      final genesis = Genesis(
        workspaceId: '11111111-1111-4111-8111-111111111111',
        owner: '10',
        participants: ['10', '20'],
      );
      final selection = SelectionRegister()
        ..apply(
          WorkspaceEvent(
            workspaceId: genesis.workspaceId,
            eventId: '33333333-3333-4333-8333-333333333333',
            actor: '10',
            device: '22222222-2222-4222-8222-222222222222',
            lamport: '1',
            target: const SelectionTarget('forum_topic', '123', '4'),
            selected: true,
          ),
        );
      final chat = <String, dynamic>{
        'type': {
          '@type': 'chatTypeSupergroup',
          'supergroup_id': 123,
          'is_channel': false,
        },
      };
      final message = <String, dynamic>{
        'chat_id': -100123,
        'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': 5},
      };
      expect(
        selectedMessageTarget(
          message: message,
          chat: chat,
          genesis: genesis,
          selection: selection,
          controlChat: -99,
        ),
        isNull,
      );
      message['topic_id']['forum_topic_id'] = 4;
      expect(
        selectedMessageTarget(
          message: message,
          chat: chat,
          genesis: genesis,
          selection: selection,
          controlChat: -99,
        )?.topic,
        '4',
      );
      expect(
        selectedMessageTarget(
          message: message,
          chat: chat,
          genesis: genesis,
          selection: selection,
          controlChat: -100123,
        ),
        isNull,
      );
    },
  );
  test(
    'export filenames cannot contain traversal, Windows devices or separators',
    () {
      expect(safeFilename('../../secret.txt'), isNot(contains('/')));
      expect(safeFilename('CON.txt'), 'file_CON.txt');
      expect(safeFilename('x\\y:bad?'), 'x_y_bad_');
      expect(safeFilename('..'), 'file_');
    },
  );
}
