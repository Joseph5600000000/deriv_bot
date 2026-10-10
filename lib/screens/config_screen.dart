import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/errors.dart';
import '../models/strategy_config.dart';
import '../state/app_controller.dart';
import '../widgets/panel.dart';

/// Strategy tab. Values are validated again by the C++ engine on save.
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key, required this.app});
  final AppController app;
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late StrategyConfig c = widget.app.cfg.copy();
  int _ver = -1;
  final Map<String, TextEditingController> _t = {};
  String? _msg;
  AppController get a => widget.app;

  TextEditingController _ctl(String k, num v) => _t.putIfAbsent(k, () => TextEditingController(text: '$v'));

  Widget _field(String label, String k, num v, {bool decimal = false, bool signed = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _ctl(k, v), keyboardType: TextInputType.numberWithOptions(decimal: decimal || signed, signed: signed),
          style: kMono.copyWith(color: Pal.onDeep), decoration: fieldDecoration(label),
        ),
      );

  Widget _seg(String label, List<String> opts, int val, void Function(int) set) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: Pal.onDeep, fontSize: 13))),
          Segmented(options: opts, value: val, onChanged: (i) => setState(() => set(i))),
        ]),
      );

  /// Collapsible strategy card with its own ON/OFF switch (applied immediately, independent of Save).
  Widget _strategyCard({required String title, required String sub, required bool on, required void Function(bool) onToggle, required List<Widget> children, bool open = false}) =>
      Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: Pal.deep2,
            boxShadow: const [BoxShadow(color: Color(0x330B2B1D), blurRadius: 18, offset: Offset(0, 8))]),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: open, maintainState: true, iconColor: Pal.lime, collapsedIconColor: Pal.onDeepDim,
            tilePadding: const EdgeInsets.fromLTRB(16, 4, 10, 4), childrenPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: Pal.onDeep, fontWeight: FontWeight.w800, fontSize: 16)),
                Text(sub, style: const TextStyle(color: Pal.onDeepDim, fontSize: 11)),
              ])),
              Pill(on ? 'ON' : 'OFF', bg: on ? Pal.lime : Pal.surface, fg: on ? Pal.deep : Pal.onDeepDim),
              Switch(value: on, onChanged: onToggle, activeColor: Pal.deep, activeTrackColor: Pal.lime, inactiveTrackColor: Pal.surface, inactiveThumbColor: Pal.onDeepDim),
            ]),
            children: children,
          ),
        ),
      );

  Widget _switch(String label, String sub, bool v, void Function(bool) set) => SwitchListTile(
        contentPadding: EdgeInsets.zero, value: v, onChanged: (x) => setState(() => set(x)),
        activeColor: Pal.deep, activeTrackColor: Pal.lime, inactiveTrackColor: Pal.surface, inactiveThumbColor: Pal.onDeepDim,
        title: Text(label, style: const TextStyle(color: Pal.onDeep, fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(sub, style: const TextStyle(color: Pal.onDeepDim, fontSize: 11)),
      );

  // Fields inside a collapsed panel may never have been built: fall back to the saved value so Save always sees every field.
  Widget _s2Status() {
    final st = a.snap.s;
    String lbl(int i) { final v = c.s2Dev(i); return 'D${i + 1} (${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}) ×${c.s2Cnt(i)}'; }
    return Row(children: [
      Expanded(child: Lcd('ACTIVE', lbl(st.s2_idx.clamp(0, 2)), size: 14, color: Pal.lime)), const SizedBox(width: 8),
      Expanded(child: Lcd('W / L', '${st.s2_wins}/${st.s2_losses}', size: 14)),
      if (st.s2_pending == 1) ...[const SizedBox(width: 8), const Expanded(child: Lcd('TRADE', 'PENDING', size: 12, color: Pal.amber))],
    ]);
  }

  Future<void> _newCycle() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Start a new cycle?'),
      content: const Text('Strategy 2 returns to Deviation 1. Its configuration and win/loss counts are kept.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Start new cycle'))]));
    if (ok == true) a.command(Cmd.s2NewCycle);
  }

  int? _i(String k) => int.tryParse((_t[k]?.text ?? '${_saved(k)}').trim());
  double? _d(String k) => double.tryParse((_t[k]?.text ?? '${_saved(k)}').trim().replaceAll(',', '.'));
  num _saved(String k) {
    final j = c.toJson();
    return (j[k] as num?) ?? 0;
  }

  String? _collect() {
    final v = <String, Object?>{
      'barrier': _i('initialBarrier'), 'rb1': _i('recoveryBarrier1'), 'rb2': _i('recoveryBarrier2'),
      'consec': _i('consecutiveCount'), 'stake': _d('stake'), 'tp': _d('takeProfit'), 'sl': _d('stopLoss'), 'mult': _d('multiplier'),
      'steps': _i('martingaleMaxSteps'), 'maxStake': _d('maxStake'), 'maxDaily': _d('maxDailyLoss'), 'maxLoss': _i('maxConsecutiveLosses'),
    };
    if (v.values.any((e) => e == null)) return 'Every field needs a valid number.';
    c.initialBarrier = v['barrier'] as int; c.recoveryBarrier1 = v['rb1'] as int; c.recoveryBarrier2 = v['rb2'] as int;
    if (c.triggerMode == 0) {
      final t = _i('triggerDigit');
      if (t == null) return 'Trigger digit needs a number from 0 to 9.';
      c.triggerDigit = t;
    } else {
      final dv = _d('triggerDeviation');
      if (dv == null) return 'Deviation trigger needs a number such as +0.5 or -1.5.';
      final problem = c.deviationProblem(dv);
      if (problem != null) return problem;
      c.triggerDeviation = dv;
    }
    final s2 = <double?>[_d('s2Dev1'), _d('s2Dev2'), _d('s2Dev3')];
    for (int k = 0; k < 3; k++) {
      if (s2[k] == null) return 'Strategy 2 Deviation ${k + 1} needs a number such as +2.0 or -1.5.';
      final pr = StrategyConfig.s2Problem(s2[k]!);
      if (pr != null) return 'Strategy 2 Deviation ${k + 1}: $pr';
    }
    final cn = <int?>[_i('s2Cnt1'), _i('s2Cnt2'), _i('s2Cnt3')];
    for (int k = 0; k < 3; k++) {
      if (cn[k] == null || cn[k]! < 1 || cn[k]! > 50) return 'Strategy 2 Deviation ${k + 1} count must be a whole number from 1 to 50.';
    }
    c.s2Cnt1 = cn[0]!; c.s2Cnt2 = cn[1]!; c.s2Cnt3 = cn[2]!;
    c.s2Dev1 = s2[0]!; c.s2Dev2 = s2[1]!; c.s2Dev3 = s2[2]!;
    c.consecutiveCount = v['consec'] as int; c.stake = v['stake'] as double;
    c.takeProfit = v['tp'] as double; c.stopLoss = v['sl'] as double; c.multiplier = v['mult'] as double;
    c.martingaleMaxSteps = v['steps'] as int; c.maxStake = v['maxStake'] as double; c.maxDailyLoss = v['maxDaily'] as double;
    c.maxConsecutiveLosses = v['maxLoss'] as int;
    return null;
  }

  Future<void> _save() async {
    final e = _collect();
    if (e != null) { setState(() => _msg = e); return; }
    a.applyConfig(c);
    await Future.delayed(const Duration(milliseconds: 450));
    final err = a.lastConfigErr;
    if (!mounted) return;
    if (err == null || err == 0) {
      setState(() => _msg = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Strategy saved')));
      return;
    }
    final i = errInfo(err);
    setState(() => _msg = '${i.name}: ${i.message} ${i.action}');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        if (_ver != a.cfgVersion) {                              // settings restored from disk after startup
          _ver = a.cfgVersion; c = a.cfg.copy();
          for (final t in _t.values) { t.dispose(); }
          _t.clear();
        }
        return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          const ScreenTitle('Strategy', sub: 'Saved settings are enforced by the trading engine'),
          _strategyCard(title: 'Strategy 1', sub: 'Consecutive deviations + trigger digit / deviation', on: a.snap.s.s1_on == 1,
            onToggle: (v) => a.command(v ? Cmd.s1On : Cmd.s1Off), open: true, children: [
            _seg('Initial direction', const ['OVER', 'UNDER'], c.direction, (i) => c.direction = i),
            _seg('Deviation', const ['POSITIVE', 'NEGATIVE'], c.deviationDirection, (i) => c.deviationDirection = i),
            _field('Consecutive deviations', 'consecutiveCount', c.consecutiveCount),
            _seg('Trigger mode', const ['TRIGGER DIGIT', 'DEVIATION'], c.triggerMode, (i) => c.triggerMode = i),
            if (c.triggerMode == 0)
              _field('Trigger digit (0-9)', 'triggerDigit', c.triggerDigit)
            else
              _field('Deviation trigger (e.g. +0.5 or -1.5, sign must match direction)', 'triggerDeviation', c.triggerDeviation, signed: true),
            _field('Initial barrier (OVER 0-8 / UNDER 1-9)', 'initialBarrier', c.initialBarrier),
          ]),
          _strategyCard(title: 'Strategy 2', sub: 'Three exact deviations, advanced by each result', on: a.snap.s.s2_on == 1,
            onToggle: (v) => a.command(v ? Cmd.s2On : Cmd.s2Off), children: [
            _field('Deviation 1 (e.g. +2.0)', 's2Dev1', c.s2Dev1, signed: true),
            _field('Deviation 1 count (1 = trigger only)', 's2Cnt1', c.s2Cnt1),
            _field('Deviation 2 (e.g. -1.5)', 's2Dev2', c.s2Dev2, signed: true),
            _field('Deviation 2 count (1 = trigger only)', 's2Cnt2', c.s2Cnt2),
            _field('Deviation 3 (e.g. +0.5)', 's2Dev3', c.s2Dev3, signed: true),
            _field('Deviation 3 count (1 = trigger only)', 's2Cnt3', c.s2Cnt3),
            _s2Status(),
            const SizedBox(height: 10),
            MetalButton('START NEW CYCLE (back to Deviation 1)', onTap: () => _newCycle()),
            const SizedBox(height: 10),
            const Text('Each deviation also has a count: N means the trigger must be preceded by N-1 consecutive deviations of the same sign (taken from the trigger's sign). Count 1 = trigger only. Win/Loss moves: D1 \u2192 D2 / D3, D2 \u2192 D3 / D1, D3 \u2192 D2 / D1. It advances only on a confirmed result. Barrier, direction, stake, recovery, martingale and risk limits are shared with the rest of the app. The bot must be started on the Trade tab. Turning Strategy 2 OFF keeps its place in the cycle.',
                style: TextStyle(color: Pal.onDeepDim, fontSize: 11)),
          ]),
          Panel(title: 'GLOBAL FILTER', child: _switch(
            'Loss-Deviation Filter', 'After a loss, skip the next qualifying trade only if its deviation equals the losing one. Skipped signals are not trades and change no recovery or martingale state. OFF = original behaviour.',
            c.lossDevFilter, (v) => c.lossDevFilter = v)),
          Panel(title: 'RECOVERY (contract type per level)', child: Column(children: [
            _seg('Recovery 1 direction', const ['OVER', 'UNDER'], c.recoveryDirection1, (i) => c.recoveryDirection1 = i),
            _field('Recovery barrier 1 (OVER 0-8 / UNDER 1-9)', 'recoveryBarrier1', c.recoveryBarrier1),
            _seg('Recovery 2 direction', const ['OVER', 'UNDER'], c.recoveryDirection2, (i) => c.recoveryDirection2 = i),
            _field('Recovery barrier 2 (OVER 0-8 / UNDER 1-9)', 'recoveryBarrier2', c.recoveryBarrier2),
            const Padding(padding: EdgeInsets.only(top: 6), child: Text(
              'Shared by Strategy 1 and 2. Recovery follows your total unrecovered loss: Initial loss → R1, R1 loss or partial win → R2, '
              'R2 stays until all losses are recovered, then back to Initial.', style: TextStyle(fontSize: 11))),
          ])),
          Panel(title: 'STAKE & MARTINGALE', child: Column(children: [
            _field('Stake (account currency)', 'stake', c.stake, decimal: true),
            _field('Take profit (0 = off)', 'takeProfit', c.takeProfit, decimal: true),
            _field('Stop loss (0 = off)', 'stopLoss', c.stopLoss, decimal: true),
            _switch('Martingale', 'Multiply the stake after each loss', c.martingale, (v) => c.martingale = v),
            _field('Multiplier', 'multiplier', c.multiplier, decimal: true),
            _field('Maximum martingale steps', 'martingaleMaxSteps', c.martingaleMaxSteps),
          ])),
          Panel(title: 'RISK LIMITS', child: Column(children: [
            _field('Maximum stake (0 = off)', 'maxStake', c.maxStake, decimal: true),
            _field('Maximum daily loss (0 = off)', 'maxDailyLoss', c.maxDailyLoss, decimal: true),
            _field('Maximum consecutive losses (0 = off)', 'maxConsecutiveLosses', c.maxConsecutiveLosses),
          ])),
          if (_msg != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4), child: Text(_msg!, style: const TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w600))),
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: MetalButton('SAVE STRATEGY', filled: true, onTap: _save)),
          const CopyrightFooter(),
        ]);
      },
    );
  }

  @override
  void dispose() { for (final t in _t.values) { t.dispose(); } super.dispose(); }
}
