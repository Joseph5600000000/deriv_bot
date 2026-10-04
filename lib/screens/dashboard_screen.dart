import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/errors.dart';
import '../ffi/tc_structs.dart';
import '../state/app_controller.dart';
import '../widgets/panel.dart';
import 'config_screen.dart';

Color _signColor(int s) => s > 0 ? Pal.green : (s < 0 ? Pal.red : Pal.neutral);
Color _connColor(int c) => c == Conn.ready ? Pal.green : (c == Conn.degraded || c == Conn.synchronizing || c == Conn.authenticating || c == Conn.connected) ? Pal.amber : Pal.red;
String _ms(int us) => us <= 0 ? '-' : '${(us / 1000).toStringAsFixed(1)} ms';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.app});
  final AppController app;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _perf = false;
  AppController get a => widget.app;

  @override
  Widget build(BuildContext context) {
    final s = a.snap.s;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Pal.metalBot, title: const Text('DERIV DIGIT BOT', style: TextStyle(fontSize: 14, letterSpacing: 2)),
        actions: [
          IconButton(icon: const Icon(Icons.tune), tooltip: 'Strategy', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ConfigScreen(app: a)))),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Disconnect / Remove PAT', onPressed: _confirmLogout),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
        _account(s), _market(s), _analysis(s), _ticks(s), _signal(s), _execution(s), _controls(s), _tradeLog(), _events(),
      ]),
    );
  }

  // ---- ACCOUNT ----
  Widget _account(TcState s) {
    final acc = a.active;
    final real = a.activeType == 'real';
    return Panel(
      title: 'ACCOUNT',
      trailing: Row(children: [Led(_connColor(s.trade_conn)), const SizedBox(width: 6),
        Text(Conn.names[s.trade_conn], style: const TextStyle(color: Pal.dim, fontSize: 10))]),
      child: Column(children: [
        InkWell(
          onTap: _pickAccount,
          child: Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: real ? Pal.red : Pal.green, borderRadius: BorderRadius.circular(4)),
              child: Text(real ? 'REAL' : 'DEMO', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12))),
            const SizedBox(width: 10),
            Expanded(child: Text(a.activeId ?? 'Select account', style: kMono.copyWith(color: Pal.text))),
            const Icon(Icons.swap_horiz, color: Pal.dim),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Lcd('BALANCE ${a.activeCurrency ?? ''}', s.balance.toStringAsFixed(2), color: Pal.green)),
          const SizedBox(width: 8),
          Expanded(child: Lcd('AVAILABLE', s.balance.toStringAsFixed(2), size: 16)),
          const SizedBox(width: 8),
          Expanded(child: Lcd('UPDATED', '${a.lastBalanceUpdate.hour.toString().padLeft(2, '0')}:${a.lastBalanceUpdate.minute.toString().padLeft(2, '0')}:${a.lastBalanceUpdate.second.toString().padLeft(2, '0')}', size: 13)),
        ]),
        if (acc != null && s.account_verified == 0) const Padding(padding: EdgeInsets.only(top: 6),
            child: Text('Verifying account identity…', style: TextStyle(color: Pal.amber, fontSize: 11))),
      ]),
    );
  }

  Future<void> _pickAccount() async {
    final busy = a.snap.s.fsm_state == Fsm.executing || a.snap.s.fsm_state == Fsm.open;
    if (busy) { _snack('A trade is in progress - wait for it to settle before switching.'); return; }
    final id = await showModalBottomSheet<String>(context: context, backgroundColor: Pal.metalBot, builder: (c) => ListView(shrinkWrap: true, children: [
      for (final x in a.accounts) ListTile(
        leading: Led(x.isReal ? Pal.red : Pal.green),
        title: Text('${x.isReal ? 'REAL' : 'DEMO'}  ${x.id}', style: kMono.copyWith(color: Pal.text)),
        subtitle: Text('${x.currency}  ${x.balance.toStringAsFixed(2)}  ${x.status}', style: const TextStyle(color: Pal.dim)),
        onTap: () => Navigator.pop(c, x.id)),
    ]));
    if (id == null || id == a.activeId) return;
    final acc = a.accounts.firstWhere((x) => x.id == id);
    if (acc.isReal) {
      final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        backgroundColor: Pal.metalBot,
        title: const Text('REAL ACCOUNT', style: TextStyle(color: Pal.red, fontWeight: FontWeight.w900)),
        content: const Text('Trades will use real funds.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue', style: TextStyle(color: Pal.red)))]));
      if (ok != true) return;
    }
    a.selectAccount(id);
  }

  // ---- MARKET ----
  Widget _market(TcState s) => Panel(title: 'MARKET', child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (int i = 0; i < 5; i++) ChoiceChip(
          label: Text(kMarketNames[i], style: TextStyle(fontSize: 11, color: s.market == i ? Colors.black : Pal.text)),
          selected: s.market == i, selectedColor: Pal.amber, backgroundColor: Pal.lcd,
          onSelected: (s.fsm_state == Fsm.executing || s.fsm_state == Fsm.open) ? null : (_) => a.selectMarket(i)),
      ]));

  // ---- LIVE ANALYSIS ----
  Widget _analysis(TcState s) {
    final c = _signColor(s.deviation_sign);
    final has = s.prev_digit >= 0;
    final dirName = !has ? '-' : (s.deviation_sign > 0 ? 'POSITIVE' : s.deviation_sign < 0 ? 'NEGATIVE' : 'ZERO');
    return Panel(
      title: 'LIVE ANALYSIS',
      trailing: Row(children: [Led(_connColor(s.public_conn)), const SizedBox(width: 6), Text(Conn.names[s.public_conn], style: const TextStyle(color: Pal.dim, fontSize: 10))]),
      child: Column(children: [
        Row(children: [
          Expanded(child: Lcd('PREVIOUS', has ? '${s.prev_digit}' : '-')), const SizedBox(width: 8),
          Expanded(child: Lcd('CURRENT', s.cur_digit >= 0 ? '${s.cur_digit}' : '-')), const SizedBox(width: 8),
          Expanded(child: Lcd('AVERAGE', has ? s.average.toStringAsFixed(1) : '-')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Lcd('DEVIATION', has ? '${s.deviation >= 0 ? '+' : ''}${s.deviation.toStringAsFixed(1)}' : '-', color: c)), const SizedBox(width: 8),
          Expanded(child: Lcd('DIRECTION', dirName, color: c, size: 14)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Lcd('CONSEC +', '${s.consec_pos}', color: Pal.green, size: 16)), const SizedBox(width: 8),
          Expanded(child: Lcd('CONSEC −', '${s.consec_neg}', color: Pal.red, size: 16)),
        ]),
      ]),
    );
  }

  // ---- LIVE TICK PANEL ----
  Widget _ticks(TcState s) {
    final n = s.recent_count;
    final digits = a.snap.recentDigits();
    final shown = <Widget>[];
    for (int i = 0; i < n; i++) {
      final d = digits[i];
      final isCur = i == n - 1, isPrev = i == n - 2;
      final trig = isCur && s.trigger_status == 1;
      shown.add(Container(
        width: 30, height: 34, alignment: Alignment.center,
        decoration: BoxDecoration(color: trig ? Pal.amber : Pal.lcd, borderRadius: BorderRadius.circular(5),
            border: Border.all(color: isCur ? _signColor(s.deviation_sign) : (isPrev ? Pal.dim : Colors.black), width: isCur || isPrev ? 2 : 1)),
        child: Text('$d', style: kMono.copyWith(color: trig ? Colors.black : Pal.text, fontSize: 16, fontWeight: FontWeight.w700))));
      if (i < n - 1) shown.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: Text('›', style: TextStyle(color: Pal.dim))));
    }
    return Panel(title: 'TICKS', child: n == 0 ? const Text('Waiting for ticks…', style: TextStyle(color: Pal.dim))
        : SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: Row(children: shown)));
  }

  // ---- SIGNAL ----
  Widget _signal(TcState s) {
    final q = s.trigger_status == 1;
    return Panel(title: 'SIGNAL', trailing: Text(q ? 'QUALIFIED' : 'WAITING', style: TextStyle(color: q ? Pal.amber : Pal.dim, fontWeight: FontWeight.w800, fontSize: 11)),
      child: Row(children: [
        Expanded(child: Lcd('DIRECTION', s.signal_direction == 0 ? 'OVER' : 'UNDER', color: Pal.amber)), const SizedBox(width: 8),
        Expanded(child: Lcd('BARRIER', s.signal_barrier < 0 ? '-' : '${s.signal_barrier}', color: Pal.amber)), const SizedBox(width: 8),
        Expanded(child: Lcd('TRIGGER DIGIT', '${a.cfg.triggerDigit}', size: 16)),
      ]));
  }

  // ---- EXECUTION ----
  Widget _execution(TcState s) {
    final res = kResultNames[s.last_result];
    final rc = s.last_result == 1 ? Pal.green : (s.last_result == 2 ? Pal.red : Pal.dim);
    return Panel(
      title: 'EXECUTION',
      trailing: GestureDetector(onTap: () => setState(() => _perf = !_perf), child: Text(_perf ? 'HIDE PERF' : 'PERF', style: const TextStyle(color: Pal.amber, fontSize: 10))),
      child: Column(children: [
        Row(children: [
          Expanded(child: Lcd('BOT', Bot.names[s.bot_status], size: 14, color: s.bot_status == Bot.running ? Pal.green : (s.bot_status == Bot.emergency ? Pal.red : Pal.amber))), const SizedBox(width: 8),
          Expanded(child: Lcd('STATE', Fsm.names[s.fsm_state], size: 11)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Lcd('STAKE', s.current_stake.toStringAsFixed(2), size: 16)), const SizedBox(width: 8),
          Expanded(child: Lcd('LAST', res, color: rc, size: 14)), const SizedBox(width: 8),
          Expanded(child: Lcd('P/L', '${s.last_profit >= 0 ? '+' : ''}${s.last_profit.toStringAsFixed(2)}', color: rc, size: 14)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Lcd('RECOVERY', const ['NORMAL', 'RECOVERY_1', 'RECOVERY_2'][s.recovery_level], size: 12)), const SizedBox(width: 8),
          Expanded(child: Lcd('MARTINGALE', 'L${s.martingale_level}', size: 14)), const SizedBox(width: 8),
          Expanded(child: Lcd('W / L', '${s.wins}/${s.losses}', size: 14)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Lcd('SESSION P/L', s.session_pnl.toStringAsFixed(2), color: s.session_pnl >= 0 ? Pal.green : Pal.red, size: 14)), const SizedBox(width: 8),
          Expanded(child: Lcd('LATENCY', _ms(s.lat_total_us), size: 14)),
        ]),
        if (_perf) Padding(padding: const EdgeInsets.only(top: 8), child: Column(children: [
          Row(children: [Expanded(child: Lcd('TICK→TRIGGER', _ms(s.lat_tick_to_trigger_us), size: 12)), const SizedBox(width: 8), Expanded(child: Lcd('TRIGGER→SEND', _ms(s.lat_trigger_to_send_us), size: 12))]),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: Lcd('SEND→ACK', _ms(s.lat_send_to_ack_us), size: 12)), const SizedBox(width: 8), Expanded(child: Lcd('ACK→OPEN', _ms(s.lat_ack_to_open_us), size: 12))]),
        ])),
        if (s.last_error != 0) Padding(padding: const EdgeInsets.only(top: 8), child: Align(alignment: Alignment.centerLeft,
          child: Text('${errInfo(s.last_error).name}: ${errInfo(s.last_error).message} ${errInfo(s.last_error).action}', style: const TextStyle(color: Pal.red, fontSize: 11)))),
      ]),
    );
  }

  // ---- BOT CONTROL ----
  Widget _controls(TcState s) {
    final emer = s.emergency_latched == 1;
    return Panel(title: 'BOT CONTROL', child: Column(children: [
      Row(children: [
        Expanded(child: MetalButton('START BOT', filled: true, color: Pal.green, onTap: emer ? null : () => a.command(Cmd.start))), const SizedBox(width: 8),
        Expanded(child: MetalButton('PAUSE', color: Pal.amber, onTap: () => a.command(Cmd.pause))), const SizedBox(width: 8),
        Expanded(child: MetalButton('STOP', onTap: () => a.command(Cmd.stop))),
      ]),
      const SizedBox(height: 8),
      emer ? MetalButton('CLEAR EMERGENCY STOP', color: Pal.amber, onTap: () => a.command(Cmd.clearEmergency))
           : MetalButton('EMERGENCY STOP', filled: true, color: Pal.red, onTap: () => a.command(Cmd.emergencyStop)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: MetalButton('RESET ANALYSIS', onTap: () => a.command(Cmd.resetAnalysis))), const SizedBox(width: 8),
        Expanded(child: MetalButton('RESET RECOVERY', onTap: () => a.command(Cmd.resetStrategy))),
      ]),
    ]));
  }

  Widget _tradeLog() => Panel(title: 'TRADE LOG', child: a.trades.isEmpty
      ? const Text('No trades yet.', style: TextStyle(color: Pal.dim))
      : Column(children: [for (final t in a.trades.take(10)) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
          Led(t['result'] == 1 ? Pal.green : (t['result'] == 2 ? Pal.red : Pal.amber), size: 8), const SizedBox(width: 8),
          Expanded(child: Text('#${t['trade_id']} ${t['direction'] == 0 ? 'OVER' : 'UNDER'} ${t['barrier']}  d${t['prev']}→${t['cur']}  stake ${(t['stake'] as double).toStringAsFixed(2)}  R${t['recovery']} M${t['martingale']}', style: kMono.copyWith(color: Pal.text, fontSize: 11))),
          Text('${(t['profit'] as double) >= 0 ? '+' : ''}${(t['profit'] as double).toStringAsFixed(2)}', style: kMono.copyWith(color: (t['profit'] as double) >= 0 ? Pal.green : Pal.red, fontSize: 12)),
        ]))]));

  Widget _events() => Panel(title: 'EVENTS', child: a.events.isEmpty
      ? const Text('-', style: TextStyle(color: Pal.dim))
      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final e in a.events.take(8)) Padding(padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text('${errInfo(e['code'] as int).name == 'UNKNOWN' && e['code'] == 0 ? 'INFO' : errInfo(e['code'] as int).name}  ${e['msg']}', style: TextStyle(color: e['level'] == 'error' ? Pal.red : (e['level'] == 'warn' ? Pal.amber : Pal.dim), fontSize: 10)))]));

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      backgroundColor: Pal.metalBot, title: const Text('Disconnect / Remove PAT'),
      content: const Text('Trading stops and the stored token is deleted from this device.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove'))]));
    if (ok == true) a.disconnect();
  }
}
