import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// An allowlisted event log; never accepts message bodies, request parameters,
/// paths, peer identifiers or exception strings.
class Diagnostics {
  final entries = <Map<String, Object>>[];
  void record(String event, {int? code}) {
    const allowed = {
      'startup',
      'native_ready',
      'native_error',
      'authorization_ready',
      'authorization_closed',
      'connection_ready',
      'connection_lost',
      'notification_error',
      'workspace_error',
    };
    if (!allowed.contains(event)) return;
    entries.add({
      'time': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      'code': ?code,
    });
    if (entries.length > 200) entries.removeAt(0);
  }

  Future<String> export() async {
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, 'whatsgram-diagnostics.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'app': 'WhatsGram',
        'version': '0.1.0',
        'tdlib': '1.8.67',
        'platform': Platform.operatingSystem,
        'events': entries,
      }),
      flush: true,
    );
    return file.path;
  }
}
