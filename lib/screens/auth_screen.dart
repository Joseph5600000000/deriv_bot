import 'package:flutter/material.dart';
import '../state/app_controller.dart';
import '../widgets/panel.dart';

/// Screen 1. Nothing else in the app is reachable until a PAT validates against Deriv.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.app});
  final AppController app;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _ctl = TextEditingController();
  late final TextEditingController _app = TextEditingController(text: widget.app.appId);
  bool _hide = true;

  @override
  Widget build(BuildContext context) {
    final a = widget.app;
    final busy = a.phase == Phase.authenticating || a.phase == Phase.booting;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Panel(
              title: 'PERSONAL ACCESS TOKEN',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Paste the PAT generated in your Deriv account (scopes: trade).', style: TextStyle(color: Pal.dim, fontSize: 12)),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctl, obscureText: _hide, enabled: !busy, autocorrect: false, enableSuggestions: false,
                  style: kMono.copyWith(color: Pal.text),
                  decoration: InputDecoration(
                    hintText: '[ Paste Personal Access Token ]', filled: true, fillColor: Pal.lcd,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hide = !_hide)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _app, enabled: !busy, autocorrect: false, enableSuggestions: false,
                  style: kMono.copyWith(color: Pal.text, fontSize: 13),
                  decoration: InputDecoration(labelText: 'Deriv App ID (PAT app)', isDense: true, filled: true, fillColor: Pal.lcd,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6))),
                ),
                const SizedBox(height: 12),
                if (a.loginErrorTitle != null) Container(
                  padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: const Color(0x33FF4D5E), borderRadius: BorderRadius.circular(6), border: Border.all(color: Pal.red)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.loginErrorTitle!, style: const TextStyle(color: Pal.red, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(a.loginErrorBody ?? '', style: const TextStyle(color: Pal.text, fontSize: 12)),
                    if (a.loginErrorTech != null) Padding(padding: const EdgeInsets.only(top: 6),
                        child: Text(a.loginErrorTech!, style: kMono.copyWith(color: Pal.dim, fontSize: 10))),
                  ]),
                ),
                MetalButton(busy ? 'CONNECTING…' : 'CONNECT', filled: true, color: Pal.green,
                    onTap: busy ? null : () { final t = _ctl.text; _ctl.clear(); a.submitPat(t, _app.text); }),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() { _ctl.dispose(); _app.dispose(); super.dispose(); }
}
