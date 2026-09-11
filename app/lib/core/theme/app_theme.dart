import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData fromBranding({
    required Color primary,
    required Color secondary,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      surface: secondary,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      fontFamily: 'Segoe UI',
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }

  static Color parseHex(String value, Color fallback) {
    var hex = value.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) {
      return fallback;
    }
    return Color(parsed);
  }
}
