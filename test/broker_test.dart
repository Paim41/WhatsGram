import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsgram/telegram/client/td_client.dart';

void main() {
  test(
    'out-of-order responses correlate while updates preserve arrival order',
    () async {
      final sent = <Json>[];
      final broker = RequestBroker(sent.add);
      final updates = <String>[];
      final subscription = broker.updates.listen(
        (u) => updates.add(u['@type']),
      );
      final first = broker.call('first', {});
      final second = broker.call('second', {});
      broker.accept({'@type': 'updateOne'});
      broker.accept({'@type': 'ok', '@extra': sent[1]['@extra'], 'value': 2});
      broker.accept({'@type': 'updateTwo'});
      broker.accept({'@type': 'ok', '@extra': sent[0]['@extra'], 'value': 1});
      expect((await first)['value'], 1);
      expect((await second)['value'], 2);
      expect(updates, ['updateOne', 'updateTwo']);
      await subscription.cancel();
      await broker.dispose();
    },
  );
  test(
    'timeouts ignore late replies without dispatching them as updates',
    () async {
      final sent = <Json>[];
      final broker = RequestBroker(
        sent.add,
        timeout: const Duration(milliseconds: 5),
      );
      final updates = <Json>[];
      final subscription = broker.updates.listen(updates.add);
      await expectLater(
        broker.call('never', {}),
        throwsA(isA<TimeoutException>()),
      );
      broker.accept({'@type': 'ok', '@extra': sent.single['@extra']});
      expect(updates, isEmpty);
      await subscription.cancel();
      await broker.dispose();
    },
  );
  test('shutdown cancels requests and rejects further calls', () async {
    final broker = RequestBroker((_) {});
    final expectation = expectLater(
      broker.call('pending', {}),
      throwsStateError,
    );
    await broker.dispose();
    await expectation;
    await expectLater(broker.call('closed', {}), throwsStateError);
  });
  test(
    'Telegram errors retain code and human-readable rate-limit advice',
    () async {
      final sent = <Json>[];
      final broker = RequestBroker(sent.add);
      final expectation = expectLater(
        broker.call('rateLimit', {}),
        throwsA(
          isA<TdException>().having(
            (e) => e.toString(),
            'message',
            contains('wait'),
          ),
        ),
      );
      broker.accept({
        '@type': 'error',
        '@extra': sent.single['@extra'],
        'code': 429,
        'message': 'retry after 10',
      });
      await expectation;
      await broker.dispose();
    },
  );
}
