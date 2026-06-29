import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/system_info.dart';

class DiskCard extends StatelessWidget {
  final DiskInfo disk;
  const DiskCard({super.key, required this.disk});

  Color get _color =>
      disk.total != 'N/A' ? AppTheme.usageColor(disk.usagePercent) : Colors.grey;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.folder_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(disk.mountPoint,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                ),
                if (disk.total != 'N/A')
                  Text('${disk.usagePercent.toInt()}%',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _color)),
              ],
            ),
            if (disk.total != 'N/A') ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('${disk.used} / ${disk.total}',
                      style: _muted(context)),
                  const Spacer(),
                  Text('free ${disk.available}', style: _muted(context)),
                ],
              ),
              const SizedBox(height: 8),
              _bar(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: disk.usagePercent / 100,
        minHeight: 4,
        backgroundColor: _color.withAlpha(30),
        valueColor: AlwaysStoppedAnimation(_color),
      ),
    );
  }

  TextStyle _muted(BuildContext context) => TextStyle(
      fontSize: 11, color: Theme.of(context).colorScheme.outline);
}
