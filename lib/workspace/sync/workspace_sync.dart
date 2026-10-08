import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../core/storage/local_store.dart';
import '../../telegram/client/td_client.dart';
import '../models/protocol.dart';

class WorkspaceSync extends ChangeNotifier {
  WorkspaceSync(this.client, this.store, this.self);
  final TdClient client;
  final LocalStore store;
  final String self;
  Genesis? genesis;
  int controlChat = 0, genesisMessage = 0;
  String controlSupergroup = '', device = const Uuid().v4();
  String? error;
  bool syncing = false,
      verified = false,
      _flushing = false,
      _disconnected = false;
  SelectionRegister register = SelectionRegister();
  final pending = <WorkspaceEvent>[];
  final _buffer = <Json>[];
  final _sendResults = <int, Json>{};
  bool _futureSchema = false;
  StreamSubscription<Json>? _subscription;
  Timer? _retry;
  Future<void> _persistence = Future.value();
  String get _key => 'account.$self.workspace';
  Json get pairing => {
    'protocol': protocolMarker,
    'schema_version': 1,
    'workspace_id': genesis!.workspaceId,
    'supergroup_id': controlSupergroup,
    'genesis_message_id': '$genesisMessage',
    'owner_user_id': genesis!.owner,
  };

  Future<void> restore() async {
    final data = await store.read(_key);
    device = data['device'] as String? ?? device;
    if (data['genesis'] == null) return;
    genesis = Genesis.parse(
      Map<String, dynamic>.from(data['genesis']),
      data['genesis']['owner_user_id'],
    );
    if (!genesis!.participants.contains(self)) {
      throw StateError('Workspace belongs to another account');
    }
    controlSupergroup = data['supergroup'] as String;
    controlChat = data['chat'] as int;
    genesisMessage = data['message'] as int;
    register.clock = BigInt.parse(data['clock'] as String? ?? '0');
    for (final raw in data['events'] as List? ?? []) {
      _applyJson(Map<String, dynamic>.from(raw), raw['actor_user_id']);
    }
    for (final raw in data['pending'] as List? ?? []) {
      pending.add(
        WorkspaceEvent.parse(Map<String, dynamic>.from(raw), genesis!, self),
      );
    }
    _listen();
    await reconcile();
  }

  Future<void> _save() {
    final data = {
      'device': device,
      'genesis': genesis?.toJson(),
      'supergroup': controlSupergroup,
      'chat': controlChat,
      'message': genesisMessage,
      'clock': '${register.clock}',
      'events': register.records.values.map((e) => e.toJson()).toList(),
      'pending': pending.map((e) => e.toJson()).toList(),
    };
    _persistence = _persistence
        .catchError((Object _) {})
        .then((_) => store.write(_key, data));
    return _persistence;
  }

