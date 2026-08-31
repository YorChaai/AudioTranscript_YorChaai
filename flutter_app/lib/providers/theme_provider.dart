import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme_modes.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _prefKey = 'app_theme_key';
  String _currentThemeKey = AppThemePresets.defaultKey;
  bool _isLoaded = false;

  ThemeProvider() {
    _loadTheme();
  }

  String get currentThemeKey => _currentThemeKey;
  bool get isLoaded => _isLoaded;
  ThemePreset get currentPreset => AppThemePresets.getPreset(_currentThemeKey);
  ThemeData get currentThemeData => currentPreset.toThemeData();

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedKey = prefs.getString(_prefKey);
      if (savedKey != null && AppThemePresets.all.any((p) => p.key == savedKey)) {
        _currentThemeKey = savedKey;
      }
    } catch (_) {}
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setTheme(String themeKey) async {
    if (_currentThemeKey == themeKey) return;
    _currentThemeKey = themeKey;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, themeKey);
    } catch (_) {}
  }
}
