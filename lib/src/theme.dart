import 'package:flutter/material.dart';

/// Static light-mode tokens ("Field Instrument"). Kept for screens not yet
/// migrated to the theme-aware [AppPalette]; values mirror [AppPalette.light].
class AppColors {
  static const navy = Color(0xFF16294A); // brand / primary
  static const navyDark = Color(0xFF0E1E38);
  static const green = Color(0xFF177A43); // measurement / confirm / 존치
  static const ember = Color(0xFFC24A1E); // 불·심각도 accent
  static const danger = Color(0xFFC0271F); // 벌채 / 위험
  static const stemRed = Color(0xFFE03A3A); // 수간 overlay
  static const sootGreen = Color(0xFF35A853); // 그을음 overlay
  static const poleYellow = Color(0xFFF6C518); // 수고봉
  static const bg = Color(0xFFF3F6FA);
  static const surface2 = Color(0xFFEDF1F6);
  static const card = Colors.white;
  static const textPrimary = Color(0xFF0E1726);
  static const textSecondary = Color(0xFF5A6A80);
  static const border = Color(0xFFD9DFE8);
}

/// Theme-aware design tokens. Adapts between light ("현장") and dark ("저조도").
/// Read with `Theme.of(context).extension<AppPalette>()!` (or `context.palette`).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color navy, onNavy, green, ember, danger;
  final Color ink, muted, line, surface, surface2, bg, field;
  final Color stem, soot, pole; // domain overlay — constant across themes

  const AppPalette({
    required this.navy,
    required this.onNavy,
    required this.green,
    required this.ember,
    required this.danger,
    required this.ink,
    required this.muted,
    required this.line,
    required this.surface,
    required this.surface2,
    required this.bg,
    required this.field,
    required this.stem,
    required this.soot,
    required this.pole,
  });

  static const light = AppPalette(
    navy: Color(0xFF16294A),
    onNavy: Colors.white,
    green: Color(0xFF177A43),
    ember: Color(0xFFC24A1E),
    danger: Color(0xFFC0271F),
    ink: Color(0xFF0E1726),
    muted: Color(0xFF5A6A80),
    line: Color(0xFFD9DFE8),
    surface: Colors.white,
    surface2: Color(0xFFEDF1F6),
    bg: Color(0xFFF3F6FA),
    field: Color(0xFFE9EFE7),
    stem: Color(0xFFE03A3A),
    soot: Color(0xFF35A853),
    pole: Color(0xFFF6C518),
  );

  static const dark = AppPalette(
    navy: Color(0xFF9CBBEA),
    onNavy: Color(0xFF0B1420),
    green: Color(0xFF4FC27C),
    ember: Color(0xFFF0824B),
    danger: Color(0xFFF06B63),
    ink: Color(0xFFE8EDF4),
    muted: Color(0xFF9AA9BD),
    line: Color(0xFF28374F),
    surface: Color(0xFF14202F),
    surface2: Color(0xFF1B2A3D),
    bg: Color(0xFF0B1420),
    field: Color(0xFF182A22),
    stem: Color(0xFFE03A3A),
    soot: Color(0xFF35A853),
    pole: Color(0xFFF6C518),
  );

  @override
  AppPalette copyWith({
    Color? navy,
    Color? onNavy,
    Color? green,
    Color? ember,
    Color? danger,
    Color? ink,
    Color? muted,
    Color? line,
    Color? surface,
    Color? surface2,
    Color? bg,
    Color? field,
    Color? stem,
    Color? soot,
    Color? pole,
  }) =>
      AppPalette(
        navy: navy ?? this.navy,
        onNavy: onNavy ?? this.onNavy,
        green: green ?? this.green,
        ember: ember ?? this.ember,
        danger: danger ?? this.danger,
        ink: ink ?? this.ink,
        muted: muted ?? this.muted,
        line: line ?? this.line,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        bg: bg ?? this.bg,
        field: field ?? this.field,
        stem: stem ?? this.stem,
        soot: soot ?? this.soot,
        pole: pole ?? this.pole,
      );

  // Theme switch is instantaneous; snapping avoids 15 per-frame color lerps.
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) =>
      (other is AppPalette && t >= 0.5) ? other : this;
}

extension PaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light, AppPalette.light);
  static ThemeData dark() => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette p) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Pretendard',
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF16294A),
      brightness: brightness,
    ).copyWith(
      primary: p.navy,
      onPrimary: p.onNavy,
      secondary: p.green,
      surface: p.surface,
      onSurface: p.ink,
      error: p.danger,
    );
    return base.copyWith(
      scaffoldBackgroundColor: p.bg,
      colorScheme: scheme,
      extensions: [p],
      dividerColor: p.line,
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      textTheme: base.textTheme.apply(
        fontFamily: 'Pretendard',
        bodyColor: p.ink,
        displayColor: p.ink,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Pretendard',
          color: p.ink,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.line),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: p.line, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: p.line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: p.navy, width: 1.5),
        ),
        hintStyle: TextStyle(color: p.muted.withValues(alpha: 0.75)),
        labelStyle: TextStyle(color: p.muted, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.navy,
          foregroundColor: p.onNavy,
          disabledBackgroundColor: p.line,
          disabledForegroundColor: p.muted,
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(
              fontFamily: 'Pretendard', fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.navy,
          minimumSize: const Size.fromHeight(54),
          side: BorderSide(color: p.navy, width: 1.5),
          textStyle: const TextStyle(
              fontFamily: 'Pretendard', fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.muted,
          textStyle: const TextStyle(
              fontFamily: 'Pretendard', fontSize: 14, fontWeight: FontWeight.w600),
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

  /// Compass heading in degrees (N=0, E=90, S=180, W=270).
  int get heading => switch (this) {
        Azimuth.north => 0,
        Azimuth.east => 90,
        Azimuth.south => 180,
        Azimuth.west => 270,
      };
}
