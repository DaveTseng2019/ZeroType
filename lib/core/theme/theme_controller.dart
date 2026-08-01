import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/di/injection.dart';

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

class ThemeController extends Notifier<ThemeMode> {
  static const _themeKey = 'theme_mode';

  SharedPreferences get _prefs => appPrefs;

  @override
  ThemeMode build() {
    final savedTheme = _prefs.getString(_themeKey);
    if (savedTheme == 'light') return ThemeMode.light;
    if (savedTheme == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_themeKey, mode.name);
  }

  Future<void> toggleTheme() async {
    final isDark = state == ThemeMode.dark || 
        (state == ThemeMode.system && 
         PlatformDispatcher.instance.platformBrightness == Brightness.dark);
    
    await setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }
}
