import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:whatsgram/telegram/native/td_native.dart';

Future<void> main() async {
  // No API credentials, authorization request or Telegram session is used.
  for (var cycle = 0; cycle < 2; cycle++) {
    final client = await NativeTdClient.start(
      libraryPath: p.absolute('native/windows/tdjson.dll'),
    );
    try {
      final state = await client.call('getAuthorizationState');
      if (state['@type'] != 'authorizationStateWaitTdlibParameters') {
        throw StateError('Unexpected initial TDLib authorization state');
      }
      final parsed = await client.call('parseTextEntities', {
        'text': '**native bridge**',
        'parse_mode': {'@type': 'textParseModeMarkdown', 'version': 2},
      });
      if (parsed['@type'] != 'formattedText') {
        throw StateError('Native request correlation failed');
      }
      stdout.writeln(
        'Native TDLib $supportedTdVersion cycle ${cycle + 1}: version, requests, authorization state and shutdown verified.',
      );
    } finally {
      await client.close();
    }
  }
}
