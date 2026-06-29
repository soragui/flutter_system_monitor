import 'package:flutter/material.dart';
import '../models/system_info.dart';
import '../services/system_monitor.dart';

class NetworkCard extends StatelessWidget {
  final NetworkInfo net;
  const NetworkCard({super.key, required this.net});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lan, size: 16),
                const SizedBox(width: 8),
                Text(net.interfaceName,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _stat(context, '↓ RX',
                      SystemMonitor.formatBytes(net.rxBytes)),
                ),
                Expanded(
                  child: _stat(context, '↑ TX',
                      SystemMonitor.formatBytes(net.txBytes)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.outline)),
        Text(value,
            style:
                const TextStyle(fontSize: 11, fontFamily: 'monospace')),
      ],
    );
  }
}
