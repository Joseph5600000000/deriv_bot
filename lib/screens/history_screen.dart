import 'package:flutter/material.dart';
import '../state/app_controller.dart';
import '../widgets/panel.dart';

/// Performance statistics + trade history. "Clear" affects statistics only (never strategy/risk/live state).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final s = app.snap.s;
        final total = s.wins + s.losses;
        final rate = total == 0 ? '-' : '${(s.wins * 100 / total).toStringAsFixed(1)}%';
        final net = s.stats_pnl;
        return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          const ScreenTitle('History', sub: 'Performance and recorded trades'),
          Panel(
            title: app.canConvert ? 'PERFORMANCE · KES (CONVERTED)' : 'PERFORMANCE · ${app.activeCurrency ?? ''}',
            child: Column(children: [
              Row(children: [
                Expanded(child: Lcd('TRADES', '${s.total_trades}')), const SizedBox(width: 8),
                Expanded(child: Lcd('WIN RATE', rate, color: Pal.lime)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Lcd('WINS', '${s.wins}', color: Pal.green)), const SizedBox(width: 8),
                Expanded(child: Lcd('LOSSES', '${s.losses}', color: Pal.red)),
              ]),
              const SizedBox(height: 8),
              Lcd('NET P/L SINCE CLEARED', app.money(net, sign: true), color: net >= 0 ? Pal.green : Pal.red, size: 24,
                  sub: app.canConvert ? 'Native: ${app.nativeText(net)}' : null),
            ]),
          ),
          Panel(title: 'RECORDED TRADES', child: app.trades.isEmpty
              ? const Text('No trades recorded.', style: TextStyle(color: Pal.onDeepDim))
              : Column(children: [for (final t in app.trades.take(30)) _row(t)])),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Material(
                color: Pal.card, borderRadius: BorderRadius.circular(40),
                child: InkWell(
                  borderRadius: BorderRadius.circular(40), onTap: () => _confirmClear(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(40), border: Border.all(color: const Color(0xFFB3261E), width: 2)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.delete_sweep_outlined, color: Color(0xFFB3261E)), SizedBox(width: 8),
                      Text('CLEAR TRADE HISTORY', style: TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                    ]),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Text('Clears recorded trades, win/loss counts and performance numbers only. Strategy, recovery, martingale, risk limits, settings, account and any open trade are not touched.',
                    textAlign: TextAlign.center, style: TextStyle(color: Pal.inkDim, fontSize: 11)),
              ),
            ]),
          ),
          const CopyrightFooter(),
        ]);
      },
    );
  }

  Widget _row(Map<String, dynamic> t) {
    final profit = (t['profit'] as num).toDouble();
    final res = t['result'] as int;
    final c = res == 1 ? Pal.green : (res == 2 ? Pal.red : Pal.amber);
    final outcome = (t['outcome'] as num?)?.toInt() ?? -1;       // -1 = Deriv did not provide it
    final dir = t['direction'] == 0 ? 'OVER' : 'UNDER';
    final barrier = (t['barrier'] as num).toInt();
    // integrity hint only (never used to fill the digit): does the reported outcome agree with the reported result?
    bool? agrees;
    if (outcome >= 0 && (res == 1 || res == 2)) {
      final wouldWin = t['direction'] == 0 ? outcome > barrier : outcome < barrier;
      agrees = wouldWin == (res == 1);
    }
    const resNames = {1: 'WIN', 2: 'LOSS', 3: 'REJECTED', 4: 'UNCONFIRMED'};
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Led(c, size: 9), const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(style: kMono.copyWith(color: Pal.onDeep, fontSize: 13, fontWeight: FontWeight.w600), children: [
              TextSpan(text: '$dir $barrier'),
              const TextSpan(text: '  →  Outcome: ', style: TextStyle(color: Pal.onDeepDim, fontWeight: FontWeight.w400)),
              TextSpan(text: outcome >= 0 ? '$outcome' : '—', style: const TextStyle(color: Pal.lime, fontWeight: FontWeight.w800, fontSize: 15)),
              const TextSpan(text: '  →  ', style: TextStyle(color: Pal.onDeepDim, fontWeight: FontWeight.w400)),
              TextSpan(text: resNames[res] ?? '-', style: TextStyle(color: c, fontWeight: FontWeight.w800)),
              if (agrees == false) const TextSpan(text: '  ⚠', style: TextStyle(color: Pal.amber)),
            ])),
            const SizedBox(height: 2),
            Text('#${t['trade_id']}   trigger ${t['prev']}→${t['cur']}   R${t['recovery']} M${t['martingale']}',
                style: kMono.copyWith(color: Pal.onDeepDim, fontSize: 10.5)),
          ]),
        ),
        Text(app.money(profit, sign: true), style: kMono.copyWith(color: c, fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear trade history?'),
        content: const Text('This permanently clears recorded trades, win/loss records and performance statistics.\n\nStrategy, recovery, settings, account and live trading are NOT affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear', style: TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (ok == true) app.clearHistory();
  }
}
