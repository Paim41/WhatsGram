import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../core/storage/local_store.dart';
import '../../telegram/client/td_client.dart';
import '../../telegram/repositories/telegram_repository.dart';
import 'media_service.dart';

class ExportPreferences {
  bool enabled = false, unmeteredOnly = true;
  String destination = '';
  int maximumBytes = 20 * 1024 * 1024;
  int retentionDays = 30;
  final categories = <String>{'photo'};
  Json toJson() => {
    'enabled': enabled,
    'unmeteredOnly': unmeteredOnly,
    'destination': destination,
    'maximumBytes': maximumBytes,
    'retentionDays': retentionDays,
    'categories': categories.toList(),
  };
  void restore(Json json) {
    enabled = json['enabled'] as bool? ?? false;
    unmeteredOnly = json['unmeteredOnly'] as bool? ?? true;
    destination = json['destination'] as String? ?? '';
    maximumBytes = json['maximumBytes'] as int? ?? maximumBytes;
    retentionDays = json['retentionDays'] as int? ?? 30;
    if (json['categories'] is List) {
      categories
        ..clear()
        ..addAll(List<String>.from(json['categories']));
    }
  }

  String? category(Json message) => switch (message['content']?['@type']) {
    'messagePhoto' => 'photo',
    'messageVideo' => 'video',
    'messageDocument' => 'document',
    'messageVoiceNote' || 'messageAudio' => 'audio',
    _ => null,
  };
  bool allows(Json message, Json file) =>
      enabled &&
      destination.isNotEmpty &&
      message['is_outgoing'] != true &&
      message['can_be_saved'] == true &&
      message['self_destruct_type'] == null &&
      message['content']?['is_secret'] != true &&
      categories.contains(category(message)) &&
      (file['size'] as num? ?? 0) > 0 &&
      (file['size'] as num) <= maximumBytes;
}

Future<bool> identicalExport(File source, File destination) async {
  if (!await destination.exists() ||
      await source.length() != await destination.length()) {
    return false;
  }
  final a = await sha256.bind(source.openRead()).first;
  final b = await sha256.bind(destination.openRead()).first;
  return a == b;
}

class ExportManager {
  ExportManager(this.client, this.store, this.account);
  final TdClient client;
  final LocalStore store;
  final String account;
  final preferences = ExportPreferences();
  final completed = <String>{};
  final pending = <String, Json>{};
  static const channel = MethodChannel('whatsgram/storage');
  String? error;
  bool _working = false;
  String get key => 'account.$account.exports';
  Future<void> restore() async {
    final json = await store.read(key);
    preferences.restore(Map<String, dynamic>.from(json['preferences'] ?? {}));
    completed.addAll(List<String>.from(json['completed'] ?? []));
    pending.addAll(
      Map<String, Json>.from(
        (json['pending'] as Map? ?? {}).map(
          (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v)),
        ),
      ),
    );
  }

  Future<void> save() => store.write(key, {
    'preferences': preferences.toJson(),
    'completed': completed.toList(),
    'pending': pending,
  });
  Future<void> chooseDestination() async {
    final chosen = Platform.isAndroid
        ? await channel.invokeMethod<String>('chooseDirectory')
        : await getDirectoryPath(
            confirmButtonText: 'Use for automatic exports',
          );
    if (chosen != null) {
      preferences.destination = chosen;
      await save();
    }
  }

  Future<bool> networkAllowed() async {
    if (!preferences.unmeteredOnly) return true;
    if (!Platform.isAndroid) {
      return false; // Unknown cost never means unmetered.
    }
    return await channel.invokeMethod<bool>('networkUnmetered') ?? false;
  }

  Future<void> enqueue(Json message) async {
    final file = messageFile(message);
    if (file == null || !preferences.allows(message, file)) return;
    final identity = '${message['chat_id']}:${message['id']}';
    if (completed.contains(identity)) return;
    pending[identity] = {
      'chat_id': message['chat_id'],
      'message_id': message['id'],
    };
    await save();
  }

  Future<void> flush(Future<bool> Function(Json) isSelected) async {
    if (_working || !preferences.enabled || !await networkAllowed()) return;
    _working = true;
    try {
      for (final entry in [...pending.entries]) {
        final message = await client.call('getMessage', entry.value);
        final file = messageFile(message);
        if (file == null ||
            !preferences.allows(message, file) ||
            !await isSelected(message)) {
          pending.remove(entry.key);
          await save();
          continue;
        }
        final properties = await client.call(
          'getMessageProperties',
          entry.value,
        );
        if (properties['can_be_saved'] != true) {
          pending.remove(entry.key);
          await save();
          continue;
        }
        final source = await MediaService(client).download(file);
        // Recheck selection after a potentially long download.
        if (!preferences.enabled || !await isSelected(message)) continue;
        final rawName =
            message['content']?['document']?['file_name'] as String? ??
            p.basename(source);
        final name = safeFilename(
          '${message['chat_id']}_${message['id']}_$rawName',
        );
        if (Platform.isAndroid) {
          await channel.invokeMethod<void>('exportToDirectory', {
            'source': source,
            'directory': preferences.destination,
            'name': name,
          });
        } else {
          final root = Directory(preferences.destination);
          if (!await root.exists()) {
            throw StateError(
              'Export destination is unavailable. Choose a folder again.',
            );
          }
          final destination = File(p.join(root.path, name));
          // The deterministic filename makes recovery after a crash idempotent.
          if (await destination.exists()) {
            if (!await identicalExport(File(source), destination)) {
              throw StateError(
                'Export filename already exists with different contents.',
              );
            }
          } else {
            final partial = File('${destination.path}.partial');
            try {
              await File(source).copy(partial.path);
              await partial.rename(destination.path);
            } catch (_) {
              if (await partial.exists()) await partial.delete();
              rethrow;
            }
          }
        }
        completed.add(entry.key);
        pending.remove(entry.key);
        error = null;
        await save();
      }
    } catch (e) {
      error = 'Automatic export pending: $e';
    } finally {
      _working = false;
    }
  }
}
