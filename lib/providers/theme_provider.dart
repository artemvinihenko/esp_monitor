import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppTheme { light, dark, amethyst }

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  AppTheme _currentTheme = AppTheme.light;
  
  ThemeProvider() {
    _loadTheme();
  }
  
  AppTheme get currentTheme => _currentTheme;
  

  ThemeMode get themeMode {
    switch (_currentTheme) {
      case AppTheme.light:
        return ThemeMode.light;
      case AppTheme.dark:
        return ThemeMode.dark;
      case AppTheme.amethyst:
        return ThemeMode.light; // Базовый режим, но с кастомной темой
    }
  }
  
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey) ?? 0;
    _currentTheme = AppTheme.values[themeIndex];
    notifyListeners();
  }
  
  Future<void> setTheme(AppTheme theme) async {
    _currentTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, theme.index);
    notifyListeners();
  }
  
  bool get isDarkMode {
    return _currentTheme == AppTheme.dark;
  }
  
  bool get isAmethyst {
    return _currentTheme == AppTheme.amethyst;
  }
  
  void toggleTheme() {
    if (_currentTheme == AppTheme.light) {
      setTheme(AppTheme.dark);
    } else if (_currentTheme == AppTheme.dark) {
      setTheme(AppTheme.amethyst);
    } else {
      setTheme(AppTheme.light);
    }
  }
}