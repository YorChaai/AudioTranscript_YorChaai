import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/localization/app_localizations.dart';

class LanguageProvider extends ChangeNotifier {
  static const String _prefKey = 'app_language_code';
  String _languageCode = 'id'; // 'id' = Bahasa Indonesia, 'en' = Full English
  bool _isLoaded = false;

  LanguageProvider() {
    _loadLanguage();
  }

  String get languageCode => _languageCode;
  bool get isEnglish => _languageCode == 'en';
  bool get isLoaded => _isLoaded;

  String tr(String key) => AppLocalizations.get(_languageCode, key);

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLang = prefs.getString(_prefKey);
      if (savedLang != null && (savedLang == 'id' || savedLang == 'en')) {
        _languageCode = savedLang;
      }
    } catch (_) {}
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    if (_languageCode == code) return;
    _languageCode = code;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, code);
    } catch (_) {}
  }
}
