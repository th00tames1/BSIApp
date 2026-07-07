import 'package:flutter/material.dart';

/// Design tokens taken from the client mock-ups (착수보고 v6).
class AppColors {
  static const navy = Color(0xFF1B2E4F); // primary buttons, headers
  static const navyDark = Color(0xFF16233F);
  static const green = Color(0xFF2E9E4F); // accents, selected nav, success
  static const greenLight = Color(0xFF4CAF50);
  static const stemRed = Color(0xFFE03A3A); // 수간 영역 overlay
  static const sootGreen = Color(0xFF35A853); // 그을음 영역 overlay
  static const poleYellow = Color(0xFFF6C518); // 수고봉
  static const bg = Color(0xFFF5F6F8);
  static const card = Colors.white;
  static const textPrimary = Color(0xFF1A1D23);
  static const textSecondary = Color(0xFF6B7280);
  static const border = Color(0xFFDDE1E7);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.navy,
        secondary: AppColors.green,
        surface: AppColors.card,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
            color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 1.5,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: AppColors.navy, width: 1.4),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

/// Azimuth enum shared across capture/result.
enum Azimuth { east, west, south, north }

extension AzimuthKo on Azimuth {
  String get ko => switch (this) {
        Azimuth.east => '동',
        Azimuth.west => '서',
        Azimuth.south => '남',
        Azimuth.north => '북',
      };
  String get code => switch (this) {
        Azimuth.east => 'E',
        Azimuth.west => 'W',
        Azimuth.south => 'S',
        Azimuth.north => 'N',
      };
}
