import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme.dart';
import 'providers/dashboard_provider.dart';
import 'screens/dashboard_screen.dart';

/// Application shell: tray icon, window management, global providers.
class SysMonitorShell extends StatefulWidget {
  const SysMonitorShell({super.key});

  @override
  State<SysMonitorShell> createState() => _SysMonitorShellState();
}

class _SysMonitorShellState extends State<SysMonitorShell>
    with TrayListener, WindowListener {
  late final DashboardProvider _provider;
  String _lastTrayTitle = '';
  bool _trayTitlePending = false;

  @override
  void initState() {
    super.initState();
    _provider = DashboardProvider();
    _provider.addListener(_onProviderChanged);
    _provider.start();

    trayManager.addListener(this);
    windowManager.addListener(this);
    _initTray();
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    _provider.dispose();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  // ── Provider listener ───────────────────────────────────────

  void _onProviderChanged() {
    final title = _provider.trayTitle;
    if (title == _lastTrayTitle || _trayTitlePending) return;

    _trayTitlePending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _trayTitlePending = false;
      _lastTrayTitle = title;
      try {
        trayManager.setTitle(title);
      } catch (_) {}
    });
  }

  // ── Tray setup ──────────────────────────────────────────────

  Future<void> _initTray() async {
    try {
      await trayManager.setIcon('assets/tray_icon.png');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'dashboard', label: 'Dashboard'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'Exit'),
      ]));
    } catch (e) {
      debugPrint('Tray init: $e');
    }
  }

  // ── Window events ───────────────────────────────────────────

  @override
  void onWindowClose() => windowManager.hide();

  // ── Tray events ─────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() => _showDashboard();

  @override
  void onTrayMenuItemClick(MenuItem item) {
    switch (item.key) {
      case 'dashboard':
        _showDashboard();
      case 'exit':
        trayManager.destroy();
        exit(0);
    }
  }

  Future<void> _showDashboard() async {
    await windowManager.show();
    await windowManager.focus();
    _provider.refresh();
  }

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const DashboardScreen(),
      ),
    );
  }
}
