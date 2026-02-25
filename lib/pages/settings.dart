import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Notifications'),
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
            title: const Text('Dark Mode'),
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
            title: const Text('Language'),
            trailing: const Icon(Icons.arrow_right),
            onTap: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Language'),
                    content: const languageDropDown(),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text('OK'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          ListTile(
            title: const Text('About'),
            onTap: () {
              // Add navigation or about dialog
            },
          ),
        ],
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
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: selectedLanguage,
      items: <String>['English', 'עברית', 'عربي', 'русский ']
          .map<DropdownMenuItem<String>>((String value) {
        return DropdownMenuItem<String>(value: value, child: Text(value));
      })
          .toList(),
      onChanged: (String? newValue) {
        setState(() {
          selectedLanguage = newValue!;
        });
      },
    );
  }

  String getLanguage() {
    return this.selectedLanguage;
  }
}
