import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/errors.dart';
import '../ffi/tc_structs.dart';
import '../state/app_controller.dart';
import '../services/deriv_rest.dart';
import '../widgets/panel.dart';

Color _signColor(int s) => s > 0 ? Pal.green : (s < 0 ? Pal.red : Pal.neutral);
Color _connColor(int c) => c == Conn.ready ? Pal.green : (c == Conn.degraded || c == Conn.synchronizing || c == Conn.authenticating || c == Conn.connected) ? Pal.amber : Pal.red;
String _ms(int us) => us <= 0 ? '-' : '${(us / 1000).toStringAsFixed(1)} ms';

/// Trade tab. Display only: every number comes from the C++ engine.
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
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        final s = a.snap.s;
        return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          ScreenTitle('Trade', sub: a.kesView ? 'Display in KES (converted, view only)' : 'Display in account currency',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Led(_connColor(s.public_conn)), const SizedBox(width: 5), const Text('Ticks', style: TextStyle(color: Pal.inkDim, fontSize: 11)),
                const SizedBox(width: 10),
                Led(_connColor(s.trade_conn)), const SizedBox(width: 5), Text(Conn.names[s.trade_conn], style: const TextStyle(color: Pal.inkDim, fontSize: 11)),
              ])),
          _accountSelector(s), _balance(s), _market(s), _analysis(s), _ticks(s), _signal(s), _execution(s), _controls(s), _events(), const CopyrightFooter(),
        ]);
      },
    );
  }

  // ---------- ACCOUNT SELECTOR ----------
  Account? _acctOf(bool real) {
    for (final x in a.accounts) { if (x.isReal == real && x.active) return x; }
    return null;
  }

  String _flagFor(Account x) => (a.kesView && x.currency == 'USD') ? '\u{1F1F0}\u{1F1EA}' : (x.currency == 'USD' ? '\u{1F1FA}\u{1F1F8}' : '\u{1F310}');

  Widget _accountSelector(TcState s) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Expanded(child: _acctCard(true, s)), const SizedBox(width: 10), Expanded(child: _acctCard(false, s)),
        ]),
      );

  Widget _acctCard(bool real, TcState s) {
    final x = _acctOf(real);
    final selected = x != null && x.id == a.activeId;
    final muted = !real || x == null;                       // Demo is always rendered in the greyed style
    final bg = muted ? Pal.greyCard : Pal.deep;
    final fg = muted ? Pal.greyInk : Pal.onDeep;
    final bal = x == null ? null : (selected ? s.balance : x.balance);
    return GestureDetector(
      onTap: x == null ? null : () => _pick(x),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? Pal.lime : Colors.transparent, width: 3),
          boxShadow: muted ? null : const [BoxShadow(color: Color(0x330B2B1D), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(x == null ? '\u{1F310}' : _flagFor(x), style: const TextStyle(fontSize: 20)), const SizedBox(width: 6),
            Text(real ? 'Real' : 'Demo', style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16)),
            const Spacer(),
            if (selected) const Icon(Icons.check_circle, color: Pal.lime, size: 20),
          ]),
          const SizedBox(height: 6),
          Text(x?.id ?? 'Not available', style: kMono.copyWith(color: fg.withOpacity(0.8), fontSize: 11)),
          const SizedBox(height: 8),
          Text(bal == null ? '-' : a.money(bal), style: kMono.copyWith(color: muted ? Pal.greyInk : Pal.lime, fontSize: 15, fontWeight: FontWeight.w800)),
          if (x != null && a.kesView && x.currency == 'USD')
            Text('converted from ${x.currency}', style: TextStyle(color: fg.withOpacity(0.7), fontSize: 9.5)),
        ]),
      ),
    );
  }

  Future<void> _pick(Account x) async {
    if (x.id == a.activeId) return;
    final st = a.snap.s;
    if (st.fsm_state == Fsm.executing || st.fsm_state == Fsm.open) { _snack('A trade is in progress - wait for it to settle before switching.'); return; }
    if (x.isReal) {
      final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: const Text('REAL ACCOUNT', style: TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w900)),
        content: const Text('Trades will use real funds.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue', style: TextStyle(color: Color(0xFFB3261E))))]));
      if (ok != true) return;
    }
    a.selectAccount(x.id);
  }

  // ---------- BALANCE ----------
  Widget _balance(TcState s) {
    final up = a.lastBalanceUpdate;
    String two(int n) => n.toString().padLeft(2, '0');
    return Panel(
      title: a.canConvert ? 'BALANCE · KES (CONVERTED, VIEW ONLY)' : 'BALANCE · ${a.activeCurrency ?? ''}',
      trailing: s.account_verified == 0 && a.activeId != null ? const Pill('VERIFYING', bg: Pal.amber) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(a.money(s.balance), style: kMono.copyWith(color: Pal.lime, fontSize: 34, fontWeight: FontWeight.w800)),
        if (a.canConvert)
          Padding(padding: const EdgeInsets.only(top: 2), child: Text(
              'Native account balance: ${a.nativeText(s.balance)}  ·  rate 1 USD = ${a.kesRate.toStringAsFixed(2)} KES (display only)',
              style: const TextStyle(color: Pal.onDeepDim, fontSize: 11))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Lcd('AVAILABLE', a.money(s.balance), size: 15)), const SizedBox(width: 8),
          Expanded(child: Lcd('UPDATED', '${two(up.hour)}:${two(up.minute)}:${two(up.second)}', size: 15)), const SizedBox(width: 8),
          Expanded(child: Lcd('TYPE', a.activeType == 'real' ? 'REAL' : 'DEMO', size: 15, color: a.activeType == 'real' ? Pal.red : Pal.green)),
        ]),
      ]),
    );
  }

  // ---------- MARKET ----------
  Widget _market(TcState s) {
    final busy = s.fsm_state == Fsm.executing || s.fsm_state == Fsm.open;
    return Panel(title: 'MARKET', child: Wrap(spacing: 8, runSpacing: 8, children: [
      for (int i = 0; i < 5; i++)
        GestureDetector(
          onTap: busy ? null : () => a.selectMarket(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(color: s.market == i ? Pal.lime : Pal.surface, borderRadius: BorderRadius.circular(30)),
            child: Text(kMarketNames[i], style: TextStyle(color: s.market == i ? Pal.deep : Pal.onDeep, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ),
    ]));
  }

  // ---------- LIVE ANALYSIS ----------
  Widget _analysis(TcState s) {
    final c = _signColor(s.deviation_sign);
    final has = s.prev_digit >= 0;
    final dirName = !has ? '-' : (s.deviation_sign > 0 ? 'POSITIVE' : s.deviation_sign < 0 ? 'NEGATIVE' : 'ZERO');
    return Panel(title: 'LIVE ANALYSIS', child: Column(children: [
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
    ]));
  }

  // ---------- LIVE TICK PANEL ----------
  Widget _ticks(TcState s) {
    final n = s.recent_count;
    final digits = a.snap.recentDigits();
    final shown = <Widget>[];
    for (int i = 0; i < n; i++) {
      final isCur = i == n - 1, isPrev = i == n - 2;
      final trig = isCur && s.trigger_status == 1;
      shown.add(Container(
        width: 32, height: 38, alignment: Alignment.center,
        decoration: BoxDecoration(color: trig ? Pal.lime : Pal.surface, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isCur ? _signColor(s.deviation_sign) : (isPrev ? Pal.onDeepDim : Colors.transparent), width: 2)),
        child: Text('${digits[i]}', style: kMono.copyWith(color: trig ? Pal.deep : Pal.onDeep, fontSize: 17, fontWeight: FontWeight.w800))));
      if (i < n - 1) shown.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 3), child: Text('›', style: TextStyle(color: Pal.onDeepDim))));
    }
    return Panel(title: 'TICKS', child: n == 0
        ? const Text('Waiting for ticks…', style: TextStyle(color: Pal.onDeepDim))
        : SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: Row(children: shown)));
  }

  // ---------- SIGNAL ----------
  Widget _signal(TcState s) {
    final q = s.trigger_status == 1;
    final restricted = s.restricted_dev2 == 99 ? 'none' : '${s.restricted_dev2 >= 0 ? '+' : ''}${(s.restricted_dev2 / 2).toStringAsFixed(1)}';
    return Panel(
      title: 'SIGNAL',
      trailing: Pill(q ? 'QUALIFIED' : 'WAITING', bg: q ? Pal.lime : Pal.surface, fg: q ? Pal.deep : Pal.onDeepDim),
      child: Column(children: [
        Row(children: [
          Expanded(child: Lcd('DIRECTION', s.signal_direction == 0 ? 'OVER' : 'UNDER', color: Pal.lime)), const SizedBox(width: 8),
          Expanded(child: Lcd('BARRIER', s.signal_barrier < 0 ? '-' : '${s.signal_barrier}', color: Pal.lime)), const SizedBox(width: 8),
          Expanded(child: a.cfg.triggerMode == 0
              ? Lcd('TRIGGER DIGIT', '${a.cfg.triggerDigit}', size: 16)
              : Lcd('TRIGGER DEV', '${a.cfg.triggerDeviation >= 0 ? '+' : ''}${a.cfg.triggerDeviation.toStringAsFixed(1)}', size: 16, color: _signColor(a.cfg.triggerDeviation >= 0 ? 1 : -1))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Lcd('LOSS-DEV FILTER', s.loss_filter_on == 1 ? 'ON' : 'OFF', size: 15, color: s.loss_filter_on == 1 ? Pal.lime : Pal.onDeepDim)), const SizedBox(width: 8),
          Expanded(child: Lcd('RESTRICTED DEV', s.loss_filter_on == 1 ? restricted : '-', size: 15)), const SizedBox(width: 8),
          Expanded(child: Lcd('REJECTED', '${s.filter_rejects}', size: 15)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Lcd('STRATEGY 1', s.s1_on == 1 ? 'ON' : 'OFF', size: 15, color: s.s1_on == 1 ? Pal.lime : Pal.onDeepDim)), const SizedBox(width: 8),
          Expanded(child: Lcd('STRATEGY 2', s.s2_on == 1 ? 'ON' : 'OFF', size: 15, color: s.s2_on == 1 ? Pal.lime : Pal.onDeepDim)), const SizedBox(width: 8),
          Expanded(child: Lcd('S2 ACTIVE', s.s2_started == 0 ? '-' : 'D${s.s2_idx + 1} ${a.cfg.s2Dev(s.s2_idx) >= 0 ? '+' : ''}${a.cfg.s2Dev(s.s2_idx).toStringAsFixed(1)}', size: 13,
              sub: s.s2_pending == 1 ? 'trade pending' : null)),
        ]),
      ]),
    );
  }

  // ---------- EXECUTION ----------
  Widget _execution(TcState s) {
    final res = kResultNames[s.last_result];
    final rc = s.last_result == 1 ? Pal.green : (s.last_result == 2 ? Pal.red : Pal.onDeepDim);
    return Panel(
      title: 'EXECUTION',
      trailing: GestureDetector(onTap: () => setState(() => _perf = !_perf), child: Text(_perf ? 'HIDE PERF' : 'PERF', style: const TextStyle(color: Pal.lime, fontSize: 11, fontWeight: FontWeight.w800))),
      child: Column(children: [
        Row(children: [
          Expanded(child: Lcd('BOT', Bot.names[s.bot_status], size: 14, color: s.bot_status == Bot.running ? Pal.green : (s.bot_status == Bot.emergency ? Pal.red : Pal.amber))), const SizedBox(width: 8),
          Expanded(child: Lcd('STATE', Fsm.names[s.fsm_state], size: 11)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Lcd('STAKE (${a.activeCurrency ?? 'native'})', s.current_stake.toStringAsFixed(2), size: 16)), const SizedBox(width: 8),
          Expanded(child: Lcd('LAST', res, color: rc, size: 14)), const SizedBox(width: 8),
          Expanded(child: Lcd('P/L', a.money(s.last_profit, sign: true), color: rc, size: 14)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Lcd('RECOVERY', const ['NORMAL', 'RECOVERY_1', 'RECOVERY_2'][s.recovery_level], size: 12, sub: s.unrecovered > 0 ? 'owed ${s.unrecovered.toStringAsFixed(2)}' : null)), const SizedBox(width: 8),
          Expanded(child: Lcd('MARTINGALE', 'L${s.martingale_level}', size: 14)), const SizedBox(width: 8),
          Expanded(child: Lcd('W / L', '${s.wins}/${s.losses}', size: 14)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(flex: 3, child: Lcd('SESSION P/L', a.money(s.session_pnl, sign: true), color: s.session_pnl >= 0 ? Pal.green : Pal.red, size: 14)), const SizedBox(width: 8),
          Expanded(flex: 2, child: Lcd('OUTCOME', a.lastOutcome, color: Pal.lime, size: 16)), const SizedBox(width: 8),
          Expanded(flex: 3, child: Lcd('LATENCY', _ms(s.lat_total_us), size: 14)),
        ]),
        if (a.canConvert) const Padding(padding: EdgeInsets.only(top: 8),
            child: Align(alignment: Alignment.centerLeft, child: Text('Stake and execution always use the account currency. KES amounts are converted for display only.', style: TextStyle(color: Pal.onDeepDim, fontSize: 10)))),
        if (_perf) Padding(padding: const EdgeInsets.only(top: 8), child: Column(children: [
          Row(children: [Expanded(child: Lcd('TICK→TRIGGER', _ms(s.lat_tick_to_trigger_us), size: 12)), const SizedBox(width: 8), Expanded(child: Lcd('TRIGGER→SEND', _ms(s.lat_trigger_to_send_us), size: 12))]),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: Lcd('SEND→ACK', _ms(s.lat_send_to_ack_us), size: 12)), const SizedBox(width: 8), Expanded(child: Lcd('ACK→OPEN', _ms(s.lat_ack_to_open_us), size: 12))]),
        ])),
        if (s.last_error != 0) Padding(padding: const EdgeInsets.only(top: 10), child: Align(alignment: Alignment.centerLeft,
          child: Text('${errInfo(s.last_error).name}: ${errInfo(s.last_error).message} ${errInfo(s.last_error).action}', style: const TextStyle(color: Pal.red, fontSize: 11)))),
      ]),
    );
  }

  // ---------- BOT CONTROL ----------
  Widget _controls(TcState s) {
    final emer = s.emergency_latched == 1;
    return Panel(title: 'BOT CONTROL', child: Column(children: [
      Row(children: [
        Expanded(flex: 3, child: MetalButton('START BOT', filled: true, onTap: emer ? null : () => a.command(Cmd.start))), const SizedBox(width: 8),
        Expanded(flex: 2, child: MetalButton('PAUSE', color: Pal.amber, onTap: () => a.command(Cmd.pause))), const SizedBox(width: 8),
        Expanded(flex: 2, child: MetalButton('STOP', onTap: () => a.command(Cmd.stop))),
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

  Widget _events() => Panel(title: 'EVENTS', child: a.events.isEmpty
      ? const Text('-', style: TextStyle(color: Pal.onDeepDim))
      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final e in a.events.take(8)) Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('${(e['code'] as int) == 0 ? 'INFO' : errInfo(e['code'] as int).name}  ${e['msg']}',
                style: TextStyle(color: e['level'] == 'error' ? Pal.red : (e['level'] == 'warn' ? Pal.amber : Pal.onDeepDim), fontSize: 10.5)))]));

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}
