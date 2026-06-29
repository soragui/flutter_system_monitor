import 'package:flutter/material.dart';
import '../models/system_info.dart';
import 'usage_gauge.dart';

class CpuCard extends StatelessWidget {
  final CpuInfo cpu;
  const CpuCard({super.key, required this.cpu});

  @override
  Widget build(BuildContext context) {
    final name = cpu.model.length > 70
        ? '${cpu.model.substring(0, 67)}...'
        : cpu.model;

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 10),
            Row(
              children: [
                UsageGauge(percent: cpu.usagePercent),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Usage: ${cpu.usagePercent}%',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cores: ${cpu.cores}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
