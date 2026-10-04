import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../models/strategy_config.dart';
import 'tc_structs.dart';

class TickOut {
  final int action, errorCode, tradeId, digit, direction, barrier;
  final double stake;
  final String? payload;
  TickOut(this.action, this.errorCode, this.tradeId, this.digit, this.direction, this.barrier, this.stake, this.payload);
}

/// Thin, allocation-light wrapper over the C ABI. All trading decisions live in C++.
class CoreEngine {
  static const int _payloadCap = 1024, _snapCap = 8192;
  late final DynamicLibrary _lib;
  late final Pointer<Void> _h;
  final Pointer<TcState> _state = calloc<TcState>();
  final Pointer<TcConfig> _cfg = calloc<TcConfig>();
  final Pointer<TcTickResult> _res = calloc<TcTickResult>();
  final Pointer<TcRecord> _rec = calloc<TcRecord>();
  final Pointer<Utf8> _payload = calloc<Uint8>(_payloadCap).cast<Utf8>();
  final Pointer<Uint8> _snap = calloc<Uint8>(_snapCap);

  late final int Function() nowUs;
  late final int Function(Pointer<Void>, Pointer<TcConfig>) _configure;
  late final int Function(Pointer<Void>, int) _command;
  late final void Function(Pointer<Void>, int, int) _setConn;
  late final int Function(Pointer<Void>, Pointer<Utf8>, int, Pointer<Utf8>) _setAccount;
  late final int Function(Pointer<Void>, Pointer<Utf8>, double, Pointer<Utf8>) _onBalance;
  late final void Function(Pointer<Void>, int, double, int, int, Pointer<TcTickResult>, Pointer<Utf8>, int) _tick;
  late final int Function(Pointer<Void>, int, int, int, double, int, int) _buyResult;
  late final int Function(Pointer<Void>, int, int, double, int) _contractUpdate;
  late final int Function(Pointer<Void>, int) _execTimeout;
  late final int Function(Pointer<Void>, int, int, int, int, double, int) _reconcile;
  late final void Function(Pointer<Void>, int) _reportError;
  late final void Function(Pointer<Void>, Pointer<TcState>) _getState;
  late final int Function(Pointer<Void>, Pointer<TcRecord>) _lastRecord;
  late final int Function(Pointer<Void>, Pointer<Uint8>, int) _serialize;
  late final int Function(Pointer<Void>, Pointer<Uint8>, int, int) _restore;
  late final void Function(Pointer<Void>) _destroy;

