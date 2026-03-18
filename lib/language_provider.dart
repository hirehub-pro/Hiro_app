import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  Locale _locale = const Locale('he');

  LanguageProvider() {
    _loadLocale();
  }

  Locale get locale => _locale;

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final String? languageCode = prefs.getString('language_code');
    if (languageCode != null) {
      _locale = Locale(languageCode);
      notifyListeners();
    }
  }
  
  /// Sets the locale using a language code (e.g., 'en', 'he', 'ar')
  Future<void> setLocale(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    _locale = Locale(languageCode);
    await prefs.setString('language_code', languageCode);
    notifyListeners();
  }
}
