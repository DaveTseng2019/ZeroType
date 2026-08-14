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

  static const _buttonTextStyle =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

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
        // 選中與未選中的圖示都用品牌橘、都放大到 28（Material 預設 24）。
        // 兩者的區別交給實心／外框圖示與選取指示器，不靠顏色。
        // 標籤文字仍然用顏色區分（見下方兩個 LabelTextStyle）。
        selectedIconTheme: const IconThemeData(color: primaryOrange, size: 28),
        unselectedIconTheme:
            const IconThemeData(color: primaryOrange, size: 28),
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
      // 三種按鈕的文字一律 16／w600。對話框的「取消」「確定」是 TextButton 配
      // FilledButton，字級訂在主題才會一致 —— 各處自己寫 fontSize 遲早又走鐘。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryOrange,
          foregroundColor: Colors.white,
          textStyle: _buttonTextStyle,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryOrange,
          textStyle: _buttonTextStyle,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryOrange,
          textStyle: _buttonTextStyle,
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
