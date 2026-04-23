import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/sign_in.dart';
import 'package:untitled1/pages/about.dart';
import 'package:untitled1/pages/account_settings.dart';
import 'package:untitled1/pages/help_page.dart';
import 'package:untitled1/pages/privacy_policy_page.dart';
import 'package:untitled1/pages/reports_page.dart';
import 'package:untitled1/pages/terms_of_service_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const List<int> _displayWeekdayOrder = [7, 1, 2, 3, 4, 5, 6];
  bool _notificationsEnabled = true;
  bool _hideSchedule = false;
  List<int> _disabledDays = []; // 1 = Monday, 7 = Sunday
  TimeOfDay _workingHoursFrom = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _workingHoursTo = const TimeOfDay(hour: 16, minute: 0);
  bool _isLoadingSettings = true;
  Map<String, dynamic>? _userData;
  String _userRole = "customer";

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
      final firestore = FirebaseFirestore.instance;
      final doc = await firestore.collection('users').doc(user.uid).get();
      final scheduleDoc = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('Schedule')
          .doc('info')
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final scheduleData = scheduleDoc.data() as Map<String, dynamic>?;
        final defaultWorkingHours =
            scheduleData?['defaultWorkingHours'] as Map<String, dynamic>?;
        final status = await Permission.notification.status;
        setState(() {
          _userData = data;
          _userRole = data['role'] ?? 'customer';
          _hideSchedule = data['hideSchedule'] ?? false;
          _disabledDays = List<int>.from(data['disabledDays'] ?? []);
          _workingHoursFrom = _parseStoredTime(
            defaultWorkingHours?['from']?.toString(),
            fallback: const TimeOfDay(hour: 8, minute: 0),
          );
          _workingHoursTo = _parseStoredTime(
            defaultWorkingHours?['to']?.toString(),
            fallback: const TimeOfDay(hour: 16, minute: 0),
          );
          _notificationsEnabled =
              (data['notificationsEnabled'] ?? true) &&
              !status.isPermanentlyDenied;
          _isLoadingSettings = false;
        });
      } else {
        setState(() => _isLoadingSettings = false);
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
      setState(() => _isLoadingSettings = false);
    }
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final firestore = FirebaseFirestore.instance;
    await firestore.collection('users').doc(user.uid).update({key: value});

    if (key == 'hideSchedule' || key == 'disabledDays') {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('Schedule')
          .doc('info')
          .set({key: value}, SetOptions(merge: true));
    }
  }

  TimeOfDay _parseStoredTime(String? value, {required TimeOfDay fallback}) {
    final raw = (value ?? '').trim();
    final parts = raw.split(':');
    if (parts.length != 2) return fallback;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return fallback;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return fallback;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatStoredTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _displayTime(TimeOfDay time) {
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(time, alwaysUse24HourFormat: true);
  }

  Future<void> _updateWorkingHours() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('Schedule')
        .doc('info')
        .set({
          'defaultWorkingHours': {
            'from': _formatStoredTime(_workingHoursFrom),
            'to': _formatStoredTime(_workingHoursTo),
          },
        }, SetOptions(merge: true));
  }

  Future<void> _pickWorkingHour({required bool isStart}) async {
    final initialTime = isStart ? _workingHoursFrom : _workingHoursTo;
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;

    final currentStart = isStart ? picked : _workingHoursFrom;
    final currentEnd = isStart ? _workingHoursTo : picked;
    final startMinutes = (currentStart.hour * 60) + currentStart.minute;
    final endMinutes = (currentEnd.hour * 60) + currentEnd.minute;
    if (endMinutes <= startMinutes) return;

    setState(() {
      if (isStart) {
        _workingHoursFrom = picked;
      } else {
        _workingHoursTo = picked;
      }
    });
    await _updateWorkingHours();
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      final status = await Permission.notification.request();
      if (status.isGranted) {
        setState(() => _notificationsEnabled = true);
        await _updateSetting('notificationsEnabled', true);
      } else if (status.isPermanentlyDenied) {
        if (mounted) {
          _showPermissionDialog();
        }
        setState(() => _notificationsEnabled = false);
      } else {
        setState(() => _notificationsEnabled = false);
      }
    } else {
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
          'privacy': 'מדיניות פרטיות',
          'terms': 'תנאי שימוש',
          'delete_account': 'מחיקת חשבון',
          'help': 'עזרה',
          'reports': 'דיווחים',
          'logout': 'התנתקות',
          'appearance': 'מראה',
          'schedule': 'לוח זמנים',
          'hide_schedule': 'הסתר לוח זמנים מאחרים',
          'work_days': 'ימי עבודה',
          'working_hours': 'שעות עבודה',
          'available_from': 'זמין מ-',
          'available_to': 'זמין עד',
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
          'privacy': 'سياسة الخصوصية',
          'terms': 'شروط الخدمة',
          'delete_account': 'حذف الحساب',
          'help': 'المساعدة',
          'reports': 'البلاغات',
          'logout': 'تسجيل الخروج',
          'appearance': 'المظهر',
          'schedule': 'الجدول الزمني',
          'hide_schedule': 'إخفاء الجدول عن الآخرين',
          'work_days': 'أيام العمل',
          'working_hours': 'ساعات العمل',
          'available_from': 'متاح من',
          'available_to': 'متاح حتى',
          'select_off_days': 'اختر أيام العطلة الثابتة',
          'days': 'ح,ن,ث,ر,خ,ج,س',
          'permission_denied':
              'الإشعارات محظورة في إعدادات الجهاز. هل تريد فتح الإعدادات؟',
          'settings': 'الإعدادات',
          'cancel': 'إلغاء',
        };
      case 'ru':
        return {
          'title': 'Настройки',
          'notifications': 'Уведомления',
          'language': 'Язык',
          'about': 'О приложении',
          'account': 'Аккаунт',
          'privacy': 'Политика конфиденциальности',
          'terms': 'Условия использования',
          'delete_account': 'Удалить аккаунт',
          'help': 'Помощь',
          'reports': 'Жалобы',
          'logout': 'Выйти',
          'appearance': 'Внешний вид',
          'schedule': 'Расписание',
          'hide_schedule': 'Скрыть расписание от других',
          'work_days': 'Рабочие дни',
          'working_hours': 'Рабочие часы',
          'available_from': 'Доступен с',
          'available_to': 'Доступен до',
          'select_off_days': 'Выберите постоянные выходные',
          'days': 'Вс,Пн,Вт,Ср,Чт,Пт,Сб',
          'permission_denied':
              'Уведомления заблокированы в настройках устройства. Открыть настройки?',
          'settings': 'Настройки',
          'cancel': 'Отмена',
        };
      case 'am':
        return {
          'title': 'ቅንብሮች',
          'notifications': 'ማሳወቂያዎች',
          'language': 'ቋንቋ',
          'about': 'ስለ መተግበሪያው',
          'account': 'መለያ',
          'privacy': 'የግላዊነት ፖሊሲ',
          'terms': 'የአጠቃቀም ውል',
          'delete_account': 'መለያ ሰርዝ',
          'help': 'እገዛ',
          'reports': 'ሪፖርቶች',
          'logout': 'ውጣ',
          'appearance': 'መልክ',
          'schedule': 'መርሃ ግብር',
          'hide_schedule': 'መርሃ ግብሩን ከሌሎች ደብቅ',
          'work_days': 'የስራ ቀናት',
          'working_hours': 'የስራ ሰዓቶች',
          'available_from': 'ዝግጁ ከ',
          'available_to': 'ዝግጁ እስከ',
          'select_off_days': 'ቋሚ የእረፍት ቀናትን ይምረጡ',
          'days': 'እ,ሰ,ማ,ረ,ሐ,ዓ,ቅ',
          'permission_denied': 'ማሳወቂያዎች በመሣሪያው ቅንብሮች ውስጥ ታግደዋል። ቅንብሮቹን ልክፈት?',
          'settings': 'ቅንብሮች',
          'cancel': 'ሰርዝ',
        };
      default:
        return {
          'title': 'Settings',
          'notifications': 'Notifications',
          'language': 'Language',
          'about': 'About',
          'account': 'Account',
          'privacy': 'Privacy Policy',
          'terms': 'Terms of Service',
          'delete_account': 'Delete Account',
          'help': 'Help & Support',
          'reports': 'Reports',
          'logout': 'Logout',
          'appearance': 'Appearance',
          'schedule': 'Schedule',
          'hide_schedule': 'Hide schedule from others',
          'work_days': 'Working Days',
          'working_hours': 'Working Hours',
          'available_from': 'Available from',
          'available_to': 'Available to',
          'select_off_days': 'Select fixed days off',
          'days': 'Su,Mo,Tu,We,Th,Fr,Sa',
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

    _loadSettings();
  }

  void _goToHelpPage() {
    if (Platform.isIOS) {
      Navigator.push(
        context,
        CupertinoPageRoute(builder: (_) => const HelpPage()),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HelpPage()),
    );
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

    if (_userRole != 'worker') return const SizedBox.shrink();

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
      ListTile(
        leading: const Icon(Icons.schedule_rounded, color: Color(0xFF1976D2)),
        title: Text(
          strings['working_hours']!,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${strings['available_from']!} ${_displayTime(_workingHoursFrom)}   ${strings['available_to']!} ${_displayTime(_workingHoursTo)}',
        ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: () async {
          await _pickWorkingHour(isStart: true);
          if (!mounted) return;
          await _pickWorkingHour(isStart: false);
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
                final dayNum = _displayWeekdayOrder[index];
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
              automaticallyImplyLeading: false,
              actions: [
                if (Navigator.of(context).canPop())
                  IconButton(
                    icon: const BackButtonIcon(),
                    onPressed: () => Navigator.maybePop(context),
                  ),
              ],
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
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PrivacyPolicyPage(),
                              ),
                            );
                          },
                        ),
                        _buildGalaxyTile(
                          Icons.description_outlined,
                          strings['terms']!,
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TermsOfServicePage(),
                              ),
                            );
                          },
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
                          _goToHelpPage,
                        ),
                        _buildGalaxyTile(
                          Icons.report_problem_outlined,
                          strings['reports']!,
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ReportsPage(),
                              ),
                            );
                          },
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
    if (children.isEmpty) return const SizedBox.shrink();
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

  Widget _buildGalaxyTile(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? const Color(0xFF1976D2)),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w500, color: color),
      ),
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
          automaticallyImplyLeading: false,
          middle: Text(strings['title']!),
          trailing: Navigator.of(context).canPop()
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => Navigator.maybePop(context),
                  child: Icon(
                    isRtl ? CupertinoIcons.forward : CupertinoIcons.back,
                  ),
                )
              : null,
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
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => const PrivacyPolicyPage(),
                      ),
                    );
                  },
                ),
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.doc_text,
                    color: CupertinoColors.systemBlue,
                  ),
                  title: Text(strings['terms']!),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => const TermsOfServicePage(),
                      ),
                    );
                  },
                ),
              ],
            ),
            if (_userRole == 'worker')
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
                  CupertinoListTile(
                    leading: const Icon(
                      CupertinoIcons.time,
                      color: CupertinoColors.systemBlue,
                    ),
                    title: Text(strings['working_hours']!),
                    subtitle: Text(
                      '${strings['available_from']!} ${_displayTime(_workingHoursFrom)}   ${strings['available_to']!} ${_displayTime(_workingHoursTo)}',
                    ),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () async {
                      await _pickWorkingHour(isStart: true);
                      if (!mounted) return;
                      await _pickWorkingHour(isStart: false);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (index) {
                        final dayNum = _displayWeekdayOrder[index];
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
                                  ? CupertinoColors.systemRed.withOpacity(0.1)
                                  : CupertinoColors.systemBlue.withOpacity(0.1),
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
                  onTap: _goToHelpPage,
                ),
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.exclamationmark_bubble,
                    color: CupertinoColors.systemBlue,
                  ),
                  title: Text(strings['reports']!),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(builder: (_) => const ReportsPage()),
                    );
                  },
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

    return Material(
      type: MaterialType.transparency,
      child: PopupMenuButton<String>(
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
      ),
    );
  }
}
