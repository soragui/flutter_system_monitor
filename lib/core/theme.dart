import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1565C0),
        brightness: Brightness.dark,
      );

  /// Returns a color based on usage percentage: green → orange → red
  static Color usageColor(double percent) {
    if (percent < 50) return Colors.green;
    if (percent < 75) return Colors.orange;
    if (percent < 90) return Colors.deepOrange;
    return Colors.red;
  }
}
