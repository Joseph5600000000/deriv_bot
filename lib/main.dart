import 'dart:async';
import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';
import 'state/app_controller.dart';
import 'widgets/panel.dart';

final AppController app = AppController();

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // In release mode Flutter shows a blank grey screen for UI errors. Show the real error instead.
    ErrorWidget.builder = (d) => Material(
          color: const Color(0xFF260000),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                'UI ERROR (send me a screenshot)\n\n${d.exceptionAsString()}\n\n${(d.stack?.toString() ?? '').split('\n').take(10).join('\n')}',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ),
        );
    app.boot();
    runApp(const DerivBotApp());
  }, (e, s) => app.fatal('$e\n${s.toString().split('\n').take(4).join('\n')}'));
}

class DerivBotApp extends StatelessWidget {
  const DerivBotApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Deriv Digit Bot', debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(scaffoldBackgroundColor: Pal.bg, canvasColor: Pal.bg),
        home: ListenableBuilder(
          listenable: app,
          builder: (context, _) => app.phase == Phase.ready ? DashboardScreen(app: app) : AuthScreen(app: app),
        ),
      );
}
