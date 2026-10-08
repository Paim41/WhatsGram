import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsgram/features/media/export_manager.dart';

void main() {
  test('automatic exports are off by default and respect all media gates', () {
    final preferences = ExportPreferences();
    final message = <String, dynamic>{
      'can_be_saved': true,
      'is_outgoing': false,
      'content': {'@type': 'messagePhoto'},
    };
    final file = <String, dynamic>{'size': 100};
    expect(preferences.allows(message, file), false);
    preferences.enabled = true;
    preferences.destination = 'chosen-folder';
    expect(preferences.allows(message, file), true);
    expect(
      preferences.allows({...message, 'self_destruct_type': {}}, file),
      false,
    );
    expect(
      preferences.allows({...message, 'can_be_saved': false}, file),
      false,
    );
    expect(preferences.allows({...message, 'is_outgoing': true}, file), false);
    expect(
      preferences.allows(message, {'size': preferences.maximumBytes + 1}),
      false,
    );
    expect(
      preferences.allows({
        ...message,
        'content': {'@type': 'messageDocument'},
      }, file),
      false,
    );
  });
  test(
    'crash recovery deduplicates exact bytes, not merely equal file sizes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'whatsgram-export-test-',
      );
      try {
        final source = await File(
          '${directory.path}/source',
        ).writeAsBytes([1, 2, 3]);
        final same = await File(
          '${directory.path}/same',
        ).writeAsBytes([1, 2, 3]);
        final other = await File(
          '${directory.path}/other',
        ).writeAsBytes([3, 2, 1]);
        expect(await identicalExport(source, same), true);
        expect(await identicalExport(source, other), false);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
