import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../core/theme.dart';
import '../models/system_info.dart';
import '../providers/dashboard_provider.dart';
import '../services/system_monitor.dart';
import '../widgets/usage_gauge.dart';

/// Main monitoring dashboard with two-column layout.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        title: const Row(
          children: [
            Icon(Icons.monitor_heart, size: 18),
            SizedBox(width: 8),
            Text('System Monitor', style: TextStyle(fontSize: 14)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.minimize, size: 18),
            tooltip: 'Hide to tray',
            onPressed: () => windowManager.hide(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Refresh',
            onPressed: () =>
                context.read<DashboardProvider>().refresh(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, p, _) => _body(context, p),
      ),
    );
  }

  Widget _body(BuildContext context, DashboardProvider p) {
    if (p.isLoading && p.data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (p.hasError && p.data == null) {
      return _errorView(context, p);
    }

    final info = p.data!;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Row 1: CPU | Memory ──
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _cpuCard(context, info.cpu, theme)),
                const SizedBox(width: 12),
                Expanded(child: _memoryCard(context, info.memory, theme)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Disks Section ──
          _sectionLabel(context, Icons.disc_full, 'Disks',
              info.disks.isNotEmpty
                  ? AppTheme.usageColor(info.disks.first.usagePercent)
                  : null),
          const SizedBox(height: 8),
          if (info.disks.isEmpty)
            _emptyHint(context, 'No disks detected')
          else
            ...info.disks.map(
              (d) => _diskCard(
                context,
                d,
                theme,
                key: ValueKey('disk_${d.mountPoint}'),
              ),
            ),

          // ── Network Section ──
          if (info.networks.isNotEmpty) ...[
            const SizedBox(height: 14),
            _sectionLabel(context, Icons.wifi, 'Network', null),
            const SizedBox(height: 8),
            ...info.networks.map(
              (n) => _networkCard(
                context,
                n,
                theme,
                key: ValueKey('net_${n.interfaceName}'),
              ),
            ),
          ],

          // ── Footer ──
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Auto-refresh every 3s  •  '
              '${DateTime.now().toString().substring(0, 16)}',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.outline,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Error view
  // ═══════════════════════════════════════════════════════════════

  Widget _errorView(BuildContext context, DashboardProvider p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 56, color: Colors.redAccent.withAlpha(180)),
            const SizedBox(height: 16),
            Text(p.errorMessage ?? 'Unknown error',
                style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => p.refresh(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Section label
  // ═══════════════════════════════════════════════════════════════

  Widget _sectionLabel(
      BuildContext context, IconData icon, String title, Color? accent) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 15,
              color: accent ?? Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withAlpha(200),
                letterSpacing: 0.4,
              )),
        ],
      ),
    );
  }

  Widget _emptyHint(BuildContext context, String msg) {
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withAlpha(80),
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(msg,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              )),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CPU Card
  // ═══════════════════════════════════════════════════════════════

  Widget _cpuCard(BuildContext context, CpuInfo cpu, ThemeData theme) {
    final color = AppTheme.usageColor(cpu.usagePercent);
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.memory, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('CPU',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withAlpha(180),
                        letterSpacing: 0.4,
                      )),
                ),
                Text('${cpu.usagePercent.toInt()}%',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: color,
                    )),
              ],
            ),
            const SizedBox(height: 12),
            // Gauge + info
            Row(
              children: [
                UsageGauge(percent: cpu.usagePercent, size: 64),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${cpu.cores} cores',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface,
                          )),
                      const SizedBox(height: 4),
                      Text(_cpuModelShort(cpu.model),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.outline,
                            height: 1.3,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _cpuModelShort(String model) {
    // Strip common prefixes to keep it compact
    return model
        .replaceFirst(RegExp(r'^(Intel|AMD)\s+'), '')
        .replaceAll(RegExp(r'\s+CPU\s*@.*$'), '')
        .replaceAll(RegExp(r'\s+Processor\s*$'), '')
        .trim();
  }

  // ═══════════════════════════════════════════════════════════════
  // Memory Card
  // ═══════════════════════════════════════════════════════════════

  Widget _memoryCard(BuildContext context, MemoryInfo mem, ThemeData theme) {
    final color = AppTheme.usageColor(mem.usagePercent);
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.sd_storage, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Memory',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withAlpha(180),
                        letterSpacing: 0.4,
                      )),
                ),
                Text('${mem.usagePercent.toInt()}%',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: color,
                    )),
              ],
            ),
            const SizedBox(height: 12),
            // Gauge + details
            Row(
              children: [
                UsageGauge(percent: mem.usagePercent, size: 64),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _statRow(context, 'Used', SystemMonitor.formatKb(mem.usedKb), color),
                      const SizedBox(height: 5),
                      _statRow(context, 'Total', SystemMonitor.formatKb(mem.totalKb), null),
                      const SizedBox(height: 5),
                      _statRow(context, 'Free', SystemMonitor.formatKb(mem.availableKb), Colors.green),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(
      BuildContext context, String label, String value, Color? valueColor) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(label,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.outline,
              )),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                color: valueColor ?? theme.colorScheme.onSurface,
              )),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Disk Card
  // ═══════════════════════════════════════════════════════════════

  Widget _diskCard(BuildContext context, DiskInfo disk, ThemeData theme,
      {Key? key}) {
    final color = disk.total != 'N/A'
        ? AppTheme.usageColor(disk.usagePercent)
        : Colors.grey;
    final isNa = disk.total == 'N/A';

    return Card(
      key: key,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.folder_outlined, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(disk.mountPoint,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      )),
                ),
                if (!isNa)
                  Text('${disk.usagePercent.toInt()}%',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color,
                      )),
              ],
            ),
            if (!isNa) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('${disk.used} / ${disk.total}',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.outline,
                      )),
                  const Spacer(),
                  Text('free ${disk.available}',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.green.withAlpha(200),
                      )),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: disk.usagePercent / 100,
                  minHeight: 5,
                  backgroundColor: color.withAlpha(25),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Network Card
  // ═══════════════════════════════════════════════════════════════

  Widget _networkCard(BuildContext context, NetworkInfo net, ThemeData theme,
      {Key? key}) {
    return Card(
      key: key,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lan, size: 16),
                const SizedBox(width: 8),
                Text(net.interfaceName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    )),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _netStat(context, 'Download', SystemMonitor.formatBytes(net.rxBytes),
                      Icons.arrow_downward, Colors.blue),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _netStat(context, 'Upload', SystemMonitor.formatBytes(net.txBytes),
                      Icons.arrow_upward, Colors.orange),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _netStat(BuildContext context, String label, String value,
      IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.outline,
                    )),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
