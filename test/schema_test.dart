import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all literal Telegram request names exist in the pinned schema', () {
    final schema = File('native/schema/td_api.tl').readAsStringSync();
    final functions = schema.split('---functions---').last;
    final methods = RegExp(
      r'^([A-Za-z][A-Za-z0-9]*)[ =]',
      multiLine: true,
    ).allMatches(functions).map((m) => m.group(1)).toSet();
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final calls = RegExp(
        r"\.call\(\s*'([^']+)'",
      ).allMatches(file.readAsStringSync());
      for (final call in calls) {
        expect(
          methods,
          contains(call.group(1)),
          reason: '${file.path}: ${call.group(1)} is not a pinned TDLib method',
        );
      }
    }
    expect(
      schema,
      contains('getForumTopicHistory chat_id:int53 forum_topic_id:int32'),
    );
    expect(schema, contains('sendMessage chat_id:int53 topic_id:MessageTopic'));
    expect(schema, contains('inputMessageVoiceNote voice_note:inputVoiceNote'));
  });
}
