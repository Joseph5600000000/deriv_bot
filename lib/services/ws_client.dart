import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../core/constants.dart';
import '../core/errors.dart';

/// Reconnecting WebSocket with heartbeat, timeout detection and exponential backoff.
/// A fresh URL (new OTP for trading sockets) is requested on every (re)connect.
class WsClient {
  WsClient({required this.urlProvider, required this.onMessage, required this.onState, required this.onOpen, required this.onError});
  final Future<String> Function() urlProvider;
  final void Function(String) onMessage;
  final void Function(int connState) onState;
  final Future<void> Function() onOpen;
  final void Function(Object) onError;

  WebSocket? _ws;
  bool _stopped = false;
  int _lastRxMs = 0;
  Timer? _hb;
  final Random _rng = Random();

  bool get isOpen => _ws != null && _ws!.readyState == WebSocket.open;
  void start() { _stopped = false; _loop(); }

  Future<void> stop() async {
    _stopped = true;
    _hb?.cancel();
    try { await _ws?.close(); } catch (_) {}
    _ws = null;
  }

  void forceReconnect() { try { _ws?.close(); } catch (_) {} }

  bool send(String s) {
    final w = _ws;
    if (w == null || w.readyState != WebSocket.open) return false;
    try { w.add(s); return true; } catch (_) { return false; }
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> _loop() async {
    int attempt = 0;
    while (!_stopped) {
      if (!_stopped) onState(Conn.reconnecting);
      try {
        final url = await urlProvider();
        if (_stopped) break;
        final ws = await WebSocket.connect(url).timeout(const Duration(seconds: 12));
        if (_stopped) { await ws.close(); break; }
        _ws = ws; _lastRxMs = _now(); attempt = 0;
        onState(Conn.connected);
        _hb?.cancel();
        _hb = Timer.periodic(const Duration(seconds: 10), (_) {
          if (_now() - _lastRxMs > 25000) { onError(DerivException(Err.wsTimeout, 'No data for 25s')); forceReconnect(); }
          else { send('{"ping":1}'); }
        });
        await onOpen();
        await for (final data in ws) {
          _lastRxMs = _now();
          if (data is String) onMessage(data);
        }
      } on DerivException catch (e) {
        onError(e);
        if (!e.retryable) { if (!_stopped) onState(Conn.error); _stopped = true; break; }
      } catch (e) {
        onError(DerivException(Err.wsDisconnected, '${e.runtimeType}', retryable: true));
      }
      _hb?.cancel(); _ws = null;
      if (_stopped) break;
      onState(Conn.disconnected);
      final ms = min(15000, 500 * (1 << min(attempt, 5))) + _rng.nextInt(300);
      await Future.delayed(Duration(milliseconds: ms));
      attempt++;
    }
  }
}
