import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsgram/app/controller.dart';
import 'package:whatsgram/features/conversation/conversation_screen.dart';
import 'package:whatsgram/features/settings/settings_screen.dart';
import 'package:whatsgram/telegram/client/td_client.dart';
import 'package:whatsgram/telegram/repositories/telegram_repository.dart';
import 'package:whatsgram/ui/shared/shell.dart';
import 'package:whatsgram/workspace/models/protocol.dart';
import 'package:whatsgram/workspace/sync/workspace_sync.dart';
import 'conversation_layout_test.dart' show ConversationClient;
import 'workspace_sync_test.dart' show MemoryStore;

class NavigationClient extends ConversationClient {
  @override
  Future<Json> call(String method, [Json parameters = const {}]) async {
    if (method == 'createPrivateChat') {
      return {
        'id': 20,
        'title': 'Counterpart',
        'type': {'@type': 'chatTypePrivate', 'user_id': 20},
      };
    }
    return super.call(method, parameters);
  }
}

void main() {
  testWidgets(
    'desktop navigation clears the old conversation and selected tab',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = NavigationClient();
      final workspace = WorkspaceSync(client, MemoryStore(), '10')
        ..genesis = Genesis(
          workspaceId: '11111111-1111-4111-8111-111111111111',
          owner: '10',
          participants: ['10', '20'],
        );
      workspace.register.apply(
        WorkspaceEvent(
          workspaceId: workspace.genesis!.workspaceId,
          eventId: '33333333-3333-4333-8333-333333333333',
          actor: '10',
          device: '22222222-2222-4222-8222-222222222222',
          lamport: '1',
          target: const SelectionTarget('participant_pair', '10,20'),
          selected: true,
        ),
      );
      final app = AppController()
        ..client = client
        ..workspace = workspace
        ..telegram = TelegramRepository(client)
        ..me = {'id': 10};
      await tester.pumpWidget(MaterialApp(home: WhatsGramShell(app: app)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Counterpart'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);
      await tester.tap(find.text('Groups / Topics'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsNothing);
      expect(find.text('Counterpart'), findsNothing);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        1,
      );
      expect(app.visible, isNull);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        2,
      );
      expect(find.byType(ConversationScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
