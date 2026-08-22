import 'package:flutter/material.dart';

abstract final class AppColors {
  static const navy = Color(0xFF081222);
  static const navyLight = Color(0xFF14223A);
  static const purple = Color(0xFF7057F5);
  static const indigo = Color(0xFF4B63E8);
  static const pink = Color(0xFFE64F91);
  static const orange = Color(0xFFFF8A3D);
  static const emergency = Color(0xFFE5484D);
  static const safe = Color(0xFF1AA56F);
  static const warning = Color(0xFFF08A2B);
  static const text = Color(0xFF172033);
  static const textMuted = Color(0xFF6F7B8D);
  static const canvas = Color(0xFFF7F8FC);
  static const border = Color(0xFFE7EAF0);
}

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.canvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.purple,
      brightness: Brightness.light,
      primary: AppColors.purple,
      error: AppColors.emergency,
      surface: Colors.white,
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        color: AppColors.text,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -.5,
      ),
      titleLarge: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800),
      bodyMedium: TextStyle(color: AppColors.text, fontSize: 15, height: 1.4),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 19,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(color: AppColors.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
  );
}
