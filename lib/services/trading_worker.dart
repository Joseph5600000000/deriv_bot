import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import '../core/constants.dart';
import '../core/errors.dart';
import '../ffi/engine_ffi.dart';
import '../models/strategy_config.dart';
import 'deriv_rest.dart';
import 'ws_client.dart';

/// Entry point of the background isolate. It owns BOTH sockets and the C++ engine so that UI work
/// can never delay a tick->trade decision. C++ decides; this isolate only moves bytes.
void tradingWorkerMain(SendPort ui) {
  final rp = ReceivePort();
  ui.send({'t': 'ready', 'port': rp.sendPort});
  final w = _Worker(ui);
  rp.listen((m) => w.handle(m as Map));
}

double _num(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);

class _Worker {
  _Worker(this.ui);
  final SendPort ui;
  late CoreEngine eng;
  late DerivRest rest;
  String _dir = '', _pat = '', _symbol = kSymbols[4];
  List<Account> _accounts = [];
  Account? _acct;
  WsClient? _pub, _trd;
  StrategyConfig? _cfg;
  int _pubState = Conn.disconnected, _lastTickUs = 0, _lastRecordSeq = 0, _sentEpoch = 0, _reconTid = 0;
  bool _tradeReady = false, _dirty = false, _persistDirty = false, _persisting = false, _ready = false;
  Timer? _uiTimer, _persistTimer, _staleTimer, _execTimer, _reconTimer;

  Future<void> handle(Map m) async {
    try {
      switch (m['t']) {
        case 'init': await _init(m); break;
        case 'login': rest = DerivRest((m['appId'] as String).trim()); await _login(m['pat'] as String); break;
        case 'select': await _select(m['id'] as String); break;
        case 'config': _config(m['cfg'] as Map); break;
        case 'cmd': _cmd(m['cmd'] as int); break;
        case 'logout': await _logout(); break;
        case 'clearHistory': await _clearHistory(); break;
      }
    } catch (e) {
      _event('error', Err.unknown, 'Internal error: ${e.runtimeType}');
    }
  }

