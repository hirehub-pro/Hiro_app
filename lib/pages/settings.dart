import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/sighn_in.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'הגדרות',
          'notifications': 'התראות',
          'language': 'שפה',
          'about': 'אודות',
          'account': 'חשבון',
          'privacy': 'פרטיות',
          'help': 'עזרה',
          'logout': 'התנתקות',
        };
      case 'ar':
        return {
          'title': 'الإعدادات',
          'notifications': 'الإشعارات',
          'language': 'اللغة',
          'about': 'حول',
          'account': 'الحساب',
          'privacy': 'الخصوصية',
          'help': 'المساعدة',
          'logout': 'تسجيل الخروج',
        };
      case 'ru':
        return {
          'title': 'Настройки',
          'notifications': 'Уведомления',
          'language': 'Язык',
          'about': 'О программе',
          'account': 'Аккаунт',
          'privacy': 'Конфиденциальность',
          'help': 'Помощь',
          'logout': 'Выйти',
        };
      default:
        return {
          'title': 'Settings',
          'notifications': 'Notifications',
          'language': 'Language',
          'about': 'About',
          'account': 'Account',
          'privacy': 'Privacy',
          'help': 'Help & Support',
          'logout': 'Logout',
        };
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const SignInPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final theme = Theme.of(context);
    final isRtl = Provider.of<LanguageProvider>(context).locale.languageCode == 'he' || 
                  Provider.of<LanguageProvider>(context).locale.languageCode == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: theme.colorScheme.background,
        appBar: AppBar(
          title: Text(strings['title']!, style: theme.textTheme.titleLarge),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildSection(strings['account']!, [
              _buildTile(Icons.person_outline_rounded, strings['account']!, theme),
              _buildTile(Icons.lock_outline_rounded, strings['privacy']!, theme),
            ], theme),
            const SizedBox(height: 24),
            _buildSection(strings['notifications']!, [
              _buildSwitchTile(Icons.notifications_none_rounded, strings['notifications']!, _notificationsEnabled, (v) => setState(() => _notificationsEnabled = v), theme),
            ], theme),
            const SizedBox(height: 24),
            _buildSection(strings['language']!, [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.language_rounded, color: theme.colorScheme.primary, size: 22),
                ),
                title: Text(strings['language']!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                trailing: const languageDropDown(),
              ),
            ], theme),
            const SizedBox(height: 24),
            _buildSection(strings['help']!, [
              _buildTile(Icons.help_outline_rounded, strings['help']!, theme),
              _buildTile(Icons.info_outline_rounded, strings['about']!, theme),
            ], theme),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: Text(strings['logout']!),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFEE2E2),
                foregroundColor: const Color(0xFFEF4444),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 1)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildTile(IconData icon, String title, ThemeData theme) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: theme.colorScheme.primary, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1)),
      onTap: () {},
    );
  }

  Widget _buildSwitchTile(IconData icon, String title, bool value, Function(bool) onChanged, ThemeData theme) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: theme.colorScheme.primary, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: theme.colorScheme.primary,
        activeTrackColor: theme.colorScheme.primary.withOpacity(0.2),
      ),
    );
  }
}

class languageDropDown extends StatelessWidget {
  const languageDropDown({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale;
    String current = 'English';
    if (locale.languageCode == 'he') current = 'עברית';
    else if (locale.languageCode == 'ar') current = 'عربي';
    else if (locale.languageCode == 'ru') current = 'русский ';

    return DropdownButton<String>(
      value: current,
      underline: const SizedBox(),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
      items: ['English', 'עברית', 'عربي', 'русский '].map((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        );
      }).toList(),
      onChanged: (String? newValue) {
        if (newValue != null) {
          Provider.of<LanguageProvider>(context, listen: false).setLocale(newValue);
        }
      },
    );
  }
}
