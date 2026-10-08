import 'dart:convert';
import '../../telegram/client/td_client.dart';

const protocolMarker = 'whatsgram.workspace';
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _id = RegExp(r'^[1-9][0-9]{0,15}$');
bool validId(Object? value) =>
    value is String &&
    _id.hasMatch(value) &&
    BigInt.parse(value) <= BigInt.from(9007199254740991);
bool validUuid(Object? value) => value is String && _uuid.hasMatch(value);

class SelectionTarget {
  const SelectionTarget(this.kind, this.identity, [this.topic]);
  final String kind;
  final String identity;
  final String? topic;
  String get key => '$kind:$identity:${topic ?? ''}';
  Json toJson() => kind == 'participant_pair'
      ? {'kind': kind, 'user_ids': identity.split(',')}
      : {
          'kind': kind,
          'supergroup_id': identity,
          if (topic != null) 'topic_id': topic,
        };
  static SelectionTarget parse(Json json, List<String> participants) {
    final kind = json['kind'];
    if (kind == 'participant_pair') {
      final ids = json['user_ids'];
      if (json.length != 2 ||
          ids is! List ||
          ids.length != 2 ||
          !ids.every(validId)) {
        throw const FormatException('Invalid participant pair');
      }
      final canonical = List<String>.from(ids)..sort(compareDecimal);
      final trusted = [...participants]..sort(compareDecimal);
      if (canonical.join(',') != trusted.join(',')) {
        throw const FormatException(
          'Private conversation is not the participant pair',
        );
      }
      return SelectionTarget(kind, canonical.join(','));
    }
    if (kind != 'supergroup' && kind != 'forum_topic') {
      throw const FormatException('Unsupported selection');
    }
    if (!validId(json['supergroup_id'])) {
      throw const FormatException('Invalid supergroup ID');
    }
    if (kind == 'forum_topic' &&
        (!validId(json['topic_id']) ||
            int.parse(json['topic_id']) > 2147483647)) {
      throw const FormatException('Invalid forum topic ID');
    }
    if (json.length != (kind == 'forum_topic' ? 3 : 2)) {
      throw const FormatException('Unknown target fields');
    }
    return SelectionTarget(kind, json['supergroup_id'], json['topic_id']);
  }
}

int compareDecimal(String a, String b) =>
    BigInt.parse(a).compareTo(BigInt.parse(b));

class Genesis {
  const Genesis({
    required this.workspaceId,
    required this.owner,
    required this.participants,
  });
  final String workspaceId;
  final String owner;
  final List<String> participants;
  Json toJson() => {
    'protocol': protocolMarker,
    'schema_version': 1,
    'operation': 'genesis',
    'workspace_id': workspaceId,
    'owner_user_id': owner,
    'participants': participants,
  };
  static Genesis parse(Json json, String sender) {
    if (json.length != 6 ||
        json['protocol'] != protocolMarker ||
        json['schema_version'] != 1 ||
        json['operation'] != 'genesis' ||
        !validUuid(json['workspace_id']) ||
        !validId(json['owner_user_id'])) {
      throw const FormatException('Invalid or unsupported workspace genesis');
    }
    final people = json['participants'];
    if (people is! List ||
        people.length != 2 ||
        !people.every(validId) ||
        people[0] == people[1] ||
        !people.contains(sender) ||
        json['owner_user_id'] != sender) {
      throw const FormatException('Untrusted workspace owner');
    }
    return Genesis(
      workspaceId: json['workspace_id'],
      owner: sender,
      participants: List<String>.from(people),
    );
  }
}

class WorkspaceEvent {
  const WorkspaceEvent({
    required this.workspaceId,
    required this.eventId,
    required this.actor,
    required this.device,
    required this.lamport,
    required this.target,
    required this.selected,
  });
  final String workspaceId, eventId, actor, device, lamport;
  final SelectionTarget target;
  final bool selected;
  Json toJson() => {
    'protocol': protocolMarker,
    'schema_version': 1,
    'workspace_id': workspaceId,
    'event_id': eventId,
    'actor_user_id': actor,
    'device_id': device,
    'lamport': lamport,
    'operation': 'set_selection',
    'target': target.toJson(),
    'selected': selected,
  };
  static WorkspaceEvent parse(Json json, Genesis genesis, String sender) {
    if (json.length != 10 ||
        json['protocol'] != protocolMarker ||
        json['schema_version'] != 1 ||
        json['operation'] != 'set_selection' ||
        json['workspace_id'] != genesis.workspaceId ||
        !validUuid(json['event_id']) ||
        !validUuid(json['device_id']) ||
        json['actor_user_id'] != sender ||
        !genesis.participants.contains(sender) ||
        json['selected'] is! bool ||
        json['lamport'] is! String ||
        !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(json['lamport']) ||
        json['target'] is! Map) {
      throw const FormatException('Invalid or unauthorized event');
    }
    return WorkspaceEvent(
      workspaceId: genesis.workspaceId,
      eventId: json['event_id'],
      actor: sender,
      device: json['device_id'],
      lamport: json['lamport'],
      target: SelectionTarget.parse(
        Map<String, dynamic>.from(json['target']),
        genesis.participants,
      ),
      selected: json['selected'],
    );
  }

  int compareTo(WorkspaceEvent other) {
    var order = compareDecimal(lamport, other.lamport);
    if (order != 0) return order;
    order = compareDecimal(actor, other.actor);
    if (order != 0) return order;
    order = device.compareTo(other.device);
    return order != 0 ? order : eventId.compareTo(other.eventId);
  }
}

class SelectionRegister {
  final records = <String, WorkspaceEvent>{};
  final seen = <String, String>{};
  BigInt clock = BigInt.zero;
  void apply(WorkspaceEvent event) {
    final counter = BigInt.parse(event.lamport);
    if (counter > clock) clock = counter;
    // Reject conflicting reuse of a UUID instead of accepting altered retries.
    final encoded = jsonEncode(event.toJson());
    if (seen.containsKey(event.eventId)) {
      if (seen[event.eventId] != encoded) {
        throw const FormatException('Conflicting event UUID');
      }
      return;
    }
    seen[event.eventId] = encoded;
    final previous = records[event.target.key];
    if (previous == null || event.compareTo(previous) > 0) {
      records[event.target.key] = event;
    }
  }

  bool includes(SelectionTarget target) {
    if (target.kind == 'forum_topic' &&
        records[SelectionTarget('supergroup', target.identity).key]?.selected ==
            true) {
      return true;
    }
    return records[target.key]?.selected == true;
  }
}

/// Telegram metadata, not JSON claims, establishes the sender identity.
Json? recordFromMessage(Json message) {
  if (message['forward_info'] != null ||
      message['import_info'] != null ||
      message['sender_id']?['@type'] != 'messageSenderUser' ||
      message['content']?['@type'] != 'messageText') {
    return null;
  }
  final text = message['content']['text']['text'];
  if (text is! String || utf8.encode(text).length > 8192) return null;
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> &&
            decoded['protocol'] == protocolMarker
        ? decoded
        : null;
  } on FormatException {
    return null;
  }
}
