import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/pages/edit_profile.dart';
import 'package:untitled1/services/phone_auth_page.dart';
import 'package:untitled1/pages/verify_business.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountSettingsPage extends StatefulWidget {
  final Map<String, dynamic> userData;
  const AccountSettingsPage({super.key, required this.userData});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  late String _currentPhone;
  String _userRole = "customer";
  bool _isBusinessVerified = false;

  @override
  void initState() {
    super.initState();
    _currentPhone = widget.userData['phone'] ?? 'N/A';
    _userRole = widget.userData['role'] ?? "customer";
    _isBusinessVerified = widget.userData['isVerified'] ?? false;
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
          'title': 'חשבון',
          'edit_profile': 'עריכת פרופיל',
          'personal_info': 'מידע אישי',
          'email': 'אימייל',
          'phone': 'טלפון',
          'town': 'עיר',
          'user_type': 'סוג משתמש',
          'worker': 'בעל מקצוע',
          'client': 'לקוח',
          'admin': 'מנהל',
          'change_phone': 'שנה מספר טלפון',
          'phone_updated': 'מספר הטלפון עודכן בהצלחה',
          'delete_account': 'מחיקת חשבון',
          'change_business': 'עדכן פרטי עסק',
        };
      case 'ar':
        return {
          'title': 'الحساب',
          'edit_profile': 'تعديل الملف الشخصي',
          'personal_info': 'المعلومات الشخصية',
          'email': 'البريد الإلكتروني',
          'phone': 'الهاتف',
          'town': 'المدينة',
          'user_type': 'نوع المستخدم',
          'worker': 'محترف',
          'client': 'عميل',
          'admin': 'مسؤول',
          'change_phone': 'تغيير رقم الهاتف',
          'phone_updated': 'تم تحديث رقم الهاتف بنجاح',
          'delete_account': 'حذف الحساب',
          'change_business': 'تحديث بيانات العمل',
          'na': 'غير متوفر',
          'firestore_error': 'خطأ أثناء تحديث البيانات',
          'delete_url_error': 'تعذر فتح رابط حذف الحساب',
        };
      case 'am':
        return {
          'title': 'መለያ',
          'edit_profile': 'ፕሮፋይል አርትዕ',
          'personal_info': 'የግል መረጃ',
          'email': 'ኢሜይል',
          'phone': 'ስልክ',
          'town': 'ከተማ',
          'user_type': 'የተጠቃሚ አይነት',
          'worker': 'ባለሙያ',
          'client': 'ደንበኛ',
          'admin': 'አስተዳዳሪ',
          'change_phone': 'የስልክ ቁጥር ቀይር',
          'phone_updated': 'የስልክ ቁጥር በተሳካ ሁኔታ ተዘምኗል',
          'delete_account': 'መለያ ሰርዝ',
          'change_business': 'የንግድ መረጃ አዘምን',
          'na': 'አይገኝም',
          'firestore_error': 'ውሂብ ሲዘምን ስህተት ተፈጥሯል',
          'delete_url_error': 'የመለያ ሰርዝ ሊንኩን መክፈት አልተቻለም',
        };
      case 'ru':
        return {
          'title': 'Аккаунт',
          'edit_profile': 'Редактировать профиль',
          'personal_info': 'Личная информация',
          'email': 'Электронная почта',
          'phone': 'Телефон',
          'town': 'Город',
          'user_type': 'Тип пользователя',
          'worker': 'Специалист',
          'client': 'Клиент',
          'admin': 'Администратор',
          'change_phone': 'Изменить номер телефона',
          'phone_updated': 'Номер телефона успешно обновлен',
          'delete_account': 'Удалить аккаунт',
          'change_business': 'Обновить данные бизнеса',
          'na': 'Недоступно',
          'firestore_error': 'Ошибка при обновлении данных',
          'delete_url_error': 'Не удалось открыть ссылку удаления аккаунта',
        };
      default:
        return {
          'title': 'Account',
          'edit_profile': 'Edit Profile',
          'personal_info': 'Personal Information',
          'email': 'Email',
          'phone': 'Phone',
          'town': 'Town',
          'user_type': 'User Type',
          'worker': 'Professional',
          'client': 'Client',
          'admin': 'Admin',
          'change_phone': 'Change Phone Number',
          'phone_updated': 'Phone number updated successfully',
          'delete_account': 'Delete Account',
          'change_business': 'Update Business Info',
          'na': 'N/A',
          'firestore_error': 'Error updating Firestore',
          'delete_url_error': 'Could not launch delete account URL',
        };
    }
  }

  Future<void> _updatePhoneInFirestore(String newPhone) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'phone': newPhone});

        setState(() {
          _currentPhone = newPhone;
        });
        if (mounted) {
          final strings = _getLocalizedStrings(context, listen: false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(strings['phone_updated']!)));
        }
      }
    } catch (e) {
      if (mounted) {
        final strings = _getLocalizedStrings(context, listen: false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings['firestore_error']!}: $e')),
        );
      }
    }
  }

  void _onChangePhone() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhoneAuthPage(
          isReauth: true,
          onVerified: (newPhone) {
            _updatePhoneInFirestore(newPhone);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  Future<void> _launchDeleteUrl() async {
    final Uri url = Uri.parse('https://hire-hub-fe6c4.web.app/delete-account');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      final strings = _getLocalizedStrings(context, listen: false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['delete_url_error']!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final isRtl =
        Provider.of<LanguageProvider>(context).locale.languageCode == 'he' ||
        Provider.of<LanguageProvider>(context).locale.languageCode == 'ar';

    final email = widget.userData['email'] ?? strings['na'];
    final town = widget.userData['town'] ?? strings['na'];

    String userType = strings['client']!;
    if (_userRole == 'worker') {
      userType = strings['worker']!;
    } else if (_userRole == 'admin') {
      userType = strings['admin']!;
    }

    if (Platform.isIOS) {
      return Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: CupertinoPageScaffold(
          backgroundColor: CupertinoColors.systemGroupedBackground,
          navigationBar: CupertinoNavigationBar(
            middle: Text(strings['title']!),
          ),
          child: ListView(
            children: [
              CupertinoListSection.insetGrouped(
                children: [
                  CupertinoListTile(
                    leading: const Icon(
                      CupertinoIcons.person,
                      color: CupertinoColors.systemBlue,
                    ),
                    title: Text(strings['edit_profile']!),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditProfilePage(
                          userData: {
                            ...widget.userData,
                            'phone': _currentPhone,
                            'role': _userRole,
                          },
                        ),
                      ),
                    ),
                  ),
                  CupertinoListTile(
                    leading: const Icon(
                      CupertinoIcons.phone,
                      color: CupertinoColors.systemGreen,
                    ),
                    title: Text(strings['change_phone']!),
                    trailing: const CupertinoListTileChevron(),
                    onTap: _onChangePhone,
                  ),
                  if (_userRole == 'worker' && _isBusinessVerified)
                    CupertinoListTile(
                      leading: const Icon(
                        CupertinoIcons.briefcase,
                        color: CupertinoColors.systemIndigo,
                      ),
                      title: Text(strings['change_business']!),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => const VerifyBusinessPage(),
                        ),
                      ),
                    ),
                  CupertinoListTile(
                    leading: const Icon(
                      CupertinoIcons.person_badge_minus,
                      color: CupertinoColors.destructiveRed,
                    ),
                    title: Text(
                      strings['delete_account']!,
                      style: const TextStyle(
                        color: CupertinoColors.destructiveRed,
                      ),
                    ),
                    trailing: const CupertinoListTileChevron(),
                    onTap: _launchDeleteUrl,
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: Text(strings['personal_info']!),
                children: [
                  CupertinoListTile(
                    title: Text(strings['email']!),
                    additionalInfo: Text(email),
                  ),
                  CupertinoListTile(
                    title: Text(strings['phone']!),
                    additionalInfo: Text(_currentPhone),
                  ),
                  CupertinoListTile(
                    title: Text(strings['town']!),
                    additionalInfo: Text(town),
                  ),
                  CupertinoListTile(
                    title: Text(strings['user_type']!),
                    additionalInfo: Text(userType),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        appBar: AppBar(
          title: Text(strings['title']!),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSection([
              _buildTile(Icons.person_outline, strings['edit_profile']!, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditProfilePage(
                      userData: {
                        ...widget.userData,
                        'phone': _currentPhone,
                        'role': _userRole,
                      },
                    ),
                  ),
                );
              }),
              const Divider(height: 1, indent: 50),
              _buildTile(
                Icons.phone_android_outlined,
                strings['change_phone']!,
                _onChangePhone,
              ),
              if (_userRole == 'worker' && _isBusinessVerified) ...[
                const Divider(height: 1, indent: 50),
                _buildTile(
                  Icons.business_center_outlined,
                  strings['change_business']!,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const VerifyBusinessPage(),
                    ),
                  ),
                ),
              ],
              const Divider(height: 1, indent: 50),
              _buildTile(
                Icons.person_remove_outlined,
                strings['delete_account']!,
                _launchDeleteUrl,
                color: Colors.red,
              ),
            ]),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                strings['personal_info']!.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8E8E93),
                ),
              ),
            ),
            _buildSection([
              _buildInfoTile(Icons.email_outlined, strings['email']!, email),
              const Divider(height: 1, indent: 50),
              _buildInfoTile(
                Icons.phone_outlined,
                strings['phone']!,
                _currentPhone,
              ),
              const Divider(height: 1, indent: 50),
              _buildInfoTile(
                Icons.location_on_outlined,
                strings['town']!,
                town,
              ),
              const Divider(height: 1, indent: 50),
              _buildInfoTile(
                Icons.badge_outlined,
                strings['user_type']!,
                userType,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildTile(
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
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1976D2)),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
          color: Colors.grey,
        ),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.black,
          fontSize: 16,
        ),
      ),
    );
  }
}
