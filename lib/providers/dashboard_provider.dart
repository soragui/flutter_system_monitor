import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/system_info.dart';
import '../services/system_monitor.dart';

/// Application state for the dashboard.
///
/// Owns a [SystemMonitor] instance and exposes the latest [SystemInfo]
/// via a periodic polling timer.
class DashboardProvider extends ChangeNotifier {
  final SystemMonitor _monitor = SystemMonitor();

  SystemInfo? _data;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  SystemInfo? get data => _data;
  bool get isLoading => _loading;
  bool get hasError => _error != null;
  String? get errorMessage => _error;

  /// Start auto-refreshing every [interval] seconds.
  void start({Duration interval = const Duration(seconds: 3)}) {
    _refresh();
    _timer = Timer.periodic(interval, (_) => _refresh());
  }

  /// Manually refresh data now.
  Future<void> refresh() => _refresh();

  Future<void> _refresh() async {
    try {
      final info = await _monitor.fetchAll();
      _data = info;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// CPU/MEM summary string for tray title.
  String get trayTitle {
    if (_data == null) return 'System Monitor';
    return 'CPU${_data!.cpu.usagePercent.toInt()}% '
        'MEM${_data!.memory.usagePercent.toInt()}%';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
