import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/errors.dart';
import '../models/strategy_config.dart';
import '../state/app_controller.dart';
import '../widgets/panel.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key, required this.app});
  final AppController app;
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late StrategyConfig c;
  final Map<String, TextEditingController> _t = {};
  String? _msg;

  @override
  void initState() { super.initState(); c = widget.app.cfg.copy(); }

  TextEditingController _ctl(String k, num v) => _t.putIfAbsent(k, () => TextEditingController(text: '$v'));

  Widget _field(String label, String k, num v, {bool decimal = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: _ctl(k, v), keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          style: kMono.copyWith(color: Pal.text),
          decoration: InputDecoration(labelText: label, isDense: true, filled: true, fillColor: Pal.lcd, border: OutlineInputBorder(borderRadius: BorderRadius.circular(6))),
        ),
      );

  Widget _seg(String label, List<String> opts, int val, void Function(int) set) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: Pal.dim, fontSize: 12))),
          ToggleButtons(isSelected: [for (int i = 0; i < opts.length; i++) i == val], onPressed: (i) => setState(() => set(i)),
              constraints: const BoxConstraints(minHeight: 34, minWidth: 74), borderRadius: BorderRadius.circular(6),
              selectedColor: Colors.black, fillColor: Pal.amber, color: Pal.text, children: [for (final o in opts) Text(o, style: const TextStyle(fontSize: 11))]),
        ]),
      );

  int? _i(String k) => int.tryParse(_t[k]!.text.trim());
  double? _d(String k) => double.tryParse(_t[k]!.text.trim().replaceAll(',', '.'));

  String? _collect() {
    final v = <String, Object?>{
      'barrier': _i('initialBarrier'), 'rb1': _i('recoveryBarrier1'), 'rb2': _i('recoveryBarrier2'), 'trig': _i('triggerDigit'),
      'consec': _i('consecutiveCount'), 'stake': _d('stake'), 'tp': _d('takeProfit'), 'sl': _d('stopLoss'), 'mult': _d('multiplier'),
      'steps': _i('martingaleMaxSteps'), 'maxStake': _d('maxStake'), 'maxDaily': _d('maxDailyLoss'), 'maxLoss': _i('maxConsecutiveLosses'),
    };
    if (v.values.any((e) => e == null)) return 'Every field needs a valid number.';
    c.initialBarrier = v['barrier'] as int; c.recoveryBarrier1 = v['rb1'] as int; c.recoveryBarrier2 = v['rb2'] as int;
    c.triggerDigit = v['trig'] as int; c.consecutiveCount = v['consec'] as int; c.stake = v['stake'] as double;
    c.takeProfit = v['tp'] as double; c.stopLoss = v['sl'] as double; c.multiplier = v['mult'] as double;
    c.martingaleMaxSteps = v['steps'] as int; c.maxStake = v['maxStake'] as double; c.maxDailyLoss = v['maxDaily'] as double;
    c.maxConsecutiveLosses = v['maxLoss'] as int;
    return null;
  }

  Future<void> _save() async {
    final e = _collect();
    if (e != null) { setState(() => _msg = e); return; }
    widget.app.applyConfig(c);
    await Future.delayed(const Duration(milliseconds: 400));
    final err = widget.app.lastConfigErr;
    if (!mounted) return;
    if (err == null || err == 0) { Navigator.pop(context); return; }
    final i = errInfo(err);
    setState(() => _msg = '${i.name}: ${i.message} ${i.action}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Pal.metalBot, title: const Text('STRATEGY', style: TextStyle(fontSize: 14, letterSpacing: 2))),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Panel(title: 'TRIGGER', child: Column(children: [
          _seg('Direction', const ['OVER', 'UNDER'], c.direction, (i) => c.direction = i),
          _seg('Deviation direction', const ['POSITIVE', 'NEGATIVE'], c.deviationDirection, (i) => c.deviationDirection = i),
          _field('Consecutive deviations', 'consecutiveCount', c.consecutiveCount),
          _field('Trigger digit (0-9)', 'triggerDigit', c.triggerDigit),
          _field('Initial barrier (OVER 0-8 / UNDER 1-9)', 'initialBarrier', c.initialBarrier),
        ])),
        Panel(title: 'RECOVERY', child: Column(children: [
          _field('Recovery barrier 1', 'recoveryBarrier1', c.recoveryBarrier1),
          _field('Recovery barrier 2', 'recoveryBarrier2', c.recoveryBarrier2),
          _seg('After a win', const ['RESET', 'STEP DOWN'], c.winBehavior, (i) => c.winBehavior = i),
        ])),
        Panel(title: 'STAKE & MARTINGALE', child: Column(children: [
          _field('Stake', 'stake', c.stake, decimal: true),
          _field('Take profit (0 = off)', 'takeProfit', c.takeProfit, decimal: true),
          _field('Stop loss (0 = off)', 'stopLoss', c.stopLoss, decimal: true),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Martingale', style: TextStyle(color: Pal.text)), value: c.martingale, onChanged: (v) => setState(() => c.martingale = v)),
          _field('Multiplier', 'multiplier', c.multiplier, decimal: true),
          _field('Maximum martingale steps', 'martingaleMaxSteps', c.martingaleMaxSteps),
        ])),
        Panel(title: 'RISK LIMITS (enforced by the C++ engine)', child: Column(children: [
          _field('Maximum stake (0 = off)', 'maxStake', c.maxStake, decimal: true),
          _field('Maximum daily loss (0 = off)', 'maxDailyLoss', c.maxDailyLoss, decimal: true),
          _field('Maximum consecutive losses (0 = off)', 'maxConsecutiveLosses', c.maxConsecutiveLosses),
        ])),
        if (_msg != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_msg!, style: const TextStyle(color: Pal.red))),
        Padding(padding: const EdgeInsets.all(16), child: MetalButton('SAVE', filled: true, color: Pal.green, onTap: _save)),
      ]),
    );
  }

  @override
  void dispose() { for (final t in _t.values) { t.dispose(); } super.dispose(); }
}
