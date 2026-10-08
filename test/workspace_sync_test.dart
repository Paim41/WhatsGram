import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsgram/core/storage/local_store.dart';
import 'package:whatsgram/telegram/client/td_client.dart';
import 'package:whatsgram/workspace/models/protocol.dart';
import 'package:whatsgram/workspace/sync/workspace_sync.dart';

class MemoryStore extends LocalStore {
  final values = <String, Json>{};
  @override
  Future<Json> read(String key) async => values[key] ?? {};
  @override
  Future<void> write(String key, Json value) async {
    values[key] = jsonDecode(jsonEncode(value)) as Json;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

const workspaceId = '11111111-1111-4111-8111-111111111111';
final genesis = Genesis(
  workspaceId: workspaceId,
  owner: '10',
  participants: ['10', '20'],
);
const target = SelectionTarget('supergroup', '777');
WorkspaceEvent makeEvent(
  String digit,
  String clock,
  bool selected,
) => WorkspaceEvent(
  workspaceId: workspaceId,
  eventId:
      '$digit$digit$digit$digit$digit$digit$digit$digit-3333-4333-8333-333333333333',
  actor: '10',
  device: '22222222-2222-4222-8222-222222222222',
  lamport: clock,
  target: target,
  selected: selected,
);
Json telegramMessage(int id, Json record) => {
  'id': id,
  'chat_id': -10099,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 10},
  'content': {
    '@type': 'messageText',
    'text': {'text': jsonEncode(record)},
  },
};

class SyncClient implements TdClient {
  final stream = StreamController<Json>.broadcast(sync: true);
  final history = <Json>[];
  bool offline = false, missingGenesis = false;
  Json? overlap;
  int pages = 0;
  final sends = <Json>[];
  @override
  Stream<Json> get updates => stream.stream;
  @override
  Future<void> close() => stream.close();
  @override
  Future<Json> call(String method, [Json parameters = const {}]) async {
    if (offline) throw const TdException(500, 'offline');
    switch (method) {
      case 'getMessage':
        if (missingGenesis) throw const TdException(404, 'missing');
        return telegramMessage(1, genesis.toJson());
      case 'getChatHistory':
        pages++;
        if (overlap != null) {
          stream.add({'@type': 'updateNewMessage', 'message': overlap});
          overlap = null;
        }
        if (parameters['from_message_id'] == 0) return {'messages': history};
        return {'messages': <Json>[]};
      case 'sendMessage':
        final data =
            jsonDecode(parameters['input_message_content']['text']['text'])
                as Json;
        sends.add(data);
        final sent = telegramMessage(200 + sends.length, data);
        // Deliberately confirm before the sendMessage Future completes.
        stream.add({
          '@type': 'updateMessageSendSucceeded',
          'old_message_id': -1,
          'message': sent,
        });
        return {
          ...sent,
          'id': -1,
          'sending_state': {'@type': 'messageSendingStatePending'},
        };
      default:
        return {'@type': 'ok'};
    }
  }
}

Future<MemoryStore> initialStore() async {
  final store = MemoryStore();
  await store.write('account.10.workspace', {
    'device': '22222222-2222-4222-8222-222222222222',
    'genesis': genesis.toJson(),
    'supergroup': '99',
    'chat': -10099,
    'message': 1,
    'clock': '0',
    'events': <Json>[],
    'pending': <Json>[],
  });
  return store;
}

void main() {
  test(
    'bootstrap overlaps live updates without losing newer tombstones',
    () async {
      final client = SyncClient()
        ..history.add(telegramMessage(2, makeEvent('3', '1', true).toJson()))
        ..overlap = telegramMessage(3, makeEvent('4', '2', false).toJson());
      final sync = WorkspaceSync(client, await initialStore(), '10');
      await sync.restore();
      expect(sync.verified, true);
      expect(sync.register.includes(target), false);
      expect(sync.register.clock, BigInt.two);
      expect(client.pages, 2);
      sync.dispose();
      await client.close();
    },
  );
  test(
    'offline selection persists UUID and early send confirmation removes pending retry',
    () async {
      final store = await initialStore();
      final client = SyncClient();
      final sync = WorkspaceSync(client, store, '10');
      await sync.restore();
      client.offline = true;
      await sync.select(target, true);
      final id = sync.pending.single.eventId;
      expect(
        (await store.read(
          'account.10.workspace',
        ))['pending'].single['event_id'],
        id,
      );
      client.offline = false;
      await sync.flush();
      expect(client.sends.single['event_id'], id);
      expect(sync.pending, isEmpty);
      sync.dispose();
      await client.close();
    },
  );
  test('genesis disappearance keeps last selection and blocks sync', () async {
    final client = SyncClient()
      ..history.add(telegramMessage(2, makeEvent('3', '1', true).toJson()));
    final sync = WorkspaceSync(client, await initialStore(), '10');
    await sync.restore();
    client.missingGenesis = true;
    await sync.reconcile();
    expect(sync.verified, false);
    expect(sync.register.includes(target), true);
    expect(sync.error, isNotNull);
    await sync.disconnect();
    expect(sync.pending, isEmpty);
    expect(sync.genesis, isNull);
    sync.dispose();
    await client.close();
  });
}
