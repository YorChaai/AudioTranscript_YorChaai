import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ThemePreset {
  final String key;
  final String displayName;
  final String description;
  final Color primary;
  final Color accent;
  final Color background;
  final Color cardBackground;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final bool isDark;
  final List<Color> previewSwatches;

  const ThemePreset({
    required this.key,
    required this.displayName,
    required this.description,
    required this.primary,
    required this.accent,
    required this.background,
    required this.cardBackground,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.isDark,
    required this.previewSwatches,
  });

  ThemeData toThemeData() {
    final textTheme = isDark
        ? GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
        : GoogleFonts.interTextTheme(ThemeData.light().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      cardColor: cardBackground,
      dividerColor: divider,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: primary,
        onPrimary: Colors.white,
        secondary: accent,
        onSecondary: Colors.black,
        error: const Color(0xFFFF5252),
        onError: Colors.white,
        surface: cardBackground,
        onSurface: textPrimary,
      ),
      textTheme: textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: cardBackground,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: cardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: divider, width: 1),
        ),
      ),
    );
  }
}

class AppThemePresets {
  static const String defaultKey = 'cyber_blue';

  static const List<ThemePreset> all = [
    ThemePreset(
      key: 'cyber_blue',
      displayName: 'Cyber Blue (Default)',
      description: 'Futuristic slate dark with glowing blue and cyan accents',
      primary: Color(0xFF2979FF),
      accent: Color(0xFF00E5FF),
      background: Color(0xFF0F1026),
      cardBackground: Color(0xFF141432),
      divider: Color(0xFF232348),
      textPrimary: Colors.white,
      textSecondary: Color(0xFF8C8CA8),
      isDark: true,
      previewSwatches: [Color(0xFF2979FF), Color(0xFF00E5FF), Color(0xFF0F1026)],
    ),
    ThemePreset(
      key: 'oled_dark',
      displayName: 'OLED Pure Black',
      description: 'Maximum contrast true black for AMOLED and OLED screens',
      primary: Color(0xFF3D82F6),
      accent: Color(0xFF06B6D4),
      background: Color(0xFF000000),
      cardBackground: Color(0xFF121212),
      divider: Color(0xFF27272A),
      textPrimary: Colors.white,
      textSecondary: Color(0xFFA1A1AA),
      isDark: true,
      previewSwatches: [Color(0xFF000000), Color(0xFF121212), Color(0xFF3D82F6)],
    ),
    ThemePreset(
      key: 'deep_purple',
      displayName: 'Neon Purple',
      description: 'Sleek dark violet theme with neon magenta glow',
      primary: Color(0xFF8B5CF6),
      accent: Color(0xFFEC4899),
      background: Color(0xFF0D0B18),
      cardBackground: Color(0xFF19152E),
      divider: Color(0xFF2D2650),
      textPrimary: Colors.white,
      textSecondary: Color(0xFFA78BFA),
      isDark: true,
      previewSwatches: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF0D0B18)],
    ),
    ThemePreset(
      key: 'emerald_teal',
      displayName: 'Emerald Teal',
      description: 'Calming forest emerald with vivid seafoam mint highlights',
      primary: Color(0xFF10B981),
      accent: Color(0xFF14B8A6),
      background: Color(0xFF091714),
      cardBackground: Color(0xFF112A25),
      divider: Color(0xFF1E433C),
      textPrimary: Colors.white,
      textSecondary: Color(0xFF6EE7B7),
      isDark: true,
      previewSwatches: [Color(0xFF10B981), Color(0xFF14B8A6), Color(0xFF091714)],
    ),
    ThemePreset(
      key: 'light_studio',
      displayName: 'Light Studio',
      description: 'Clean minimalist bright theme for daylight productivity',
      primary: Color(0xFF1D4ED8),
      accent: Color(0xFF0284C7),
      background: Color(0xFFF8FAFC),
      cardBackground: Color(0xFFFFFFFF),
      divider: Color(0xFFE2E8F0),
      textPrimary: Color(0xFF0F172A),
      textSecondary: Color(0xFF64748B),
      isDark: false,
      previewSwatches: [Color(0xFFF8FAFC), Color(0xFFFFFFFF), Color(0xFF1D4ED8)],
    ),
  ];

  static ThemePreset getPreset(String key) {
    return all.firstWhere((p) => p.key == key, orElse: () => all.first);
  }
}
