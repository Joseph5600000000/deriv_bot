import 'package:flutter/material.dart';
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

  Widget _switch(String label, String sub, bool v, void Function(bool) set) => SwitchListTile(
        contentPadding: EdgeInsets.zero, value: v, onChanged: (x) => setState(() => set(x)),
        activeColor: Pal.deep, activeTrackColor: Pal.lime, inactiveTrackColor: Pal.surface, inactiveThumbColor: Pal.onDeepDim,
        title: Text(label, style: const TextStyle(color: Pal.onDeep, fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(sub, style: const TextStyle(color: Pal.onDeepDim, fontSize: 11)),
      );

  int? _i(String k) => int.tryParse(_t[k]!.text.trim());
  double? _d(String k) => double.tryParse(_t[k]!.text.trim().replaceAll(',', '.'));

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
          Panel(title: 'TRIGGER (one mode active at a time)', child: Column(children: [
            _seg('Initial direction', const ['OVER', 'UNDER'], c.direction, (i) => c.direction = i),
            _seg('Deviation', const ['POSITIVE', 'NEGATIVE'], c.deviationDirection, (i) => c.deviationDirection = i),
            _field('Consecutive deviations', 'consecutiveCount', c.consecutiveCount),
            _seg('Trigger mode', const ['TRIGGER DIGIT', 'DEVIATION'], c.triggerMode, (i) => c.triggerMode = i),
            if (c.triggerMode == 0)
              _field('Trigger digit (0-9)', 'triggerDigit', c.triggerDigit)
            else
              _field('Deviation trigger (e.g. +0.5 or -1.5, sign must match direction)', 'triggerDeviation', c.triggerDeviation, signed: true),
            _field('Initial barrier (OVER 0-8 / UNDER 1-9)', 'initialBarrier', c.initialBarrier),
          ])),
          Panel(title: 'GLOBAL FILTER', child: _switch(
            'Loss-Deviation Filter', 'After a loss, skip the next qualifying trade only if its deviation equals the losing one. Skipped signals are not trades and change no recovery or martingale state. OFF = original behaviour.',
            c.lossDevFilter, (v) => c.lossDevFilter = v)),
          Panel(title: 'RECOVERY (contract type per level)', child: Column(children: [
            _seg('Recovery 1 direction', const ['OVER', 'UNDER'], c.recoveryDirection1, (i) => c.recoveryDirection1 = i),
            _field('Recovery barrier 1 (OVER 0-8 / UNDER 1-9)', 'recoveryBarrier1', c.recoveryBarrier1),
            _seg('Recovery 2 direction', const ['OVER', 'UNDER'], c.recoveryDirection2, (i) => c.recoveryDirection2 = i),
            _field('Recovery barrier 2 (OVER 0-8 / UNDER 1-9)', 'recoveryBarrier2', c.recoveryBarrier2),
            _seg('After a win', const ['RESET', 'STEP DOWN'], c.winBehavior, (i) => c.winBehavior = i),
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
