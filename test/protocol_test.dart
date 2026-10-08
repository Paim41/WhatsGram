import 'package:flutter_test/flutter_test.dart';
import 'package:whatsgram/workspace/models/protocol.dart';
import 'package:whatsgram/telegram/client/td_client.dart';

const workspace = '11111111-1111-4111-8111-111111111111';
const device = '22222222-2222-4222-8222-222222222222';
final genesis = Genesis(
  workspaceId: workspace,
  owner: '10',
  participants: ['10', '20'],
);
const target = SelectionTarget('forum_topic', '123', '4');
WorkspaceEvent event(String id, String counter, String actor, bool selected) =>
    WorkspaceEvent(
      workspaceId: workspace,
      eventId: '$id$id$id$id$id$id$id$id-3333-4333-8333-333333333333',
      actor: actor,
      device: device,
      lamport: counter,
      target: target,
      selected: selected,
    );

void main() {
  test(
    'concurrent writes converge in either replay order and preserve tombstones',
    () {
      final select = event('3', '42', '10', true);
      final deselect = event('4', '42', '20', false);
      final a = SelectionRegister()
        ..apply(select)
        ..apply(deselect)
        ..apply(select);
      final b = SelectionRegister()
        ..apply(deselect)
        ..apply(select);
      expect(a.includes(target), false);
      expect(b.records[target.key]!.toJson(), a.records[target.key]!.toJson());
      expect(a.clock, BigInt.from(42));
      expect(a.records[target.key]!.selected, false);
    },
  );
  test('Lamport and actor IDs use numeric comparison, never lexical', () {
    expect(
      event('3', '10', '10', true).compareTo(event('4', '9', '20', false)),
      greaterThan(0),
    );
    expect(
      event('3', '10', '20', true).compareTo(event('4', '10', '10', false)),
      greaterThan(0),
    );
  });
  test(
    'duplicate UUID retries do not change state and conflicting UUIDs fail',
    () {
      final first = event('3', '1', '10', true);
      final register = SelectionRegister()
        ..apply(first)
        ..apply(first);
      expect(register.seen.length, 1);
      expect(
        () => register.apply(event('3', '2', '10', false)),
        throwsFormatException,
      );
    },
  );
  test('full-group selection overrides individual topic tombstones', () {
    final register = SelectionRegister()..apply(event('3', '1', '10', false));
    register.apply(
      WorkspaceEvent(
        workspaceId: workspace,
        eventId: '44444444-4444-4444-8444-444444444444',
        actor: '10',
        device: device,
        lamport: '2',
        target: const SelectionTarget('supergroup', '123'),
        selected: true,
      ),
    );
    expect(register.includes(target), true);
    expect(
      register.includes(const SelectionTarget('forum_topic', '999', '4')),
      false,
    );
  });
  test(
    'sender, version, participant and arbitrary-private-chat validation',
    () {
      final json = event('3', '1', '10', true).toJson();
      expect(
        () => WorkspaceEvent.parse(json, genesis, '20'),
        throwsFormatException,
      );
      expect(
        () =>
            WorkspaceEvent.parse({...json, 'schema_version': 2}, genesis, '10'),
        throwsFormatException,
      );
      expect(
        () => WorkspaceEvent.parse({...json, 'lamport': '1e10'}, genesis, '10'),
        throwsFormatException,
      );
      expect(
        () => SelectionTarget.parse({
          'kind': 'participant_pair',
          'user_ids': ['10', '30'],
        }, genesis.participants),
        throwsFormatException,
      );
      expect(
        () => Genesis.parse(genesis.toJson(), '20'),
        throwsFormatException,
      );
      expect(Genesis.parse(genesis.toJson(), '10').owner, '10');
    },
  );
  test(
    'forwarded, anonymous, oversized and malformed records are rejected',
    () {
      Json message(String text) => {
        'sender_id': {'@type': 'messageSenderUser', 'user_id': 10},
        'content': {
          '@type': 'messageText',
          'text': {'text': text},
        },
      };
      expect(recordFromMessage(message('not JSON')), isNull);
      expect(recordFromMessage(message('x' * 8193)), isNull);
      expect(recordFromMessage({...message('{}'), 'forward_info': {}}), isNull);
      expect(
        recordFromMessage({
          ...message('{}'),
          'sender_id': {'@type': 'messageSenderChat', 'chat_id': 10},
        }),
        isNull,
      );
    },
  );
}
