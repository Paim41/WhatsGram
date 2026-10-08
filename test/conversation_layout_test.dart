import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsgram/app/controller.dart';
import 'package:whatsgram/features/conversation/conversation_screen.dart';
import 'package:whatsgram/telegram/client/td_client.dart';
import 'package:whatsgram/telegram/repositories/telegram_repository.dart';
import 'package:whatsgram/workspace/models/protocol.dart';

class ConversationClient implements TdClient {
  final sent = <Json>[];
  final events = StreamController<Json>.broadcast();
  @override
  Stream<Json> get updates => events.stream;
  @override
  Future<void> close() => events.close();
  @override
  Future<Json> call(String method, [Json parameters = const {}]) async {
    if (method == 'getChatHistory') return {'messages': <Json>[]};
    if (method == 'sendMessage') {
      sent.add(parameters);
      return {
        'id': 1048576,
        'chat_id': 20,
        'date': 1700000000,
        'is_outgoing': true,
        'content': {
          '@type': 'messageText',
          'text': parameters['input_message_content']['text'],
        },
      };
    }
    return {'@type': 'ok'};
  }
}

void main() {
  for (final size in [const Size(360, 640), const Size(1100, 760)]) {
    testWidgets('composer works at $size with keyboard and large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = ConversationClient();
      final app = AppController()
        ..client = client
        ..telegram = TelegramRepository(client);
      const conversation = Conversation(
        SelectionTarget('participant_pair', '10,20'),
        {
          'id': 20,
          'title': 'Test counterpart',
          'type': {'@type': 'chatTypePrivate', 'user_id': 20},
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: ConversationScreen(
                app: app,
                conversation: conversation,
                onBack: () {},
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'Hello\nsecond line');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        client.sent.single['input_message_content']['text']['text'],
        'Hello\nsecond line',
      );
      expect(find.text('Hello\nsecond line'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.client = null;
      app.dispose();
      await client.close();
    });
  }
}