  // ---------- lifecycle ----------
  Future<void> _init(Map m) async {
    if (_ready) return;
    eng = CoreEngine.open();
    rest = DerivRest(m['appId'] as String);
    _dir = m['dir'] as String;
    final snap = File('$_dir/engine_state.bin');
    if (await snap.exists()) {
      final rc = eng.restore(await snap.readAsBytes(), resume: m['resume'] == true);
      if (rc != 0) _event('warn', Err.badSnapshot, 'Saved state ignored (code $rc)');
    }
    final sj = File('$_dir/strategy.json');
    if (await sj.exists()) {
      try {
        _cfg = StrategyConfig.fromJson(jsonDecode(await sj.readAsString()) as Map);
        eng.configure(_cfg!);
        _symbol = kSymbols[_cfg!.market];
        ui.send({'t': 'cfg', 'cfg': _cfg!.toJson()});
      } catch (_) {}
    }
    _uiTimer = Timer.periodic(const Duration(milliseconds: 250), (_) { if (_dirty) { _dirty = false; _pushState(); } });
    _persistTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (_persistDirty) _persist(); });
    _staleTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkStale());
    _ready = true;
    _pushState();
    ui.send({'t': 'inited'});
  }

  Future<void> _login(String pat) async {
    try {
      final accts = await rest.accounts(pat);
      if (accts.isEmpty) throw DerivException(Err.accountNotFound, 'The token has no Options accounts');
      _pat = pat; _accounts = accts;
      ui.send({'t': 'loginResult', 'ok': true, 'accounts': accts.map((a) => a.toJson()).toList()});
      _ensurePublic();
      final demos = accts.where((a) => !a.isReal && a.active).toList();     // Demo-first (spec 42)
      if (demos.isNotEmpty) await _select(demos.first.id);
    } on DerivException catch (e) {
      ui.send({'t': 'loginResult', 'ok': false, 'code': e.code, 'technical': e.technical});
    }
  }

  /// Statistics only. Strategy, recovery, risk accumulators, config, account and any live trade are untouched.
  Future<void> _clearHistory() async {
    eng.command(Cmd.clearHistory);
    try { final f = File('$_dir/trades.jsonl'); if (await f.exists()) await f.delete(); } catch (_) {}
    _persistSoon(); _dirty = true;
    _event('info', Err.none, 'Trade history and statistics cleared.');
  }

  Future<void> _logout() async {
    eng.command(Cmd.pause);
    eng.setConn(1, Conn.disconnected);
    await _trd?.stop(); _trd = null; _tradeReady = false;
    _pat = ''; _acct = null; _accounts = [];
    _event('info', Err.none, 'Disconnected and credentials cleared from memory.');
    _dirty = true;
  }

  // ---------- public tick stream ----------
  void _ensurePublic() {
    if (_pub != null) return;
    late WsClient c;
    c = WsClient(
      urlProvider: () async => kPublicWs,
      onState: (s) { if (!identical(_pub, c)) return; _pubState = s; if (s != Conn.connected) eng.setConn(0, s); _dirty = true; },
      onOpen: () async {
        eng.setConn(0, Conn.synchronizing); _pubState = Conn.synchronizing; _lastTickUs = eng.nowUs();
        c.send(jsonEncode({'ticks': _symbol, 'subscribe': 1}));
      },
      onMessage: (raw) { if (identical(_pub, c)) _onPublic(raw); },
      onError: (e) => _event('warn', e is DerivException ? e.code : Err.network, '$e'),
    );
    _pub = c;
    c.start();
  }

  void _onPublic(String raw) {
    final rx = eng.nowUs();
    dynamic m;
    try { m = jsonDecode(raw); } catch (_) { _event('warn', Err.unknown, 'Malformed tick message dropped'); return; }
    if (m is! Map) return;
    if (m['msg_type'] != 'tick') {
      if (m['error'] != null) _event('error', Err.network, 'Tick stream: ${(m['error'] as Map)['message']}');
      return;
    }
    final t = m['tick'];
    if (t is! Map || t['symbol'] != _symbol || t['epoch'] == null || t['quote'] == null) return;
    _lastTickUs = rx;
    if (_pubState != Conn.ready) { _pubState = Conn.ready; eng.setConn(0, Conn.ready); }
    final r = eng.processTick((t['epoch'] as num).toInt(), (t['quote'] as num).toDouble(), (t['pip_size'] as num?)?.toInt() ?? 2, rx);
    if (r.action == 1 && r.payload != null) {
      _sendBuy(r.payload!, r.tradeId);                      // immediately, before any bookkeeping
    } else if (r.action == 3) {
      _event('info', Err.none, 'Trigger skipped by Loss-Deviation Filter (same deviation as last loss).');
    } else if (r.action == 2) {
      _event('warn', r.errorCode, 'Trigger blocked: ${errInfo(r.errorCode).name}');
    }
    _dirty = true; _persistDirty = true;
  }

  void _checkStale() {
    if (!_ready || _pub == null) return;
    final ageS = (eng.nowUs() - _lastTickUs) / 1e6;
    if (_pubState == Conn.ready && ageS > 20) {
      _pubState = Conn.degraded; eng.setConn(0, Conn.degraded);
      _event('warn', Err.staleTick, 'No tick for ${ageS.toStringAsFixed(0)}s - trading blocked');
      _dirty = true;
    }
    if ((_pubState == Conn.degraded || _pubState == Conn.synchronizing) && ageS > 45) { _lastTickUs = eng.nowUs(); _pub?.forceReconnect(); }
  }

  // ---------- trading socket ----------
  Future<void> _select(String id) async {
    Account? a;
    for (final x in _accounts) { if (x.id == id) a = x; }
    if (a == null) { _event('error', Err.accountNotFound, 'Unknown account $id'); return; }
    final st = eng.state();
    if (st.fsm_state == Fsm.executing || st.fsm_state == Fsm.open) {
      _event('warn', Err.busy, 'Cannot switch account while a trade is open.'); ui.send({'t': 'selectResult', 'ok': false}); return;
    }
    eng.setConn(1, Conn.disconnected);                      // 1. block execution on the previous account at once
    _tradeReady = false;
    await _trd?.stop(); _trd = null;
    if (eng.setAccount(a.id, a.isReal, a.currency) != 0) { _event('error', Err.busy, 'Engine refused account change'); return; }
    _acct = a;
    ui.send({'t': 'account', 'id': a.id, 'type': a.type, 'currency': a.currency});
    final acct = a;
    late WsClient c;
    c = WsClient(
      urlProvider: () async {
        final url = await rest.otpUrl(_pat, acct.id);       // 2. fresh OTP on every (re)connect
        final want = acct.isReal ? '/ws/real' : '/ws/demo';
        if (!url.contains(want)) throw DerivException(Err.accountMismatch, 'OTP URL does not match ${acct.type} account');
        return url;
      },
      onState: (s) {
        if (!identical(_trd, c)) return;
        if (s != Conn.connected) { _tradeReady = false; eng.setConn(1, s); }
        _dirty = true;
      },
      onOpen: () async {
        eng.setConn(1, Conn.synchronizing);
        c.send(jsonEncode({'balance': 1, 'subscribe': 1}));  // 3/4. identity + authoritative balance
      },
      onMessage: (raw) { if (identical(_trd, c)) _onTrade(raw); },
      onError: (e) { if (identical(_trd, c)) _event('warn', e is DerivException ? e.code : Err.network, '$e'); },
    );
    _trd = c;
    c.start();
    ui.send({'t': 'selectResult', 'ok': true});
  }

  void _onTrade(String raw) {
    final ts = eng.nowUs();
    dynamic m;
    try { m = jsonDecode(raw); } catch (_) { _event('warn', Err.unknown, 'Malformed message dropped'); return; }
    if (m is! Map) return;
    final err = m['error'];
    switch (m['msg_type']) {
      case 'ping': return;
      case 'balance': _onBalance(m, err); break;
      case 'buy': _onBuy(m, err, ts); break;
      case 'proposal_open_contract': _onPoc(m, ts); break;
      default:
        if (err is Map) _handleApiError('${m['msg_type']}', err);
    }
    _dirty = true;
  }

  void _handleApiError(String type, Map err) {
    final code = '${err['code']}';
    if (code == 'InvalidToken' || code == 'Unauthorized') {
      _event('error', Err.patInvalid, 'Session rejected ($type). Requesting a fresh OTP.');
      _tradeReady = false; eng.setConn(1, Conn.reconnecting); _trd?.forceReconnect();
    } else {
      _event('error', code == 'InsufficientBalance' ? Err.insufficientBalance : Err.tradeRejected, '$type: ${err['message']}');
    }
  }

  void _onBalance(Map m, dynamic err) {
    final b = m['balance'];
    if (err is Map || b is! Map) { if (err is Map) _handleApiError('balance', err); return; }
    final ok = eng.onBalance(b['loginid'] as String?, _num(b['balance']), b['currency'] as String?);
    if (ok == 1) {
      if (!_tradeReady) { _tradeReady = true; eng.setConn(1, Conn.ready); _afterTradeReady(); }
    } else {
      _event('error', Err.accountMismatch, 'Connected account does not match the selected account. Trading blocked.');
      _tradeReady = false; eng.setConn(1, Conn.error); _trd?.stop();
    }
  }

  void _sendBuy(String payload, int tid) {
    final ok = _trd?.send(payload) ?? false;
    _sentEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (!ok) {
      eng.onBuyResult(tid, false, 0, 0, Err.wsDisconnected, eng.nowUs());
      _event('error', Err.wsDisconnected, 'Buy not sent - connection down. No trade placed.');
      return;
    }
    _execTimer?.cancel();
    _execTimer = Timer(const Duration(seconds: 8), () {
      if (eng.onExecTimeout(tid) == 1) {
        _event('error', Err.executionTimeout, 'No buy confirmation - reconciling with Deriv.');
        if (_tradeReady) _startReconcile(tid);
        _dirty = true;
      }
    });
    _persistSoon();
  }

  void _onBuy(Map m, dynamic err, int ts) {
    _execTimer?.cancel();
    final st = eng.state();
    final rid = (m['req_id'] as num?)?.toInt() ?? st.last_trade_id;
    if (err is Map) {
      final code = err['code'] == 'InsufficientBalance' ? Err.insufficientBalance : Err.tradeRejected;
      eng.onBuyResult(rid, false, 0, 0, code, ts);
      _event('error', code, 'Buy rejected: ${err['message']}');
    } else {
      final b = m['buy'];
      if (b is! Map) return;
      eng.onBalance(null, _num(b['balance_after']), null);
      eng.onBuyResult(rid, true, (b['contract_id'] as num).toInt(), _num(b['buy_price']), 0, ts);
    }
    _persistSoon();
  }

  void _onPoc(Map m, int ts) {
    final p = m['proposal_open_contract'];
    if (p is! Map || p['contract_id'] == null) return;
    final cid = (p['contract_id'] as num).toInt();
    final status = p['status'];
    final profit = _num(p['profit']);
    final sold = p['is_sold'] == 1;
    int s = 0;
    if (status == 'won') s = 1; else if (status == 'lost') s = 2; else if (sold) s = profit >= 0 ? 1 : 2;
    if (_reconTid != 0) {                                    // reconciling an unconfirmed buy: match, never re-buy
      final pt = (p['purchase_time'] as num?)?.toInt() ?? 0;
      final since = _sentEpoch > 0 ? _sentEpoch - 5 : DateTime.now().millisecondsSinceEpoch ~/ 1000 - 120;
      final type = '${p['contract_type']}';
      if (p['underlying_symbol'] == _symbol && type.startsWith('DIGIT') && pt >= since) {
        _reconTimer?.cancel();
        final tid = _reconTid; _reconTid = 0;
        eng.reconcile(tid, true, cid, s, profit, eng.nowUs());
        _event('info', Err.none, 'Reconciled contract $cid from Deriv state.');
        _persistSoon(); return;
      }
    }
    eng.onContractUpdate(cid, s, profit, ts);
    if (s != 0) _persistSoon();
  }

  void _afterTradeReady() {
    final st = eng.state();
    if (st.fsm_state == Fsm.open && st.open_contract_id != 0) {
      _trd?.send(jsonEncode({'proposal_open_contract': 1, 'contract_id': st.open_contract_id, 'subscribe': 1}));
    } else if (st.fsm_state == Fsm.executing) {
      _startReconcile(st.last_trade_id);
    }
  }

  void _startReconcile(int tid) {
    _reconTid = tid;
    _trd?.send(jsonEncode({'proposal_open_contract': 1, 'subscribe': 1}));   // streams all currently open contracts
    _reconTimer?.cancel();
    _reconTimer = Timer(const Duration(seconds: 6), () {
      if (_reconTid == 0) return;
      final t = _reconTid; _reconTid = 0;
      eng.reconcile(t, false, 0, 0, 0, eng.nowUs());
      _event('error', Err.stateSyncFailed, 'Last buy could not be confirmed. Bot paused - check your Deriv statement.');
      _persistSoon(); _dirty = true;
    });
  }

  // ---------- config / commands ----------
  void _config(Map j) {
    final c = StrategyConfig.fromJson(j);
    final err = eng.configure(c);
    if (err == 0) {
      final marketChanged = _cfg != null && _cfg!.market != c.market;
      _cfg = c;
      if (marketChanged) {
        _symbol = kSymbols[c.market];
        _pub?.send(jsonEncode({'forget_all': 'ticks'}));
        _pub?.send(jsonEncode({'ticks': _symbol, 'subscribe': 1}));
        _pubState = Conn.synchronizing; eng.setConn(0, Conn.synchronizing); _lastTickUs = eng.nowUs();
      } else { _symbol = kSymbols[c.market]; }
      File('$_dir/strategy.json').writeAsString(jsonEncode(c.toJson()));
      _persistSoon();
    }
    ui.send({'t': 'configResult', 'err': err});
    _dirty = true;
  }

  void _cmd(int c) {
    final r = eng.command(c);
    if (r != 0) _event('warn', r, 'Command refused: ${errInfo(r).name}');
    _persistSoon(); _dirty = true;
  }

  // ---------- reporting / persistence (never on the tick->trade path) ----------
  void _pushState() {
    final st = eng.state();
    if (st.record_seq != _lastRecordSeq) {
      _lastRecordSeq = st.record_seq;
      final rec = eng.lastRecord();
      if (rec != null) {
        rec['account'] = _acct?.id ?? '';
        ui.send({'t': 'record', 'rec': rec});
        File('$_dir/trades.jsonl').writeAsString('${jsonEncode(rec)}\n', mode: FileMode.append);
      }
    }
    ui.send({'t': 'state', 'b': eng.stateBytes()});
  }

  void _persistSoon() { _persistDirty = true; Timer(Duration.zero, _persist); }

  Future<void> _persist() async {
    if (_persisting || !_ready) return;
    final bytes = eng.serialize();
    if (bytes == null) return;
    _persisting = true; _persistDirty = false;
    try {
      final tmp = File('$_dir/engine_state.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename('$_dir/engine_state.bin');             // atomic replace
    } catch (_) { _persistDirty = true; } finally { _persisting = false; }
  }

  void _event(String level, int code, String msg) {
    if (_ready && code != Err.none) eng.reportError(code);
    ui.send({'t': 'event', 'level': level, 'code': code, 'msg': msg, 'ts': DateTime.now().millisecondsSinceEpoch});
  }
}
