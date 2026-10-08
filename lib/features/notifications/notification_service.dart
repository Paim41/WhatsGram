import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../telegram/client/td_client.dart';
import '../../workspace/models/protocol.dart';

SelectionTarget? selectedMessageTarget({
  required Json message,
  required Json chat,
  required Genesis genesis,
  required SelectionRegister selection,
  required int controlChat,
}) {
  if (message['chat_id'] == controlChat ||
      message['is_outgoing'] == true ||
      message['sending_state'] != null) {
    return null;
  }
  final type = chat['type'] as Json?;
  if (type?['@type'] == 'chatTypePrivate') {
    final users = [...genesis.participants]..sort(compareDecimal);
    if (!users.contains('${type!['user_id']}')) return null;
    final target = SelectionTarget('participant_pair', users.join(','));
    return selection.includes(target) ? target : null;
  }
  if (type?['@type'] != 'chatTypeSupergroup' || type?['is_channel'] == true) {
    return null;
  }
  final group = '${type!['supergroup_id']}';
  final entire = SelectionTarget('supergroup', group);
  if (selection.includes(entire)) return entire;
  if (message['topic_id']?['@type'] != 'messageTopicForum') return null;
  final topic = SelectionTarget(
    'forum_topic',
    group,
    '${message['topic_id']['forum_topic_id']}',
  );
  return selection.includes(topic) ? topic : null;
}

class NotificationService {
  final plugin = FlutterLocalNotificationsPlugin();
  bool initialized = false;
  Future<void> initialize(void Function(Json) onOpen) async {
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        windows: WindowsInitializationSettings(
          appName: 'WhatsGram',
          appUserModelId: 'WhatsGram.Desktop.Client',
          guid: '5295fe5c-5dcd-4c51-a54c-93a94d4f88d1',
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == null) return;
        try {
          onOpen(jsonDecode(response.payload!) as Json);
        } on FormatException {
          return;
        }
      },
    );
    initialized = true;
  }

  Future<void> requestPermission() async => plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();
  Future<void> show(int id, String title, String body, Json payload) async {
    if (!initialized) return;
    await plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'selected_messages',
          'Selected conversations',
          channelDescription: 'Messages in selected WhatsGram chats and topics',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
        ),
        windows: WindowsNotificationDetails(),
      ),
      payload: jsonEncode(payload),
    );
  }
}
