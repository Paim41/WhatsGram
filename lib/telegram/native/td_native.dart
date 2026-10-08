import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import '../client/td_client.dart';

const supportedTdVersion = '1.8.67';

class NativeTdClient implements TdClient {
  NativeTdClient._();
  late final RequestBroker _broker;
  final _inbox = ReceivePort();
  final _errors = ReceivePort();
  final _exit = ReceivePort();
  late Isolate _worker;
  late SendPort _commands;
  final _stopped = Completer<void>();
  bool _closing = false;

  static Future<NativeTdClient> start({String? libraryPath}) async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      throw UnsupportedError('WhatsGram supports Android and Windows only.');
    }
    final client = NativeTdClient._();
    final ready = Completer<void>();
    client._broker = RequestBroker((json) => client._commands.send(json));
    client._inbox.listen((value) {
      if (value is SendPort) {
        client._commands = value;
        ready.complete();
      } else if (value is Map) {
        final json = Map<String, dynamic>.from(value);
        if (json.containsKey('startup_error')) {
          if (!ready.isCompleted) {
            ready.completeError(StateError(json['startup_error']));
          }
        } else {
          client._broker.accept(json);
        }
      }
    });
    client._errors.listen((_) {
      final error = StateError(
        'TDLib worker stopped unexpectedly. Restart WhatsGram.',
      );
      if (!ready.isCompleted) ready.completeError(error);
      client._broker.cancelPending(error);
    });
    client._exit.listen((_) {
      if (!client._stopped.isCompleted) client._stopped.complete();
      client._broker.cancelPending(StateError('TDLib worker exited'));
    });
    final library =
        libraryPath ??
        (Platform.isWindows
            ? p.join(p.dirname(Platform.resolvedExecutable), 'tdjson.dll')
            : 'libtdjson.so');
    client._worker = await Isolate.spawn(
      _run,
      [client._inbox.sendPort, library],
      onError: client._errors.sendPort,
      onExit: client._exit.sendPort,
    );
    try {
      await ready.future.timeout(const Duration(seconds: 15));
      final version = await client.call('getOption', {'name': 'version'});
      if (version['value'] != supportedTdVersion) {
        throw StateError(
          'TDLib ${version['value']} is incompatible. Build the pinned $supportedTdVersion library.',
        );
      }
      return client;
    } catch (_) {
      await client.close();
      rethrow;
    }
  }

  @override
  Stream<Json> get updates => _broker.updates;
  @override
  Future<Json> call(String method, [Json parameters = const {}]) =>
      _broker.call(method, parameters);

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    try {
      await call('close').timeout(const Duration(seconds: 3));
      await _stopped.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      _worker.kill(priority: Isolate.immediate);
    }
    await _broker.dispose();
    _inbox.close();
    _errors.close();
    _exit.close();
  }
}

void _run(List<Object> arguments) {
  final parent = arguments[0] as SendPort;
  final path = arguments[1] as String;
  DynamicLibrary library;
  try {
    library = DynamicLibrary.open(path);
  } catch (_) {
    parent.send({
      'startup_error':
          'Cannot load $path. Build/package TDLib 1.8.67 and its OpenSSL/zlib runtime dependencies for ${Abi.current()}. See docs/BUILD_WINDOWS.md or docs/BUILD_ANDROID.md.',
    });
    return;
  }
  final create = library.lookupFunction<Int32 Function(), int Function()>(
    'td_create_client_id',
  );
  final send = library
      .lookupFunction<
        Void Function(Int32, Pointer<Utf8>),
        void Function(int, Pointer<Utf8>)
      >('td_send');
  final receive = library
      .lookupFunction<
        Pointer<Utf8> Function(Double),
        Pointer<Utf8> Function(double)
      >('td_receive');
  final execute = library
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)
      >('td_execute');
  final log = jsonEncode({
    '@type': 'setLogVerbosityLevel',
    'new_verbosity_level': 0,
  }).toNativeUtf8();
  try {
    execute(log);
  } finally {
    malloc.free(log);
  }
  final id = create();
  final commands = ReceivePort();
  parent.send(commands.sendPort);
  commands.listen((value) {
    final native = jsonEncode(value).toNativeUtf8();
    try {
      send(id, native);
    } finally {
      malloc.free(native);
    }
  });
  // A single receive loop owns all TDLib strings and copies them before the next
  // call. Blocking waits occur in this isolate, never Flutter's UI isolate.
  Timer.periodic(const Duration(milliseconds: 10), (timer) {
    for (var count = 0; count < 100; count++) {
      final pointer = receive(count == 0 ? 0.02 : 0);
      if (pointer == nullptr) break;
      final event = jsonDecode(pointer.toDartString()) as Json;
      if (event['@client_id'] != null && event['@client_id'] != id) continue;
      parent.send(event);
      if (event['@type'] == 'updateAuthorizationState' &&
          event['authorization_state']['@type'] == 'authorizationStateClosed') {
        timer.cancel();
        commands.close();
        return;
      }
    }
  });
}
