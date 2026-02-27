import 'package:flutter/material.dart';

class LanguageProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  void setLocale(String language) {
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
      default:
        _locale = const Locale('en');
    }
    notifyListeners();
  }
}
