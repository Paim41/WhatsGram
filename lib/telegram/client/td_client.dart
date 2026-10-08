import 'dart:async';

typedef Json = Map<String, dynamic>;

abstract interface class TdClient {
  Stream<Json> get updates;
  Future<Json> call(String method, [Json parameters = const {}]);
  Future<void> close();
}

class TdException implements Exception {
  const TdException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => code == 429
      ? 'Telegram rate limit. Please wait before retrying. $message'
      : 'Telegram ($code): $message';
}

/// Correlation is independent of native transport so ordering and lifecycle can
/// be exercised without an account or network connection.
class RequestBroker {
  RequestBroker(this.send, {this.timeout = const Duration(seconds: 30)});
  final void Function(Json) send;
  final Duration timeout;
  final _pending = <String, Completer<Json>>{};
  final _timers = <String, Timer>{};
  final _updates = StreamController<Json>.broadcast(sync: true);
  int _sequence = 0;
  bool _closed = false;
  Stream<Json> get updates => _updates.stream;

  Future<Json> call(String method, Json parameters) {
    if (_closed) return Future.error(StateError('TDLib client is closed'));
    final id = '${++_sequence}';
    final completer = Completer<Json>();
    _pending[id] = completer;
    _timers[id] = Timer(timeout, () {
      _timers.remove(id);
      _pending.remove(id)?.completeError(TimeoutException('$method timed out'));
    });
    try {
      send({...parameters, '@type': method, '@extra': id});
    } catch (error, stack) {
      _timers.remove(id)?.cancel();
      _pending.remove(id)?.completeError(error, stack);
    }
    return completer.future;
  }

  void accept(Json event) {
    if (_closed) return;
    final id = event['@extra']?.toString();
    if (id != null) {
      _timers.remove(id)?.cancel();
      final request = _pending.remove(id);
      if (request == null) {
        return; // Late response to a cancelled/timed-out call.
      }
      if (event['@type'] == 'error') {
        request.completeError(
          TdException(event['code'] as int, event['message'] as String),
        );
      } else {
        request.complete(event);
      }
    } else {
      _updates.add(event);
    }
  }

  void cancelPending([Object? reason]) {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    for (final request in _pending.values) {
      request.completeError(reason ?? StateError('TDLib operation cancelled'));
    }
    _pending.clear();
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    cancelPending();
    await _updates.close();
  }
}
