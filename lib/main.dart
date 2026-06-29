import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  await windowManager.setTitle('System Monitor');
  await windowManager.setSize(const Size(420, 620));
  await windowManager.center();
  await windowManager.show();

  runApp(const SysMonitorShell());
}
