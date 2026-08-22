import 'package:flutter/material.dart';

abstract final class AppColors {
  static const navy = Color(0xFF091426);
  static const navyLight = Color(0xFF12233D);
  static const purple = Color(0xFF7657FF);
  static const emergency = Color(0xFFE33D4E);
  static const safe = Color(0xFF1E9E6A);
  static const warning = Color(0xFFF39B32);
  static const textMuted = Color(0xFF9BAAC0);
}

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.navy,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.purple,
      secondary: AppColors.purple,
      error: AppColors.emergency,
      surface: AppColors.navyLight,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.navyLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
