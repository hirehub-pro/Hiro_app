import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hiro_admin/services/language_provider.dart';
import 'package:provider/provider.dart';

class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final language = context.watch<LanguageProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<String>(
            initialValue: language.locale.languageCode,
            decoration: const InputDecoration(
              labelText: 'Language',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'he', child: Text('עברית')),
              DropdownMenuItem(value: 'ar', child: Text('العربية')),
            ],
            onChanged: (value) {
              if (value != null) language.setLocale(value);
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
