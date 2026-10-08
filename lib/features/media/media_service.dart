import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../telegram/client/td_client.dart';

String safeFilename(String input) {
  var name = input
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty ||
      RegExp(
        r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
        caseSensitive: false,
      ).hasMatch(name)) {
    name = 'file_$name';
  }
  if (name.length > 180) name = name.substring(0, 180);
  return name;
}

class MediaService {
  const MediaService(this.client);
  final TdClient client;
  Future<String> download(Json file) async {
    final result = await client.call('downloadFile', {
      'file_id': file['id'],
      'priority': 16,
      'offset': 0,
      'limit': 0,
      'synchronous': true,
    });
    final local = result['local'] as Json;
    if (local['is_downloading_completed'] != true ||
        !await File(local['path']).exists()) {
      throw StateError(
        'File is not available yet. Retry when the transfer completes.',
      );
    }
    return local['path'] as String;
  }

  Future<void> save(String source, String filename) async {
    if (!await File(source).exists()) {
      throw StateError('Cached file is missing. Download it again.');
    }
    final name = safeFilename(filename);
    if (Platform.isAndroid) {
      await const MethodChannel(
        'whatsgram/storage',
      ).invokeMethod<void>('saveFile', {'source': source, 'name': name});
    } else {
      final destination = await getSaveLocation(suggestedName: name);
      if (destination == null) return;
      if (p.equals(source, destination.path) ||
          await File(destination.path).exists()) {
        throw StateError(
          'Choose a new filename; WhatsGram does not silently overwrite files.',
        );
      }
      final partial = '${destination.path}.whatsgram-part';
      if (await File(partial).exists()) {
        throw StateError(
          'A partial export already exists. Choose another name.',
        );
      }
      try {
        await File(source).copy(partial);
        await File(partial).rename(destination.path);
      } catch (_) {
        if (await File(partial).exists()) await File(partial).delete();
        rethrow;
      }
    }
  }
}
