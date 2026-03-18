import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/edit_profile.dart';
import 'package:untitled1/pages/phone_auth_page.dart';

class AccountSettingsPage extends StatefulWidget {
  final Map<String, dynamic> userData;
  const AccountSettingsPage({super.key, required this.userData});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  late String _currentPhone;

  @override
  void initState() {
    super.initState();
    _currentPhone = widget.userData['phone'] ?? 'N/A';
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
          'change_phone': 'שנה מספר טלפון',
          'phone_updated': 'מספר הטלפון עודכן בהצלחה',
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
          'change_phone': 'تغيير رقم الهاتف',
          'phone_updated': 'تم تحديث رقم الهاتف بنجاح',
        };
      case 'am':
        return {
          'title': 'አካውንት',
          'edit_profile': 'ፕሮፋይል አዘምን',
          'personal_info': 'የግል መረጃ',
          'email': 'ኢሜይል',
          'phone': 'ስልክ',
          'town': 'ከተማ',
          'user_type': 'የተጠቃሚ ዓይነት',
          'worker': 'ባለሙያ',
          'client': 'ደንበኛ',
          'change_phone': 'የስልክ ቁጥር ይቀይሩ',
          'phone_updated': 'የስልክ ቁጥር በተሳካ ሁኔታ ተቀይሯል',
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
          'change_phone': 'Change Phone Number',
          'phone_updated': 'Phone number updated successfully',
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error updating Firestore: $e")));
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
            Navigator.pop(
              context,
            ); // Go back to account settings from PhoneAuthPage
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final isRtl =
        Provider.of<LanguageProvider>(context).locale.languageCode == 'he' ||
        Provider.of<LanguageProvider>(context).locale.languageCode == 'ar';

    final email = widget.userData['email'] ?? 'N/A';
    final town = widget.userData['town'] ?? 'N/A';
    final userType = widget.userData['userType'] == 'worker'
        ? strings['worker']
        : strings['client'];

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
                    additionalInfo: Text(userType!),
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
                      userData: {...widget.userData, 'phone': _currentPhone},
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
                userType!,
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

  Widget _buildTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1976D2)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
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
