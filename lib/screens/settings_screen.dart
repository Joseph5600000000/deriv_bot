import 'package:flutter/material.dart';
import '../state/app_controller.dart';
import '../widgets/panel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.app});
  final AppController app;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _rate = TextEditingController(text: widget.app.kesRate.toStringAsFixed(2));
  AppController get a => widget.app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) => ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        const ScreenTitle('Settings'),
        Panel(
          title: 'CURRENCY VIEW',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Show balances and P/L in', style: TextStyle(color: Pal.onDeep, fontSize: 14))),
              Segmented(options: const ['USD', 'KES'], value: a.kesView ? 1 : 0, onChanged: (i) => a.setKesView(i == 1)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: kMono.copyWith(color: Pal.onDeep),
              decoration: fieldDecoration('KES per 1 USD (you set this)', suffix: IconButton(
                icon: const Icon(Icons.check, color: Pal.lime),
                onPressed: () {
                  final r = double.tryParse(_rate.text.trim().replaceAll(',', '.'));
                  if (r == null || r <= 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid rate'))); return; }
                  a.setKesRate(r); FocusScope.of(context).unfocus();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rate saved: 1 USD = ${r.toStringAsFixed(2)} KES')));
                })),
            ),
            const SizedBox(height: 10),
            const Text('Display only. The rate is not fetched live, so set it to a current rate. Your Deriv account currency, stake and trade execution never change. Only USD accounts are converted.',
                style: TextStyle(color: Pal.onDeepDim, fontSize: 11)),
          ]),
        ),
        Panel(
          title: 'ACCOUNT & SECURITY',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Token: ${a.maskedPat ?? 'stored securely on this device'}', style: kMono.copyWith(color: Pal.onDeep, fontSize: 13)),
            const SizedBox(height: 4),
            Text('App ID: ${a.appId}', style: kMono.copyWith(color: Pal.onDeepDim, fontSize: 11)),
            const SizedBox(height: 12),
            MetalButton('DISCONNECT / REMOVE PAT', filled: true, color: Pal.red, onTap: () => _confirmLogout(context)),
          ]),
        ),
        Panel(
          title: 'ABOUT',
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/branding/logo.png', width: 44, height: 44)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('DeltaDesk', style: TextStyle(color: Pal.onDeep, fontWeight: FontWeight.w800, fontSize: 16)),
              Text('Version 1.3.0', style: TextStyle(color: Pal.onDeepDim, fontSize: 11)),
            ])),
          ]),
        ),
        const CopyrightFooter(),
      ]),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Disconnect / Remove PAT'),
      content: const Text('Trading stops and the stored token is deleted from this device.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove'))]));
    if (ok == true) a.disconnect();
  }

  @override
  void dispose() { _rate.dispose(); super.dispose(); }
}
