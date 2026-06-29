import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Circular + linear progress gauge for usage percentages.
class UsageGauge extends StatelessWidget {
  final double percent;
  final double size;

  const UsageGauge({super.key, required this.percent, this.size = 50});

  Color get _color => AppTheme.usageColor(percent);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: percent / 100,
                strokeWidth: 4.5,
                backgroundColor: _color.withAlpha(35),
                valueColor: AlwaysStoppedAnimation(_color),
              ),
              Center(
                child: Text('${percent.toInt()}%',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _color)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Bar(percent: percent, color: _color, width: size),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double percent;
  final Color color;
  final double width;
  const _Bar({required this.percent, required this.color, required this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: percent / 100,
          minHeight: 4,
          backgroundColor: color.withAlpha(30),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}
