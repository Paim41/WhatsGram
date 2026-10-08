import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../core/storage/local_store.dart';
import '../core/errors/diagnostics.dart';
import '../features/notifications/notification_service.dart';
import '../features/media/export_manager.dart';
import '../telegram/client/td_client.dart';
import '../telegram/native/td_native.dart';
import '../telegram/repositories/telegram_repository.dart';
import '../workspace/sync/workspace_sync.dart';

final appProvider = ChangeNotifierProvider((ref) => AppController());

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  final store = const LocalStore();
  final diagnostics = Diagnostics();
  TdClient? client;
  TelegramRepository? telegram;
  WorkspaceSync? workspace;
  Json authorization = {'@type': 'notStarted'};
  Json? me;
  String? error;
  String connection = 'Disconnected';
  bool starting = false, active = true;
  ThemeMode theme = ThemeMode.system;
  String slot = '', sessionPath = '';
  final chats = <int, Json>{};
  final users = <int, Json>{};
  final forumTopics = <String, Json>{};
  final files = <int, Json>{};
  final muted = <String>{}, pinned = <String>{};
  bool enterSends = true;
  bool notificationsEnabled = false, notificationPreviews = false;
  final notifications = NotificationService();
  ExportManager? exports;
  Timer? _maintenance;
  final notified = <String>{};
  Json? notificationDestination;
  Future<void> _notificationQueue = Future.value();
  bool _settingParameters = false;
  bool _handlingReady = false;
  bool _loggingOut = false;
  StreamSubscription<Json>? _subscription;
  Conversation? visible;

  AppController() {
    WidgetsBinding.instance.addObserver(this);
  }
  bool get ready => authorization['@type'] == 'authorizationStateReady';

  Future<void> start() async {
    if (starting || client != null) return;
    starting = true;
    diagnostics.record('startup');
    _settingParameters = false;
    _handlingReady = false;
    _loggingOut = false;
    error = null;
    notifyListeners();
    try {
      const api = String.fromEnvironment('TELEGRAM_API_ID');
      const hash = String.fromEnvironment('TELEGRAM_API_HASH');
      if (int.tryParse(api) == null ||
          int.parse(api) <= 0 ||
          !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(hash)) {
        throw StateError(
          'Telegram developer credentials are missing. Copy config/telegram.example.json to config/telegram.local.json and run with --dart-define-from-file=config/telegram.local.json.',
        );
      }
      final preferences = await store.read('device.preferences');
      theme = ThemeMode.values.firstWhere(
        (m) => m.name == preferences['theme'],
        orElse: () => ThemeMode.system,
      );
      enterSends = preferences['enterSends'] as bool? ?? true;
      notificationsEnabled =
          preferences['notificationsEnabled'] as bool? ?? false;
      notificationPreviews =
          preferences['notificationPreviews'] as bool? ?? false;
      final session = await store.read('session.active');
      slot = session['slot'] as String? ?? const Uuid().v4();
      await store.write('session.active', {'slot': slot});
      final base = await getApplicationSupportDirectory();
      sessionPath = p.join(base.path, 'sessions', slot);
      await Directory(sessionPath).create(recursive: true);
      client = await NativeTdClient.start();
      diagnostics.record('native_ready');
      telegram = TelegramRepository(client!);
      _subscription = client!.updates.listen(_update);
      await _authorization(await client!.call('getAuthorizationState'));
    } catch (e) {
      diagnostics.record('native_error');
      error = '$e';
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  Future<void> _authorization(Json state) async {
    authorization = state;
    notifyListeners();
    try {
      if (state['@type'] == 'authorizationStateWaitTdlibParameters') {
        if (_settingParameters) return;
        _settingParameters = true;
        await client!.call('setTdlibParameters', {
          'use_test_dc': false,
          'database_directory': p.join(sessionPath, 'database'),
          'files_directory': p.join(sessionPath, 'media'),
          'database_encryption_key': await store.databaseKey(slot),
          'use_file_database': true,
          'use_chat_info_database': true,
          'use_message_database': true,
          'use_secret_chats': false,
          'api_id': int.parse(const String.fromEnvironment('TELEGRAM_API_ID')),
          'api_hash': const String.fromEnvironment('TELEGRAM_API_HASH'),
          'system_language_code': Platform.localeName.split('_').first,
          'device_model': Platform.isWindows ? 'Windows PC' : 'Android',
          'system_version': Platform.operatingSystemVersion,
          'application_version': '0.1.0',
        });
      } else if (state['@type'] == 'authorizationStateReady' &&
          workspace == null) {
        if (_handlingReady) return;
        _handlingReady = true;
        me = await client!.call('getMe');
        diagnostics.record('authorization_ready');
        final preferences = await store.read(
          'account.${me!['id']}.preferences',
        );
        muted.addAll(List<String>.from(preferences['muted'] ?? []));
        pinned.addAll(List<String>.from(preferences['pinned'] ?? []));
        final delivered = await store.read(
          'account.${me!['id']}.notifications',
        );
        notified.addAll(List<String>.from(delivered['seen'] ?? []));
        try {
          await notifications.initialize((destination) {
            if (destination['account'] == '${me?['id']}') {
              notificationDestination = destination;
              notifyListeners();
            }
          });
        } catch (_) {
          error = 'Native notifications could not initialize on this device.';
        }
        workspace = WorkspaceSync(client!, store, '${me!['id']}')
          ..addListener(notifyListeners);
        exports = ExportManager(client!, store, '${me!['id']}');
        await exports!.restore();
        await workspace!.restore();
        _handlingReady = false;
        _maintenance?.cancel();
        _maintenance = Timer.periodic(const Duration(seconds: 30), (_) {
          unawaited(exports?.flush(_isSelected));
        });
      } else if (state['@type'] == 'authorizationStateClosed') {
        diagnostics.record('authorization_closed');
        visible = null;
        me = null;
        workspace?.dispose();
        workspace = null;
        _maintenance?.cancel();
        exports = null;
        if (_loggingOut) {
          await store.delete('session.active');
          await store.delete('tdlib.database.key.$slot');
        }
        chats.clear();
        files.clear();
        muted.clear();
        pinned.clear();
        notified.clear();
        final old = client;
        client = null;
        telegram = null;
        await _subscription?.cancel();
        await old?.close();
      }
    } catch (e) {
      _handlingReady = false;
      error = '$e';
    }
    notifyListeners();
  }

  void _update(Json update) {
    switch (update['@type']) {
      case 'updateAuthorizationState':
        if (update['authorization_state']?['@type'] ==
            'authorizationStateLoggingOut') {
          _loggingOut = true;
        }
        unawaited(
          _authorization(
            Map<String, dynamic>.from(update['authorization_state']),
          ),
        );
      case 'updateConnectionState':
        connection = (update['state']['@type'] as String).replaceFirst(
          'connectionState',
          '',
        );
      case 'updateNewChat':
        chats[update['chat']['id']] = Map<String, dynamic>.from(update['chat']);
      case 'updateUser':
        users[update['user']['id']] = Map<String, dynamic>.from(update['user']);
      case 'updateUserStatus':
        users[update['user_id']]?['status'] = update['status'];
      case 'updateForumTopic':
        forumTopics['${update['chat_id']}:${update['forum_topic_id']}'] =
            update;
      case 'updateChatLastMessage':
        chats[update['chat_id']]?['last_message'] = update['last_message'];
      case 'updateChatReadInbox':
        chats[update['chat_id']]?['unread_count'] = update['unread_count'];
        chats[update['chat_id']]?['last_read_inbox_message_id'] =
            update['last_read_inbox_message_id'];
      case 'updateChatReadOutbox':
        chats[update['chat_id']]?['last_read_outbox_message_id'] =
            update['last_read_outbox_message_id'];
      case 'updateFile':
        files[update['file']['id']] = Map<String, dynamic>.from(update['file']);
      case 'updateNewMessage':
        final message = Map<String, dynamic>.from(update['message']);
        _notificationQueue = _notificationQueue.catchError((Object _) {}).then((
          _,
        ) async {
          await _notifyMessage(message);
          if (await _isSelected(message)) {
            await exports?.enqueue(message);
            await exports?.flush(_isSelected);
          }
        });
    }
    notifyListeners();
  }

  Future<void> authenticate(String value) async {
    final kind = authorization['@type'];
    switch (kind) {
      case 'authorizationStateWaitPhoneNumber':
        await client!.call('setAuthenticationPhoneNumber', {
          'phone_number': value.trim(),
        });
      case 'authorizationStateWaitCode':
        await client!.call('checkAuthenticationCode', {'code': value.trim()});
      case 'authorizationStateWaitPassword':
        await client!.call('checkAuthenticationPassword', {'password': value});
      case 'authorizationStateWaitEmailAddress':
        await client!.call('setAuthenticationEmailAddress', {
          'email_address': value.trim(),
        });
      case 'authorizationStateWaitEmailCode':
        await client!.call('checkAuthenticationEmailCode', {
          'code': {
            '@type': 'emailAddressAuthenticationCode',
            'code': value.trim(),
          },
        });
      default:
        throw StateError('Telegram is not requesting text input now.');
    }
  }

  Future<void> savePreferences() async {
    await exports?.save();
    await store.write('device.preferences', {
      'theme': theme.name,
      'enterSends': enterSends,
      'notificationsEnabled': notificationsEnabled,
      'notificationPreviews': notificationPreviews,
    });
    if (me != null) {
      await store.write('account.${me!['id']}.preferences', {
        'muted': muted.toList(),
        'pinned': pinned.toList(),
      });
    }
    notifyListeners();
  }

  Future<void> logout() async {
    _loggingOut = true;
    await client!.call('logOut');
  }

  Future<void> _notifyMessage(Json message) async {
    final sync = workspace;
    if (!notificationsEnabled ||
        sync?.genesis == null ||
        !sync!.verified ||
        sync.syncing ||
        message['is_outgoing'] == true ||
        message['chat_id'] == sync.controlChat) {
      return;
    }
    final key = '${message['chat_id']}:${message['id']}';
    if (notified.contains(key)) return;
    final metadata =
        chats[message['chat_id']] ??
        await client!.call('getChat', {'chat_id': message['chat_id']});
    final target = selectedMessageTarget(
      message: message,
      chat: metadata,
      genesis: sync.genesis!,
      selection: sync.register,
      controlChat: sync.controlChat,
    );
    if (target == null || muted.contains(target.key)) return;
    final resolved = await telegram!.resolve(target, '${me!['id']}');
    if (resolved.chat == null || !sync.register.includes(target)) return;
    // Suppress history replay, already-read messages, and active conversations.
    final readThrough =
        resolved.topicInfo?['last_read_inbox_message_id'] ??
        metadata['last_read_inbox_message_id'] ??
        0;
    if ((message['id'] as int) <= readThrough ||
        active && visible?.contains(message) == true ||
        DateTime.now().millisecondsSinceEpoch ~/ 1000 -
                (message['date'] as int) >
            120) {
      return;
    }
    notified.add(key);
    while (notified.length > 2000) {
      notified.remove(notified.first);
    }
    await store.write('account.${me!['id']}.notifications', {
      'seen': notified.toList(),
    });
    await notifications.show(
      (message['id'] as int).hashCode & 0x7fffffff,
      notificationPreviews ? resolved.title : 'WhatsGram',
      notificationPreviews
          ? messageText(message)
          : 'New message in a selected conversation',
      {'account': '${me!['id']}', 'target': target.toJson()},
    );
  }

  Future<bool> _isSelected(Json message) async {
    final sync = workspace;
    if (sync?.genesis == null ||
        !sync!.verified ||
        sync.syncing ||
        client == null) {
      return false;
    }
    final metadata =
        chats[message['chat_id']] ??
        await client!.call('getChat', {'chat_id': message['chat_id']});
    final target = selectedMessageTarget(
      message: message,
      chat: metadata,
      genesis: sync.genesis!,
      selection: sync.register,
      controlChat: sync.controlChat,
    );
    if (target == null) return false;
    final resolved = await telegram!.resolve(target, '${me!['id']}');
    return resolved.chat != null && sync.register.includes(target);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) unawaited(workspace?.reconcile());
    notifyListeners();
  }

  @override
  void dispose() {
    _maintenance?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    workspace?.dispose();
    client?.close();
    super.dispose();
  }
}
