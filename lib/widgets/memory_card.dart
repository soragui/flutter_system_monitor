import 'package:flutter/material.dart';
import '../models/system_info.dart';
import '../services/system_monitor.dart';
import 'usage_gauge.dart';

class MemoryCard extends StatelessWidget {
  final MemoryInfo mem;
  const MemoryCard({super.key, required this.mem});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            UsageGauge(percent: mem.usagePercent),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(context, 'Used', SystemMonitor.formatKb(mem.usedKb)),
                  const SizedBox(height: 3),
                  _row(context, 'Total', SystemMonitor.formatKb(mem.totalKb)),
                  const SizedBox(height: 3),
                  _row(context, 'Avail', SystemMonitor.formatKb(mem.availableKb)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 38,
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline)),
        ),
        Text(value,
            style:
                const TextStyle(fontSize: 11, fontFamily: 'monospace')),
      ],
    );
  }
}