  void _listen() {
    _disconnected = false;
    _subscription ??= client.updates.listen((event) {
      if (event['old_message_id'] is int &&
          event['message']?['chat_id'] == controlChat &&
          [
            'updateMessageSendSucceeded',
            'updateMessageSendFailed',
          ].contains(event['@type'])) {
        _sendResults[event['old_message_id']] = event;
        while (_sendResults.length > 128) {
          _sendResults.remove(_sendResults.keys.first);
        }
      }
      if (event['@type'] == 'updateConnectionState' &&
          event['state']?['@type'] == 'connectionStateReady') {
        unawaited(reconcile());
      }
      final message = event['message'];
      if (message is Json &&
          message['chat_id'] == controlChat &&
          message['sending_state'] == null) {
        if (syncing) {
          _buffer.add(message);
        } else {
          _consume(message);
          unawaited(
            _save().catchError((Object e) {
              error = '$e';
              notifyListeners();
            }),
          );
        }
        notifyListeners();
      }
      if (event['chat_id'] == controlChat &&
          [
            'updateDeleteMessages',
            'updateMessageContent',
            'updateMessageEdited',
          ].contains(event['@type'])) {
        unawaited(reconcile());
      }
    });
    _retry ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(reconcile()),
    );
  }

  Future<Json> create(String otherId) async {
    if (!validId(otherId) || otherId == self) {
      throw const FormatException('Choose the other person’s Telegram user ID');
    }
    await client.call('getUser', {'user_id': int.parse(otherId)});
    final chat = await client.call('createNewSupergroupChat', {
      'title': 'WhatsGram settings',
      'is_forum': false,
      'is_channel': false,
      'description':
          'Private WhatsGram workspace settings. Records are visible to members.',
      'message_auto_delete_time': 0,
      'for_import': false,
    });
    controlChat = chat['id'] as int;
    controlSupergroup = '${chat['type']['supergroup_id']}';
    await client.call('toggleSupergroupIsAllHistoryAvailable', {
      'supergroup_id': int.parse(controlSupergroup),
      'is_all_history_available': true,
    });
    genesis = Genesis(
      workspaceId: const Uuid().v4(),
      owner: self,
      participants: [self, otherId],
    );
    _listen();
    final sent = await _sendRecord(genesis!.toJson());
    final confirmed = await _confirm(sent);
    genesisMessage = confirmed['id'] as int;
    verified = true;
    await _save();
    String? invite;
    try {
      final result = await client.call('addChatMember', {
        'chat_id': controlChat,
        'user_id': int.parse(otherId),
        'forward_limit': 0,
      });
      if ((result['failed_to_add_members'] as List? ?? []).isNotEmpty) {
        throw StateError('Invite restricted');
      }
    } catch (_) {
      final link = await client.call('createChatInviteLink', {
        'chat_id': controlChat,
        'name': 'WhatsGram participant',
        'expiration_date': 0,
        'member_limit': 1,
        'creates_join_request': false,
      });
      invite = link['invite_link'] as String;
    }
    notifyListeners();
    return {'pairing': pairing, 'invite_link': ?invite};
  }

  Future<Genesis> inspectPairing(String payload) async {
    if (utf8.encode(payload).length > 8192) {
      throw const FormatException('Pairing payload too large');
    }
    final data = jsonDecode(payload) as Json;
    if (data.length != 6 ||
        data['protocol'] != protocolMarker ||
        data['schema_version'] != 1 ||
        !validUuid(data['workspace_id']) ||
        !validId(data['supergroup_id']) ||
        !validId(data['genesis_message_id']) ||
        !validId(data['owner_user_id'])) {
      throw const FormatException('Invalid pairing payload');
    }
    final chat = await client.call('createSupergroupChat', {
      'supergroup_id': int.parse(data['supergroup_id']),
      'force': false,
    });
    final group = await client.call('getSupergroup', {
      'supergroup_id': int.parse(data['supergroup_id']),
    });
    if (group['is_channel'] == true ||
        [
          'chatMemberStatusLeft',
          'chatMemberStatusBanned',
        ].contains(group['status']?['@type']) ||
        (group['status']?['@type'] == 'chatMemberStatusRestricted' &&
            group['status']?['is_member'] != true)) {
      throw StateError(
        'Join the private settings group through the owner’s invite first.',
      );
    }
    final message = await client.call('getMessage', {
      'chat_id': chat['id'],
      'message_id': int.parse(data['genesis_message_id']),
    });
    final raw = recordFromMessage(message);
    if (raw == null) {
      throw const FormatException('Genesis is missing or forwarded');
    }
    final checked = Genesis.parse(raw, '${message['sender_id']['user_id']}');
    if (checked.workspaceId != data['workspace_id'] ||
        checked.owner != data['owner_user_id'] ||
        !checked.participants.contains(self)) {
      throw StateError('Owner or workspace identity mismatch');
    }
    return checked;
  }

  Future<void> acceptPairing(String payload) async {
    final checked = await inspectPairing(payload);
    final data = jsonDecode(payload) as Json;
    final chat = await client.call('createSupergroupChat', {
      'supergroup_id': int.parse(data['supergroup_id']),
      'force': false,
    });
    genesis = checked;
    controlChat = chat['id'] as int;
    controlSupergroup = data['supergroup_id'];
    genesisMessage = int.parse(data['genesis_message_id']);
    pending.clear();
    register = SelectionRegister();
    _listen();
    await reconcile();
  }

  void _applyJson(Json raw, String sender) {
    final event = WorkspaceEvent.parse(raw, genesis!, sender);
    register.apply(event);
  }

  void _consume(Json message) {
    final raw = recordFromMessage(message);
    if (raw == null) return;
    if (raw['workspace_id'] != genesis?.workspaceId ||
        raw['operation'] == 'genesis') {
      return;
    }
    final sender = '${message['sender_id']['user_id']}';
    if (!genesis!.participants.contains(sender)) return;
    if (raw['schema_version'] != 1) {
      _futureSchema = true;
      verified = false;
      error =
          'A future workspace schema was found. Update WhatsGram before syncing.';
      return;
    }
    try {
      final event = WorkspaceEvent.parse(raw, genesis!, sender);
      register.apply(event);
      pending.removeWhere(
        (e) =>
            e.eventId == event.eventId &&
            jsonEncode(e.toJson()) == jsonEncode(event.toJson()),
      );
    } on FormatException {
      /* Untrusted chat data never becomes configuration. */
    }
  }

  Future<void> reconcile() async {
    if (genesis == null || syncing || _disconnected) return;
    syncing = true;
    notifyListeners();
    final old = register;
    try {
      final message = await client.call('getMessage', {
        'chat_id': controlChat,
        'message_id': genesisMessage,
      });
      final raw = recordFromMessage(message);
      if (raw == null) {
        throw StateError(
          'Trusted genesis is missing. Ask the owner to create a new workspace.',
        );
      }
      final checked = Genesis.parse(raw, '${message['sender_id']['user_id']}');
      if (jsonEncode(checked.toJson()) != jsonEncode(genesis!.toJson())) {
        throw StateError(
          'Trusted genesis changed. Workspace recovery is required.',
        );
      }
      register = SelectionRegister()..clock = old.clock;
      _futureSchema = false;
      verified = true;
      error = null;
      var before = 0;
      final visited = <int>{};
      while (!_disconnected) {
        final page = await client.call('getChatHistory', {
          'chat_id': controlChat,
          'from_message_id': before,
          'offset': 0,
          'limit': 100,
          'only_local': false,
        });
        final messages = List<Json>.from(page['messages']);
        if (messages.isEmpty) break;
        for (final item in messages) {
          if (item['sending_state'] == null) _consume(item);
        }
        final next = messages.last['id'] as int;
        if (!visited.add(next)) break;
        before = next;
      }
      for (final item in _buffer) {
        _consume(item);
      }
      _buffer.clear();
      if (_futureSchema) {
        throw StateError(
          'Unsupported workspace schema. Update WhatsGram before synchronizing.',
        );
      }
      for (final event in pending) {
        register.apply(event);
      }
      if (!_disconnected) await _save();
    } catch (e) {
      if (register.clock > old.clock) old.clock = register.clock;
      register = old;
      for (final event in pending) {
        register.apply(event);
      }
      verified = false;
      error = '$e';
    } finally {
      syncing = false;
      if (!_disconnected) {
        notifyListeners();
        if (verified) unawaited(flush());
      }
    }
  }

  Future<void> select(SelectionTarget target, bool selected) async {
    if (_futureSchema) {
      throw StateError('Update WhatsGram before changing this workspace.');
    }
    if (genesis == null || _disconnected) {
      throw StateError('Join a workspace first');
    }
    if (target.kind != 'participant_pair' &&
        target.identity == controlSupergroup) {
      throw StateError('The settings group cannot be selected');
    }
    final event = WorkspaceEvent(
      workspaceId: genesis!.workspaceId,
      eventId: const Uuid().v4(),
      actor: self,
      device: device,
      lamport: '${register.clock + BigInt.one}',
      target: target,
      selected: selected,
    );
    WorkspaceEvent.parse(event.toJson(), genesis!, self);
    pending.add(event);
    register.apply(event);
    await _save();
    notifyListeners();
    if (verified) await flush();
  }

  Future<void> flush() async {
    if (_flushing || !verified || _disconnected) return;
    _flushing = true;
    try {
      for (final event in [...pending]) {
        if (_disconnected || !verified) break;
        final result = await _sendRecord(event.toJson());
        _consume(await _confirm(result));
        await _save();
        notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 750));
      }
    } catch (e) {
      error = 'Selection synchronization pending: $e';
      notifyListeners();
    } finally {
      _flushing = false;
    }
  }

  Future<Json> _sendRecord(Json value) => client.call('sendMessage', {
    'chat_id': controlChat,
    'input_message_content': {
      '@type': 'inputMessageText',
      'text': {
        '@type': 'formattedText',
        'text': jsonEncode(value),
        'entities': <Json>[],
      },
    },
  });
  Future<Json> _confirm(Json message) async {
    if (message['sending_state'] == null) return message;
    // The persistent listener caches results arriving before sendMessage returns.
    final initial = message['id'];
    final cached = _sendResults.remove(initial);
    final match = cached == null
        ? client.updates
              .firstWhere(
                (u) =>
                    u['old_message_id'] == initial &&
                    u['message']?['chat_id'] == controlChat,
              )
              .timeout(const Duration(seconds: 35))
        : Future<Json>.value(cached);
    final event = await match;
    if (event['@type'] == 'updateMessageSendFailed') {
      throw const TdException(
        0,
        'Settings message failed. Retry will reuse its event ID.',
      );
    }
    return Map<String, dynamic>.from(event['message']);
  }

  Future<void> disconnect() async {
    _disconnected = true;
    _retry?.cancel();
    _retry = null;
    await _subscription?.cancel();
    _subscription = null;
    await _persistence.catchError((Object _) {});
    pending.clear();
    genesis = null;
    verified = false;
    register = SelectionRegister();
    await store.delete(_key);
    notifyListeners();
  }

  @override
  void dispose() {
    _disconnected = true;
    _retry?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
