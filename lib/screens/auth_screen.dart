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
      backgroundColor: Pal.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/branding/logo.png', width: 52, height: 52)),
                  const SizedBox(width: 12),
                  const Text('DeltaDesk', style: TextStyle(color: Pal.ink, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 4),
                child: Text('Connect your\nDeriv account.', style: TextStyle(color: Pal.ink, fontSize: 40, fontWeight: FontWeight.w800, height: 1.05, letterSpacing: -1)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 6, 24, 10),
                child: Text('Paste a Personal Access Token with the trade scope. Nothing is shown until Deriv accepts it.', style: TextStyle(color: Pal.inkDim, fontSize: 14)),
              ),
              Panel(
                title: 'PERSONAL ACCESS TOKEN',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextField(
                    controller: _ctl, obscureText: _hide, enabled: !busy, autocorrect: false, enableSuggestions: false,
                    style: kMono.copyWith(color: Pal.onDeep),
                    decoration: fieldDecoration('Personal Access Token', hint: '[ Paste Personal Access Token ]',
                        suffix: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off, color: Pal.onDeepDim), onPressed: () => setState(() => _hide = !_hide))),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: _app, enabled: !busy, autocorrect: false, enableSuggestions: false, style: kMono.copyWith(color: Pal.onDeep, fontSize: 13),
                      decoration: fieldDecoration('Deriv App ID (PAT app)')),
                  const SizedBox(height: 12),
                  if (a.loginErrorTitle != null)
                    Container(
                      padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: const Color(0x33FF8F85), borderRadius: BorderRadius.circular(16)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.loginErrorTitle!, style: const TextStyle(color: Pal.red, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(a.loginErrorBody ?? '', style: const TextStyle(color: Pal.onDeep, fontSize: 12)),
                        if (a.loginErrorTech != null)
                          Padding(padding: const EdgeInsets.only(top: 6), child: Text(a.loginErrorTech!, style: kMono.copyWith(color: Pal.onDeepDim, fontSize: 10))),
                      ]),
                    ),
                  MetalButton(busy ? 'CONNECTING…' : 'CONNECT', filled: true,
                      onTap: busy ? null : () { final t = _ctl.text; _ctl.clear(); a.submitPat(t, _app.text); }),
                ]),
              ),
              const CopyrightFooter(),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() { _ctl.dispose(); _app.dispose(); super.dispose(); }
}
