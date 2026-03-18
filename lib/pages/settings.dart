import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/sighn_in.dart';
import 'package:untitled1/pages/about.dart';
import 'package:untitled1/pages/account_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  bool _hideSchedule = false;
  List<int> _disabledDays = []; // 1 = Monday, 7 = Sunday
  bool _isLoadingSettings = true;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      setState(() => _isLoadingSettings = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        // Check actual system permission status as well
        final status = await Permission.notification.status;
        setState(() {
          _userData = data;
          _hideSchedule = data['hideSchedule'] ?? false;
          _disabledDays = List<int>.from(data['disabledDays'] ?? []);
          // Sync with Firestore, but also respect system setting if permanently denied
          _notificationsEnabled =
              (data['notificationsEnabled'] ?? true) &&
              !status.isPermanentlyDenied;
          _isLoadingSettings = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
      setState(() => _isLoadingSettings = false);
    }
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      key: value,
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      // Request permission when enabling
      final status = await Permission.notification.request();
      if (status.isGranted) {
        setState(() => _notificationsEnabled = true);
        await _updateSetting('notificationsEnabled', true);
      } else if (status.isPermanentlyDenied) {
        // If permanently denied, show a dialog to open settings
        if (mounted) {
          _showPermissionDialog();
        }
        setState(() => _notificationsEnabled = false);
      } else {
        setState(() => _notificationsEnabled = false);
      }
    } else {
      // Just disable in Firestore/UI
      setState(() => _notificationsEnabled = false);
      await _updateSetting('notificationsEnabled', false);
    }
  }

  void _showPermissionDialog() {
    final strings = _getLocalizedStrings(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings['notifications']!),
        content: Text(strings['permission_denied']!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings['cancel']!),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: Text(strings['settings']!),
          ),
        ],
      ),
    );
  }

  Map<String, String> _getLocalizedStrings(
    BuildContext context, {
    bool listen = true,
  }) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: listen,
    ).locale.languageCode;
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
          'appearance': 'מראה',
          'schedule': 'לוח זמנים',
          'hide_schedule': 'הסתר לוח זמנים מאחרים',
          'work_days': 'ימי עבודה',
          'select_off_days': 'בחר ימי חופש קבועים',
          'days': 'א,ב,ג,ד,ה,ו,ש',
          'permission_denied':
              'התראות חסומות בהגדרות המכשיר. האם תרצה לפתוח את ההגדרות?',
          'settings': 'הגדרות',
          'cancel': 'ביטול',
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
          'appearance': 'المظهر',
          'schedule': 'الجدول الزمني',
          'hide_schedule': 'إخفاء الجدول عن الآخرين',
          'work_days': 'أيام العمل',
          'select_off_days': 'اختر أيام العطلة الثابتة',
          'days': 'ن,ث,ر,خ,ج,س,ح',
          'permission_denied':
              'الإشعارات محظورة في إعدادات الجهاز. هل تريد فتح الإعدادات؟',
          'settings': 'الإعدادات',
          'cancel': 'إلغاء',
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
          'appearance': 'Appearance',
          'schedule': 'Schedule',
          'hide_schedule': 'Hide schedule from others',
          'work_days': 'Working Days',
          'select_off_days': 'Select fixed days off',
          'days': 'M,T,W,T,F,S,S',
          'permission_denied':
              'Notifications are blocked in system settings. Would you like to open settings?',
          'settings': 'Settings',
          'cancel': 'Cancel',
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

  void _goToAccountSettings() async {
    if (_userData == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AccountSettingsPage(userData: _userData!),
      ),
    );

    // Refresh when coming back in case data changed
    _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;
    final isRtl = localeCode == 'he' || localeCode == 'ar';

    if (Platform.isIOS) {
      return _buildIosSettings(context, strings, isRtl);
    } else {
      return _buildAndroidSettings(context, strings, isRtl);
    }
  }

  Widget _buildScheduleSection(Map<String, String> strings) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return const SizedBox.shrink();
    if (_isLoadingSettings)
      return const Center(child: CupertinoActivityIndicator());

    final dayNames = strings['days']!.split(',');

    return _buildGalaxySection(strings['schedule']!, [
      _buildGalaxySwitchTile(
        Icons.calendar_view_day_rounded,
        strings['hide_schedule']!,
        _hideSchedule,
        (v) {
          setState(() => _hideSchedule = v);
          _updateSetting('hideSchedule', v);
        },
      ),
      const Divider(height: 1, indent: 50),
      Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings['select_off_days']!,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (index) {
                final dayNum = index + 1;
                final isOff = _disabledDays.contains(dayNum);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isOff) {
                        _disabledDays.remove(dayNum);
                      } else {
                        _disabledDays.add(dayNum);
                      }
                    });
                    _updateSetting('disabledDays', _disabledDays);
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isOff
                          ? Colors.red.withOpacity(0.1)
                          : const Color(0xFF1976D2).withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isOff ? Colors.red : const Color(0xFF1976D2),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        dayNames[index],
                        style: TextStyle(
                          color: isOff ? Colors.red : const Color(0xFF1976D2),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    ]);
  }

  // --- ANDROID (Galaxy / One UI) DESIGN ---
  Widget _buildAndroidSettings(
    BuildContext context,
    Map<String, String> strings,
    bool isRtl,
  ) {
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        body: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              expandedHeight: 180,
              backgroundColor: const Color(0xFFF2F2F7),
              elevation: 0,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  strings['title']!,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                centerTitle: false,
                titlePadding: const EdgeInsetsDirectional.only(
                  start: 24,
                  bottom: 16,
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _buildGalaxySection(strings['account']!, [
                        _buildGalaxyTile(
                          Icons.person_outline_rounded,
                          strings['account']!,
                          _goToAccountSettings,
                        ),
                        _buildGalaxyTile(
                          Icons.lock_outline_rounded,
                          strings['privacy']!,
                          () {},
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildScheduleSection(strings),
                      const SizedBox(height: 16),
                      _buildGalaxySection(strings['notifications']!, [
                        _buildGalaxySwitchTile(
                          Icons.notifications_none_rounded,
                          strings['notifications']!,
                          _notificationsEnabled,
                          _toggleNotifications,
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildGalaxySection(strings['language']!, [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: const Icon(
                            Icons.language_rounded,
                            color: Color(0xFF1976D2),
                          ),
                          title: Text(
                            strings['language']!,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: const LanguageDropDown(),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildGalaxySection(strings['help']!, [
                        _buildGalaxyTile(
                          Icons.help_outline_rounded,
                          strings['help']!,
                          () {},
                        ),
                        _buildGalaxyTile(
                          Icons.info_outline_rounded,
                          strings['about']!,
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AboutPage(),
                              ),
                            );
                          },
                        ),
                      ]),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _logout,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                            backgroundColor: Colors.white,
                          ),
                          child: Text(
                            strings['logout']!,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalaxySection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF8E8E93),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildGalaxyTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1976D2)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildGalaxySwitchTile(
    IconData icon,
    String title,
    bool value,
    Function(bool) onChanged,
  ) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1976D2)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: const Color(0xFF1976D2).withOpacity(0.5),
        activeThumbColor: const Color(0xFF1976D2),
      ),
    );
  }

  // --- iOS (Cupertino) DESIGN ---
  Widget _buildIosSettings(
    BuildContext context,
    Map<String, String> strings,
    bool isRtl,
  ) {
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        navigationBar: CupertinoNavigationBar(
          middle: Text(strings['title']!),
          border: null,
        ),
        child: ListView(
          children: [
            CupertinoListSection.insetGrouped(
              header: Text(strings['account']!),
              children: [
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.person,
                    color: CupertinoColors.systemBlue,
                  ),
                  title: Text(strings['account']!),
                  trailing: const CupertinoListTileChevron(),
                  onTap: _goToAccountSettings,
                ),
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.lock,
                    color: CupertinoColors.systemBlue,
                  ),
                  title: Text(strings['privacy']!),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {},
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: Text(strings['schedule']!),
              children: [
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.calendar,
                    color: CupertinoColors.systemIndigo,
                  ),
                  title: Text(strings['hide_schedule']!),
                  trailing: CupertinoSwitch(
                    value: _hideSchedule,
                    onChanged: (v) {
                      setState(() => _hideSchedule = v);
                      _updateSetting('hideSchedule', v);
                    },
                  ),
                ),
                // Days off row for iOS
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(7, (index) {
                      final dayNum = index + 1;
                      final isOff = _disabledDays.contains(dayNum);
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isOff) {
                              _disabledDays.remove(dayNum);
                            } else {
                              _disabledDays.add(dayNum);
                            }
                          });
                          _updateSetting('disabledDays', _disabledDays);
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isOff
                                ? CupertinoColors.systemRed.withValues(
                                    alpha: 0.1,
                                  )
                                : CupertinoColors.systemBlue.withValues(
                                    alpha: 0.1,
                                  ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isOff
                                  ? CupertinoColors.systemRed
                                  : CupertinoColors.systemBlue,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              strings['days']!.split(',')[index],
                              style: TextStyle(
                                color: isOff
                                    ? CupertinoColors.systemRed
                                    : CupertinoColors.systemBlue,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: Text(strings['notifications']!),
              children: [
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.bell,
                    color: CupertinoColors.systemRed,
                  ),
                  title: Text(strings['notifications']!),
                  trailing: CupertinoSwitch(
                    value: _notificationsEnabled,
                    onChanged: _toggleNotifications,
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: Text(strings['language']!),
              children: [
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.globe,
                    color: CupertinoColors.systemGreen,
                  ),
                  title: Text(strings['language']!),
                  trailing: const LanguageDropDown(),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: Text(strings['help']!),
              children: [
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.question_circle,
                    color: CupertinoColors.systemOrange,
                  ),
                  title: Text(strings['help']!),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {},
                ),
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.info,
                    color: CupertinoColors.systemGrey,
                  ),
                  title: Text(strings['about']!),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(builder: (_) => const AboutPage()),
                    );
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: CupertinoButton(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(10),
                onPressed: _logout,
                child: Text(
                  strings['logout']!,
                  style: const TextStyle(
                    color: CupertinoColors.destructiveRed,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LanguageDropDown extends StatelessWidget {
  const LanguageDropDown({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale;
    String current = 'English';
    if (locale.languageCode == 'he') {
      current = 'עברית';
    } else if (locale.languageCode == 'ar')
      current = 'عربي';
    else if (locale.languageCode == 'ru')
      current = 'Русский';
    else if (locale.languageCode == 'am')
      current = 'አማርኛ';

    return PopupMenuButton<String>(
      onSelected: (code) {
        Provider.of<LanguageProvider>(context, listen: false).setLocale(code);
      },

      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(current, style: const TextStyle(color: Colors.grey)),
          const Icon(Icons.arrow_drop_down, color: Colors.grey),
        ],
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'en', child: Text('English')),
        const PopupMenuItem(value: 'he', child: Text('עברית')),
        const PopupMenuItem(value: 'ar', child: Text('عربي')),
        const PopupMenuItem(value: 'ru', child: Text('Русский')),
        const PopupMenuItem(value: 'am', child: Text('አማርኛ')),
      ],
    );
  }
}
