import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/constants.dart';
import '../core/errors.dart';
import '../ffi/engine_ffi.dart';
import '../models/strategy_config.dart';
import '../security/secure_store.dart';
import '../services/deriv_rest.dart';
import '../services/trading_worker.dart';

enum Phase { booting, needPat, authenticating, ready }

/// UI-side mirror. It displays engine state and forwards user intent; it never decides trades.
class AppController extends ChangeNotifier {
  final SecureStore _store = SecureStore();
  final ReceivePort _rx = ReceivePort();
  SendPort? _worker;
  Isolate? _iso;
  Phase phase = Phase.booting;
  final EngineSnap snap = EngineSnap();
  StrategyConfig cfg = StrategyConfig();
  List<Account> accounts = [];
  String? activeId, activeType, activeCurrency, maskedPat, loginErrorTitle, loginErrorBody, loginErrorTech;
  final List<Map<String, dynamic>> trades = [];
  final List<Map<String, dynamic>> events = [];
  int? lastConfigErr;
  bool _fromStored = false;
  String appId = kDerivAppId;
  DateTime lastBalanceUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  Account? get active { for (final a in accounts) { if (a.id == activeId) return a; } return null; }

  Future<void> boot() async {
    final dir = (await getApplicationSupportDirectory()).path;
    _iso = await Isolate.spawn(tradingWorkerMain, _rx.sendPort);
    _rx.listen((m) => _onMsg(m as Map, dir));
  }

  void _send(Map m) => _worker?.send(m);

  Future<void> _onMsg(Map m, String dir) async {
    switch (m['t']) {
      case 'ready':
        _worker = m['port'] as SendPort;
        _send({'t': 'init', 'dir': dir, 'appId': kDerivAppId, 'resume': false});   // cold start => never auto-resume trading
        break;
      case 'inited':
        appId = (await _store.readAppId()) ?? kDerivAppId;
        final pat = await _store.readPat();
        if (pat != null && pat.isNotEmpty) { _fromStored = true; _login(pat); }
        else { phase = Phase.needPat; notifyListeners(); }
        break;
      case 'cfg': cfg = StrategyConfig.fromJson(m['cfg'] as Map); notifyListeners(); break;
      case 'loginResult': await _onLogin(m); break;
      case 'account':
        activeId = m['id'] as String; activeType = m['type'] as String; activeCurrency = m['currency'] as String;
        notifyListeners(); break;
      case 'state': snap.load(m['b'] as Uint8List); lastBalanceUpdate = DateTime.now(); notifyListeners(); break;
      case 'record':
        trades.insert(0, Map<String, dynamic>.from(m['rec'] as Map));
        if (trades.length > 50) trades.removeLast();
        notifyListeners(); break;
      case 'event':
        events.insert(0, Map<String, dynamic>.from(m));
        if (events.length > 40) events.removeLast();
        notifyListeners(); break;
      case 'configResult': lastConfigErr = m['err'] as int; notifyListeners(); break;
    }
  }

  Future<void> submitPat(String raw, [String? app]) async {
    if (app != null && app.trim().isNotEmpty) appId = app.trim();
    final pat = raw.trim();
    if (pat.length < 8 || pat.contains(RegExp(r'\s'))) {
      loginErrorTitle = 'PAT_INVALID'; loginErrorBody = 'That does not look like a token.';
      loginErrorTech = 'Local check: empty, too short or contains whitespace';
      notifyListeners(); return;
    }
    _fromStored = false;
    _login(pat);
  }

  void _login(String pat) {
    phase = Phase.authenticating; loginErrorTitle = loginErrorBody = loginErrorTech = null;
    maskedPat = '••••${pat.substring(pat.length - 4)}';          // never show the full token after submission
    notifyListeners();
    _send({'t': 'login', 'pat': pat, 'appId': appId});
    _pendingPat = pat;
  }
  String? _pendingPat;

  Future<void> _onLogin(Map m) async {
    if (m['ok'] == true) {
      if (_pendingPat != null) { await _store.writePat(_pendingPat!); await _store.writeAppId(appId); }
      _pendingPat = null;
      accounts = (m['accounts'] as List).map((a) => Account.fromJson({
            'account_id': (a as Map)['id'], 'account_type': a['type'], 'currency': a['currency'],
            'status': a['status'], 'balance': a['balance']})).toList();
      phase = Phase.ready;
    } else {
      final code = m['code'] as int;
      final info = errInfo(code);
      loginErrorTitle = '${info.name}  (code $code)';
      loginErrorBody = '${info.message} ${info.action}';
      loginErrorTech = m['technical'] as String?;
      if (_fromStored && (code == Err.patInvalid || code == Err.patExpired || code == Err.patScopeMissing)) await _store.clearPat();
      _pendingPat = null; maskedPat = null;
      phase = Phase.needPat;
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    _send({'t': 'logout'});
    await _store.clearPat();
    accounts = []; activeId = null; maskedPat = null; phase = Phase.needPat;
    notifyListeners();
  }

  void selectAccount(String id) => _send({'t': 'select', 'id': id});
  void applyConfig(StrategyConfig c) { cfg = c; lastConfigErr = null; _send({'t': 'config', 'cfg': c.toJson()}); notifyListeners(); }
  void command(int c) => _send({'t': 'cmd', 'cmd': c});
  void selectMarket(int idx) { final c = cfg.copy()..market = idx; applyConfig(c); }

  @override
  void dispose() { _iso?.kill(priority: Isolate.immediate); _rx.close(); super.dispose(); }
}
