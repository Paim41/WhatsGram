import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Protected platform storage holds local state as well as encryption keys.
/// Each account is scoped by Telegram's user ID after authorization.
class LocalStore {
  const LocalStore([this.storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage storage;
  Future<String> databaseKey(String slot) async {
    final key = 'tdlib.database.key.$slot';
    final existing = await storage.read(key: key);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final value = base64Encode(List.generate(32, (_) => random.nextInt(256)));
    await storage.write(key: key, value: value);
    return value;
  }

  Future<Map<String, dynamic>> read(String key) async {
    final data = await storage.read(key: key);
    return data == null ? {} : jsonDecode(data) as Map<String, dynamic>;
  }

  Future<void> write(String key, Map<String, dynamic> value) =>
      storage.write(key: key, value: jsonEncode(value));
  Future<void> delete(String key) => storage.delete(key: key);
}
