import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const primaryOrange = Color(0xFFFF7A00);
  
  // Light Colors
  static const _lightBackground = Color(0xFFFFFFFF);
  static const _lightSurface = Color(0xFFF8F9FA);
  static const _lightOnSurface = Color(0xFF1A1A1A);

  // Dark Colors
  static const _darkBackground = Color(0xFF000000);
  static const _darkSurface = Color(0xFF121212);
  static const _darkOnSurface = Color(0xFFE0E0E0);

  static ThemeData get lightTheme => _themeData(Brightness.light);
  static ThemeData get darkTheme => _themeData(Brightness.dark);

  static ThemeData _themeData(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryOrange,
        brightness: brightness,
        primary: primaryOrange,
        surface: isDark ? _darkSurface : _lightSurface,
        onSurface: isDark ? _darkOnSurface : _lightOnSurface,
        background: isDark ? _darkBackground : _lightBackground,
      ),
      scaffoldBackgroundColor: isDark ? _darkBackground : _lightBackground,
      fontFamily: 'SF Pro Display',
      useMaterial3: true,
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? _darkSurface : _lightSurface,
        selectedIconTheme: const IconThemeData(color: primaryOrange),
        unselectedIconTheme: IconThemeData(
          color: (isDark ? _darkOnSurface : _lightOnSurface).withOpacity(0.5),
        ),
        selectedLabelTextStyle: const TextStyle(
          color: primaryOrange,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: (isDark ? _darkOnSurface : _lightOnSurface).withOpacity(0.5),
          fontSize: 14,
        ),
      ),
      dividerTheme: DividerThemeData(
        thickness: 1,
        color: (isDark ? _darkOnSurface : _lightOnSurface).withOpacity(0.1),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryOrange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: (isDark ? _darkSurface : _lightSurface).withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryOrange, width: 1.5),
        ),
      ),
    );
  }
}
