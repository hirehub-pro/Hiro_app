import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/language_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    // Listen to LanguageProvider directly to ensure rebuilds on change
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'הגדרות',
          'notifications': 'התראות',
          'dark_mode': 'מצב כהה',
          'language': 'שפה',
          'about': 'אודות',
          'ok': 'אישור'
        };
      case 'ar':
        return {
          'title': 'الإعدادات',
          'notifications': 'الإشعارات',
          'dark_mode': 'الوضع الداكن',
          'language': 'اللغة',
          'about': 'حول',
          'ok': 'موافق'
        };
      case 'ru':
        return {
          'title': 'Настройки',
          'notifications': 'Уведомления',
          'dark_mode': 'Темный режим',
          'language': 'Язык',
          'about': 'О программе',
          'ok': 'ОК'
        };
      default:
        return {
          'title': 'Settings',
          'notifications': 'Notifications',
          'dark_mode': 'Dark Mode',
          'language': 'Language',
          'about': 'About',
          'ok': 'OK'
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text(strings['title']!)),
        body: ListView(
          children: [
            ListTile(
              title: Text(strings['notifications']!),
              trailing: Switch(
                value: _notificationsEnabled,
                onChanged: (value) {
                  setState(() {
                    _notificationsEnabled = value;
                  });
                },
              ),
            ),
            ListTile(
              title: Text(strings['dark_mode']!),
              trailing: Switch(
                value: _darkModeEnabled,
                onChanged: (value) {
                  setState(() {
                    _darkModeEnabled = value;
                  });
                },
              ),
            ),
            ListTile(
              title: Text(strings['language']!),
              trailing: Icon(isRtl ? Icons.arrow_left : Icons.arrow_right),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text(strings['language']!),
                      content: const languageDropDown(),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text(strings['ok']!),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            ListTile(
              title: Text(strings['about']!),
              onTap: () {
                // Add navigation or about dialog
              },
            ),
          ],
        ),
      ),
    );
  }
}

class languageDropDown extends StatefulWidget {
  const languageDropDown({Key? key}) : super(key: key);
  @override
  State<languageDropDown> createState() => _languageDropDownState();
}

class _languageDropDownState extends State<languageDropDown> {
  String selectedLanguage = 'English';

  @override
  void initState() {
    super.initState();
    _updateSelectedLanguage();
  }

  void _updateSelectedLanguage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final locale = Provider.of<LanguageProvider>(context, listen: false).locale;
      setState(() {
        if (locale.languageCode == 'en') {
          selectedLanguage = 'English';
        } else if (locale.languageCode == 'he') {
          selectedLanguage = 'עברית';
        } else if (locale.languageCode == 'ar') {
          selectedLanguage = 'عربي';
        } else if (locale.languageCode == 'ru') {
          selectedLanguage = 'русский ';
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: selectedLanguage,
      isExpanded: true,
      items: <String>['English', 'עברית', 'عربي', 'русский ']
          .map<DropdownMenuItem<String>>((String value) {
        return DropdownMenuItem<String>(value: value, child: Text(value));
      })
          .toList(),
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() {
            selectedLanguage = newValue;
          });
          Provider.of<LanguageProvider>(context, listen: false).setLocale(newValue);
        }
      },
    );
  }
}
