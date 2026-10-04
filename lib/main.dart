import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';
import 'state/app_controller.dart';
import 'widgets/panel.dart';

final AppController app = AppController();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  app.boot();
  runApp(const DerivBotApp());
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
