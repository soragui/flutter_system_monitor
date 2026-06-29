import 'dart:io';
import '../models/system_info.dart';

/// Low-level system data fetcher. Reads /proc and runs shell commands.
class SystemMonitor {
  String _cpuModel = '';

  // ── Public API ──────────────────────────────────────────────

  Future<SystemInfo> fetchAll() async {
    final results = await Future.wait([
      _fetchCpu(),
      _fetchMemory(),
      _fetchDisks(),
      _fetchNetworks(),
    ]);
    return SystemInfo(
      cpu: results[0] as CpuInfo,
      memory: results[1] as MemoryInfo,
      disks: results[2] as List<DiskInfo>,
      networks: results[3] as List<NetworkInfo>,
    );
  }

  // ── Formatting helpers ──────────────────────────────────────

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String formatKb(int kb) {
    if (kb < 1024) return '$kb KB';
    if (kb < 1024 * 1024) return '${(kb / 1024).toStringAsFixed(1)} MB';
    return '${(kb / (1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // ── CPU ─────────────────────────────────────────────────────

  Future<CpuInfo> _fetchCpu() async {
    await _ensureCpuModel();

    final t1 = await _readCpuTimes();
    await Future.delayed(const Duration(milliseconds: 200));
    final t2 = await _readCpuTimes();

    if (t1.isEmpty || t2.isEmpty || t1.length < 4 || t2.length < 4) {
      return CpuInfo(usagePercent: 0, cores: _cores, model: _cpuModel);
    }

    final idle1 = t1[3] + (t1.length > 4 ? t1[4] : 0);
    final total1 = t1.fold<int>(0, (a, b) => a + b);
    final idle2 = t2[3] + (t2.length > 4 ? t2[4] : 0);
    final total2 = t2.fold<int>(0, (a, b) => a + b);

    final totalDelta = total2 - total1;
    if (totalDelta == 0) {
      return CpuInfo(usagePercent: 0, cores: _cores, model: _cpuModel);
    }

    final pct = ((totalDelta - (idle2 - idle1)) / totalDelta * 100).clamp(0, 100);
    return CpuInfo(
      usagePercent: double.parse(pct.toStringAsFixed(1)),
      cores: _cores,
      model: _cpuModel,
    );
  }

  Future<void> _ensureCpuModel() async {
    if (_cpuModel.isNotEmpty) return;
    // Try /proc/cpuinfo
    for (final line in (await _read('/proc/cpuinfo')).split('\n')) {
      if (line.startsWith('model name')) {
        _cpuModel = line.split(':').last.trim();
        return;
      }
    }
    // Fallback: lscpu
    try {
      final r = await Process.run('lscpu', []);
      for (final line in (r.stdout as String).split('\n')) {
        if (line.startsWith('Model name:')) {
          _cpuModel = line.split(':').last.trim();
          return;
        }
      }
    } catch (_) {}
    _cpuModel = 'Unknown CPU';
  }

  Future<List<int>> _readCpuTimes() async {
    final stat = await _read('/proc/stat');
    final cpuLine = stat
        .split('\n')
        .firstWhere((l) => l.startsWith('cpu '), orElse: () => '');
    if (cpuLine.isEmpty) return [];
    return cpuLine
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList()
        .sublist(1)
        .map(int.parse)
        .toList();
  }

  int get _cores => Platform.numberOfProcessors;

  // ── Memory ──────────────────────────────────────────────────

  Future<MemoryInfo> _fetchMemory() async {
    final text = await _read('/proc/meminfo');

    int extract(String key) {
      final line = text
          .split('\n')
          .firstWhere((l) => l.startsWith(key), orElse: () => '$key: 0 kB');
      final m = RegExp(r'(\d+)').firstMatch(line);
      return m != null ? int.parse(m.group(1)!) : 0;
    }

    final total = extract('MemTotal');
    final available = extract('MemAvailable');
    final free = extract('MemFree');
    final buffers = extract('Buffers');
    final cached = extract('Cached');
    final sReclaimable = extract('SReclaimable');

    final avail = available > 0
        ? available
        : free + buffers + cached + sReclaimable;
    final used = total - avail;
    final pct = total > 0 ? (used / total * 100).clamp(0, 100) : 0.0;

    return MemoryInfo(
      totalKb: total,
      usedKb: used,
      availableKb: avail,
      usagePercent: double.parse(pct.toStringAsFixed(1)),
    );
  }

  // ── Disk ────────────────────────────────────────────────────

  Future<List<DiskInfo>> _fetchDisks() async {
    try {
      final result = await Process.run('df', ['-h']);
      final lines = (result.stdout as String).split('\n');

      return lines
          .skip(1)
          .map((line) => line.split(RegExp(r'\s+')))
          .where((p) => p.length >= 6 && p[0].startsWith('/'))
          .map((p) {
            final pct = double.tryParse(p[4].replaceAll('%', '')) ?? 0;
            return DiskInfo(
              mountPoint: p[5],
              total: p[1],
              used: p[2],
              available: p[3],
              usagePercent: pct,
            );
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Network ─────────────────────────────────────────────────

  Future<List<NetworkInfo>> _fetchNetworks() async {
    try {
      final text = await _read('/proc/net/dev');
      return text
          .split('\n')
          .where((l) => l.contains(':'))
          .map((l) => l.trim().split(RegExp(r'\s+')))
          .where((p) => p[0].replaceAll(':', '') != 'lo')
          .map((p) {
            final rx = int.tryParse(p[1]) ?? 0;
            final tx = int.tryParse(p[9]) ?? 0;
            if (rx == 0 && tx == 0) return null;
            return NetworkInfo(
              interfaceName: p[0].replaceAll(':', ''),
              rxBytes: rx,
              txBytes: tx,
            );
          })
          .whereType<NetworkInfo>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Helpers ─────────────────────────────────────────────────

  Future<String> _read(String path) async {
    try {
      return await File(path).readAsString();
    } catch (_) {
      return '';
    }
  }
}
