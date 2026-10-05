import 'package:flutter/material.dart';
import '../state/app_controller.dart';
import '../widgets/panel.dart';
import 'config_screen.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

/// Bottom-navigation shell. Each tab keeps its state (IndexedStack).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.app});
  final AppController app;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;
  @override
  Widget build(BuildContext context) {
    final a = widget.app;
    return Scaffold(
      backgroundColor: Pal.bg,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _i, children: [DashboardScreen(app: a), ConfigScreen(app: a), HistoryScreen(app: a), SettingsScreen(app: a)]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i, onDestinationSelected: (i) => setState(() => _i = i),
        backgroundColor: Pal.card, indicatorColor: Pal.lime, height: 68,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.candlestick_chart_outlined), selectedIcon: Icon(Icons.candlestick_chart), label: 'Trade'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Strategy'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