  CoreEngine.open() {
    final name = Platform.isAndroid ? 'libtradingcore.so' : (Platform.environment['TC_LIB'] ?? 'libtradingcore.so');
    _lib = DynamicLibrary.open(name);
    final create = _lib.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('engine_create');
    _destroy = _lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('engine_destroy');
    nowUs = _lib.lookupFunction<Int64 Function(), int Function()>('engine_now_us');
    final sizes = _lib.lookupFunction<Int32 Function(Pointer<Int64>), int Function(Pointer<Int64>)>('engine_abi_sizes');
    _configure = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<TcConfig>), int Function(Pointer<Void>, Pointer<TcConfig>)>('engine_configure');
    _command = _lib.lookupFunction<Int32 Function(Pointer<Void>, Int32), int Function(Pointer<Void>, int)>('engine_command');
    _setConn = _lib.lookupFunction<Void Function(Pointer<Void>, Int32, Int32), void Function(Pointer<Void>, int, int)>('engine_set_conn');
    _setAccount = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32, Pointer<Utf8>), int Function(Pointer<Void>, Pointer<Utf8>, int, Pointer<Utf8>)>('engine_set_account');
    _onBalance = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>, Double, Pointer<Utf8>), int Function(Pointer<Void>, Pointer<Utf8>, double, Pointer<Utf8>)>('engine_on_balance');
    _tick = _lib.lookupFunction<Void Function(Pointer<Void>, Int64, Double, Int32, Int64, Pointer<TcTickResult>, Pointer<Utf8>, Int32), void Function(Pointer<Void>, int, double, int, int, Pointer<TcTickResult>, Pointer<Utf8>, int)>('engine_process_tick');
    _buyResult = _lib.lookupFunction<Int32 Function(Pointer<Void>, Int64, Int32, Int64, Double, Int32, Int64), int Function(Pointer<Void>, int, int, int, double, int, int)>('engine_on_buy_result');
    _contractUpdate = _lib.lookupFunction<Int32 Function(Pointer<Void>, Int64, Int32, Double, Int64), int Function(Pointer<Void>, int, int, double, int)>('engine_on_contract_update');
    _execTimeout = _lib.lookupFunction<Int32 Function(Pointer<Void>, Int64), int Function(Pointer<Void>, int)>('engine_on_exec_timeout');
    _reconcile = _lib.lookupFunction<Int32 Function(Pointer<Void>, Int64, Int32, Int64, Int32, Double, Int64), int Function(Pointer<Void>, int, int, int, int, double, int)>('engine_reconcile');
    _reportError = _lib.lookupFunction<Void Function(Pointer<Void>, Int32), void Function(Pointer<Void>, int)>('engine_report_error');
    _getState = _lib.lookupFunction<Void Function(Pointer<Void>, Pointer<TcState>), void Function(Pointer<Void>, Pointer<TcState>)>('engine_get_state');
    _lastRecord = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<TcRecord>), int Function(Pointer<Void>, Pointer<TcRecord>)>('engine_get_last_record');
    _serialize = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32), int Function(Pointer<Void>, Pointer<Uint8>, int)>('engine_serialize');
    _restore = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32, Int32), int Function(Pointer<Void>, Pointer<Uint8>, int, int)>('engine_restore');

    final s = calloc<Int64>(4);
    sizes(s);
    final ok = s[0] == sizeOf<TcConfig>() && s[1] == sizeOf<TcState>() && s[2] == sizeOf<TcTickResult>() && s[3] == sizeOf<TcRecord>();
    calloc.free(s);
    if (!ok) throw StateError('FFI struct size mismatch between Dart and C++. Re-run tools/gen_structs.py and rebuild the native lib.');
    _h = create();
    if (_h == nullptr) throw StateError('engine_create failed');
  }

  int configure(StrategyConfig c) { c.writeTo(_cfg.ref); return _configure(_h, _cfg); }
  int command(int c) => _command(_h, c);
  void setConn(int kind, int st) => _setConn(_h, kind, st);

  int setAccount(String id, bool real, String currency) {
    final a = id.toNativeUtf8(), c = currency.toNativeUtf8();
    try { return _setAccount(_h, a, real ? 1 : 0, c); } finally { calloc.free(a); calloc.free(c); }
  }

  /// Returns 1 when [loginid] matched the selected account (identity verified).
  int onBalance(String? loginid, double bal, String? currency) {
    final l = loginid == null ? nullptr.cast<Utf8>() : loginid.toNativeUtf8();
    final c = currency == null ? nullptr.cast<Utf8>() : currency.toNativeUtf8();
    try { return _onBalance(_h, l, bal, c); } finally { if (loginid != null) calloc.free(l); if (currency != null) calloc.free(c); }
  }

  /// Hot path: no allocation except the (rare) payload string.
  TickOut processTick(int epoch, double quote, int pip, int rxUs) {
    _tick(_h, epoch, quote, pip, rxUs, _res, _payload, _payloadCap);
    final r = _res.ref;
    String? p;
    if (r.action == 1) p = _payload.toDartString(length: r.payload_len);
    return TickOut(r.action, r.error_code, r.trade_id, r.digit, r.direction, r.barrier, r.stake, p);
  }

  int onBuyResult(int tradeId, bool ok, int contractId, double price, int err, int ackUs) =>
      _buyResult(_h, tradeId, ok ? 1 : 0, contractId, price, err, ackUs);
  int onContractUpdate(int cid, int status, double profit, int nowUs) => _contractUpdate(_h, cid, status, profit, nowUs);
  int onExecTimeout(int tradeId) => _execTimeout(_h, tradeId);
  int reconcile(int tradeId, bool found, int cid, int status, double profit, int nowUs) =>
      _reconcile(_h, tradeId, found ? 1 : 0, cid, status, profit, nowUs);
  void reportError(int code) => _reportError(_h, code);

  TcState state() { _getState(_h, _state); return _state.ref; }
  Uint8List stateBytes() { _getState(_h, _state); return Uint8List.fromList(_state.cast<Uint8>().asTypedList(sizeOf<TcState>())); }

  Map<String, dynamic>? lastRecord() {
    if (_lastRecord(_h, _rec) != 1) return null;
    final r = _rec.ref;
    return {
      'trade_id': r.trade_id, 'tick_epoch': r.tick_epoch, 'market': r.market, 'real': r.account_real,
      'prev': r.prev_digit, 'cur': r.cur_digit, 'average': r.average, 'deviation': r.deviation,
      'dev_sign': r.deviation_sign, 'consecutive': r.consecutive_seq, 'trigger_digit': r.trigger_digit,
      'direction': r.direction, 'barrier': r.barrier, 'stake': r.stake, 'recovery': r.recovery_level,
      'martingale': r.martingale_level, 'result': r.result, 'profit': r.profit, 'contract_id': r.contract_id,
      'lat_tick_to_trigger_us': r.t_trigger_us - r.t_tick_rx_us, 'lat_trigger_to_send_us': r.t_request_us - r.t_trigger_us,
      'lat_send_to_ack_us': r.t_ack_us == 0 ? 0 : r.t_ack_us - r.t_request_us,
      'lat_ack_to_open_us': (r.t_open_us == 0 || r.t_ack_us == 0) ? 0 : r.t_open_us - r.t_ack_us,
    };
  }

  Uint8List? serialize() {
    final n = _serialize(_h, _snap, _snapCap);
    return n <= 0 ? null : Uint8List.fromList(_snap.asTypedList(n));
  }

  int restore(Uint8List b, {required bool resume}) {
    if (b.length > _snapCap) return 25;
    _snap.asTypedList(b.length).setAll(0, b);
    return _restore(_h, _snap, b.length, resume ? 1 : 0);
  }

  void dispose() { _destroy(_h); }
}

/// UI-side holder for a copy of the engine state (read-only mirror; never a source of truth).
class EngineSnap {
  final Pointer<TcState> _p = calloc<TcState>();
  TcState get s => _p.ref;
  /// Array indexing needs dart:ffi's extension in scope, so it lives here (this file imports it).
  List<int> recentDigits() { final r = _p.ref; return [for (int i = 0; i < 16; i++) r.recent[i]]; }
  void load(Uint8List b) {
    if (b.length != sizeOf<TcState>()) return;
    _p.cast<Uint8>().asTypedList(b.length).setAll(0, b);
  }
}
