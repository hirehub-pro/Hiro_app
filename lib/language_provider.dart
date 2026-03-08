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

  Future<void> setLocale(String language) async {
    final prefs = await SharedPreferences.getInstance();
    switch (language) {
      case 'English':
        _locale = const Locale('en');
        break;
      case 'עברית':
        _locale = const Locale('he');
        break;
      case 'عربي':
        _locale = const Locale('ar');
        break;
      case 'русский ':
        _locale = const Locale('ru');
        break;
      case 'አማርኛ':
        _locale = const Locale('am');
        break;
      default:
        _locale = const Locale('he');
    }
    await prefs.setString('language_code', _locale.languageCode);
    notifyListeners();
  }
}
