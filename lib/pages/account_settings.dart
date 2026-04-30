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
import 'package:untitled1/sign_in.dart';

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
    _currentPhone =
        widget.userData['phone'] ??
        FirebaseAuth.instance.currentUser?.phoneNumber ??
        'N/A';
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
          'cancel': 'ביטול',
          'next': 'הבא',
          'yes_delete': 'כן, מחק',
          'keep_account': 'לא, השאר חשבון',
          'delete_confirm_title': 'למחוק את החשבון?',
          'delete_confirm_body':
              'לפני שנמשיך, נוודא שזה באמת מה שבחרת. מחיקה תסיר את החשבון והמידע המקושר אליו.',
          'delete_losses_title': 'מה תאבד',
          'delete_invoices_title': 'חשבוניות ומסמכים',
          'delete_invoices_body':
              'אם יצרת חשבוניות, מומלץ להוריד אותן עכשיו. אחרי מחיקת החשבון לא תהיה לך גישה לחשבון כדי להוריד אותן. לפי החוק בישראל נשמור עותקי חשבוניות למשך 7 שנים.',
          'delete_invoices_badge': 'שמירה למשך 7 שנים',
          'delete_invoices_download': 'הבנתי, המשך',
          'delete_losses_next': 'הבא: חשבוניות',
          'delete_verify_title': 'אימות טלפוני למחיקה',
          'delete_verify_body': 'נשלח קוד SMS למספר {phone}.',
          'delete_code_label': 'קוד SMS',
          'delete_send_code': 'שלח קוד',
          'delete_verify_code': 'אמת קוד',
          'delete_final_title': 'אישור אחרון',
          'delete_final_body':
              'זה השלב האחרון. אחרי אישור, נמחק את החשבון וננתק אותך מהאפליקציה.',
          'delete_failed': 'מחיקת החשבון נכשלה',
          'delete_code_failed': 'האימות נכשל',
          'delete_customer_loss_1': 'הפרופיל ופרטי החשבון שלך יימחקו',
          'delete_customer_loss_2': 'הודעות, בקשות ושיחות לא יהיו זמינות',
          'delete_customer_loss_3': 'פרויקטים שמורים ומועדפים יוסרו',
          'delete_worker_loss_1': 'פרופיל בעל המקצוע שלך יוסר מהחיפוש',
          'delete_worker_loss_2': 'פרויקטים, ביקורות, לו"ז וכלי עבודה יוסרו',
          'delete_worker_loss_3': 'גישה למנוי Pro ולנתוני העסק תופסק',
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
          'cancel': 'إلغاء',
          'next': 'التالي',
          'yes_delete': 'نعم، احذف',
          'keep_account': 'لا، أبقِ الحساب',
          'delete_confirm_title': 'حذف الحساب؟',
          'delete_confirm_body':
              'قبل أن نتابع، سنتأكد أن هذا هو اختيارك فعلًا. الحذف سيزيل الحساب والمعلومات المرتبطة به.',
          'delete_losses_title': 'ما الذي ستفقده',
          'delete_invoices_title': 'الفواتير والمستندات',
          'delete_invoices_body':
              'إذا أنشأت فواتير، ننصح بتنزيلها الآن. بعد حذف الحساب لن تتمكن من الدخول لتنزيلها. وفقًا للقانون في إسرائيل سنحتفظ بنسخ الفواتير لمدة 7 سنوات.',
          'delete_invoices_badge': 'حفظ لمدة 7 سنوات',
          'delete_invoices_download': 'فهمت، تابع',
          'delete_losses_next': 'التالي: الفواتير',
          'delete_verify_title': 'تأكيد الهاتف للحذف',
          'delete_verify_body': 'سنرسل رمز SMS إلى {phone}.',
          'delete_code_label': 'رمز SMS',
          'delete_send_code': 'إرسال الرمز',
          'delete_verify_code': 'تأكيد الرمز',
          'delete_final_title': 'تأكيد أخير',
          'delete_final_body':
              'هذه هي الخطوة الأخيرة. بعد التأكيد سنحذف حسابك ونسجل خروجك من التطبيق.',
          'delete_failed': 'فشل حذف الحساب',
          'delete_code_failed': 'فشل التحقق',
          'delete_customer_loss_1': 'سيتم حذف ملفك وبيانات حسابك',
          'delete_customer_loss_2': 'لن تتوفر الرسائل والطلبات والمحادثات',
          'delete_customer_loss_3': 'ستتم إزالة المحفوظات والمفضلات',
          'delete_worker_loss_1': 'سيتم إزالة ملفك المهني من البحث',
          'delete_worker_loss_2':
              'ستتم إزالة المشاريع والتقييمات والجدول وأدوات العمل',
          'delete_worker_loss_3': 'سيتم إيقاف وصول Pro وبيانات العمل',
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
          'cancel': 'ሰርዝ',
          'next': 'ቀጣይ',
          'yes_delete': 'አዎ፣ ሰርዝ',
          'keep_account': 'አይ፣ መለያውን አቆይ',
          'delete_confirm_title': 'መለያውን ሰርዝ?',
          'delete_confirm_body': 'ከመቀጠላችን በፊት ይህ ትክክለኛው ምርጫዎ መሆኑን እናረጋግጣለን።',
          'delete_losses_title': 'የሚያጡት',
          'delete_invoices_title': 'ደረሰኞች እና ሰነዶች',
          'delete_invoices_body':
              'ደረሰኞችን ካዘጋጁ አሁን ማውረድ ይመከራል። መለያው ከተሰረዘ በኋላ ለማውረድ መግባት አይችሉም። በእስራኤል ህግ መሠረት ደረሰኞችን ለ7 ዓመት እናስቀምጣለን።',
          'delete_invoices_badge': 'ለ7 ዓመት መያዝ',
          'delete_invoices_download': 'ገባኝ፣ ቀጥል',
          'delete_losses_next': 'ቀጣይ: ደረሰኞች',
          'delete_verify_title': 'ለመሰረዝ ስልክ ያረጋግጡ',
          'delete_verify_body': 'የSMS ኮድ ወደ {phone} እንልካለን።',
          'delete_code_label': 'SMS ኮድ',
          'delete_send_code': 'ኮድ ላክ',
          'delete_verify_code': 'ኮድ አረጋግጥ',
          'delete_final_title': 'የመጨረሻ ማረጋገጫ',
          'delete_final_body': 'ይህ የመጨረሻው ደረጃ ነው። ካረጋገጡ መለያዎን እንሰርዛለን።',
          'delete_failed': 'መለያውን መሰረዝ አልተሳካም',
          'delete_code_failed': 'ማረጋገጫው አልተሳካም',
          'delete_customer_loss_1': 'መገለጫዎ እና የመለያ መረጃዎ ይሰረዛሉ',
          'delete_customer_loss_2': 'መልዕክቶች እና ጥያቄዎች አይገኙም',
          'delete_customer_loss_3': 'የተቀመጡ ነገሮች ይወገዳሉ',
          'delete_worker_loss_1': 'የሙያ መገለጫዎ ከፍለጋ ይወገዳል',
          'delete_worker_loss_2': 'ፕሮጀክቶች፣ ግምገማዎች እና መርሃግብር ይወገዳሉ',
          'delete_worker_loss_3': 'የPro መዳረሻ እና የንግድ መረጃ ይቆማሉ',
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
          'cancel': 'Отмена',
          'next': 'Далее',
          'yes_delete': 'Да, удалить',
          'keep_account': 'Нет, оставить',
          'delete_confirm_title': 'Удалить аккаунт?',
          'delete_confirm_body':
              'Перед продолжением мы убедимся, что это действительно ваш выбор. Удаление уберет аккаунт и связанные данные.',
          'delete_losses_title': 'Что вы потеряете',
          'delete_invoices_title': 'Счета и документы',
          'delete_invoices_body':
              'Если вы создавали счета, рекомендуем скачать их сейчас. После удаления аккаунта вы не сможете войти, чтобы получить к ним доступ. Согласно законодательству Израиля мы будем хранить копии счетов 7 лет.',
          'delete_invoices_badge': 'Хранение 7 лет',
          'delete_invoices_download': 'Понятно, продолжить',
          'delete_losses_next': 'Далее: счета',
          'delete_verify_title': 'Подтвердите телефон для удаления',
          'delete_verify_body': 'Мы отправим SMS-код на {phone}.',
          'delete_code_label': 'SMS-код',
          'delete_send_code': 'Отправить код',
          'delete_verify_code': 'Подтвердить код',
          'delete_final_title': 'Последнее подтверждение',
          'delete_final_body':
              'Это последний шаг. После подтверждения мы удалим аккаунт и выйдем из приложения.',
          'delete_failed': 'Не удалось удалить аккаунт',
          'delete_code_failed': 'Проверка не удалась',
          'delete_customer_loss_1':
              'Ваш профиль и данные аккаунта будут удалены',
          'delete_customer_loss_2': 'Сообщения, заявки и чаты будут недоступны',
          'delete_customer_loss_3': 'Сохраненное и избранное будет удалено',
          'delete_worker_loss_1':
              'Ваш профессиональный профиль исчезнет из поиска',
          'delete_worker_loss_2':
              'Проекты, отзывы, график и инструменты будут удалены',
          'delete_worker_loss_3': 'Доступ Pro и бизнес-данные будут отключены',
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
          'cancel': 'Cancel',
          'next': 'Next',
          'yes_delete': 'Yes, delete',
          'keep_account': 'No, keep account',
          'delete_confirm_title': 'Delete your account?',
          'delete_confirm_body':
              'Before we continue, we will make sure this is really what you want. Deleting removes your account and linked data.',
          'delete_losses_title': 'What you will lose',
          'delete_invoices_title': 'Invoices and documents',
          'delete_invoices_body':
              'If you created invoices, download them now. After deleting your account, you will not be able to sign in and access them. We will keep invoice records for 7 years according to Israeli law.',
          'delete_invoices_badge': '7 years retention',
          'delete_invoices_download': 'I understand, continue',
          'delete_losses_next': 'Next: invoices',
          'delete_verify_title': 'Verify your phone to delete',
          'delete_verify_body': 'We will send an SMS code to {phone}.',
          'delete_code_label': 'SMS Code',
          'delete_send_code': 'Send Code',
          'delete_verify_code': 'Verify Code',
          'delete_final_title': 'Final confirmation',
          'delete_final_body':
              'This is the last step. If you confirm, we will delete your account and sign you out.',
          'delete_failed': 'Failed to delete account',
          'delete_code_failed': 'Verification failed',
          'delete_customer_loss_1':
              'Your profile and account details are deleted',
          'delete_customer_loss_2':
              'Messages, requests, and chats become unavailable',
          'delete_customer_loss_3': 'Saved items and favorites are removed',
          'delete_worker_loss_1':
              'Your professional profile is removed from search',
          'delete_worker_loss_2':
              'Projects, reviews, schedule, and worker tools are removed',
          'delete_worker_loss_3':
              'Pro access and business data are disconnected',
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

  Future<void> _startDeleteAccountFlow() async {
    final strings = _getLocalizedStrings(context, listen: false);
    final wantsToContinue = await _showDeleteStepDialog(
      title: strings['delete_confirm_title']!,
      body: strings['delete_confirm_body']!,
      primaryLabel: strings['next']!,
      secondaryLabel: strings['cancel']!,
      icon: Icons.warning_amber_rounded,
    );
    if (wantsToContinue != true || !mounted) return;

    final acceptedLosses = await _showDeleteLossesDialog(strings);
    if (acceptedLosses != true || !mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    final acceptedInvoiceNotice = await _showDeleteInvoicesDialog(strings);
    if (acceptedInvoiceNotice != true || !mounted) return;

    final verified = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _DeletePhoneVerificationPage(
          phoneNumber: _currentPhone,
          strings: strings,
        ),
      ),
    );
    if (verified != true || !mounted) return;

    final finalConfirm = await _showDeleteStepDialog(
      title: strings['delete_final_title']!,
      body: strings['delete_final_body']!,
      primaryLabel: strings['yes_delete']!,
      secondaryLabel: strings['keep_account']!,
      icon: Icons.delete_forever_rounded,
      destructive: true,
    );
    if (finalConfirm != true || !mounted) return;

    await _deleteCurrentAccount(strings);
  }

  Future<bool?> _showDeleteStepDialog({
    required String title,
    required String body,
    required String primaryLabel,
    required String secondaryLabel,
    required IconData icon,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DeleteDialogIcon(icon: icon, destructive: destructive),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(secondaryLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: destructive
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF1976D2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(primaryLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showDeleteLossesDialog(Map<String, String> strings) {
    final losses = _userRole == 'worker'
        ? [
            strings['delete_worker_loss_1']!,
            strings['delete_worker_loss_2']!,
            strings['delete_worker_loss_3']!,
          ]
        : [
            strings['delete_customer_loss_1']!,
            strings['delete_customer_loss_2']!,
            strings['delete_customer_loss_3']!,
          ];

    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _DeleteDialogIcon(
                icon: Icons.inventory_2_outlined,
                destructive: false,
              ),
              const SizedBox(height: 18),
              Text(
                strings['delete_losses_title']!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 16),
              ...losses.map(
                (loss) => Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.remove_circle_outline_rounded,
                        color: Color(0xFFDC2626),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          loss,
                          style: const TextStyle(
                            color: Color(0xFF7F1D1D),
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(strings['cancel']!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(strings['delete_losses_next']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showDeleteInvoicesDialog(Map<String, String> strings) {
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _DeleteDialogIcon(
                icon: Icons.receipt_long_outlined,
                destructive: false,
              ),
              const SizedBox(height: 18),
              Text(
                strings['delete_invoices_title']!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                strings['delete_invoices_body']!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFB45309),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        strings['delete_invoices_badge']!,
                        style: const TextStyle(
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      strings['delete_invoices_download']!,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(strings['cancel']!),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteCurrentAccount(Map<String, String> strings) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _deleteUserFirestoreData(user.uid);
      await user.delete();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const SignInPage(showDeletionFeedbackPrompt: true),
        ),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings['delete_failed']!}: $e')),
      );
    }
  }

  Future<void> _deleteUserFirestoreData(String uid) async {
    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection('users').doc(uid);
    for (final collection in const [
      'Schedule',
      'ProRating',
      'deviceTokens',
      'favorites',
      'likedBy',
      'notifications',
      'projects',
      'subscriptionPayments',
    ]) {
      while (true) {
        final snap = await userRef.collection(collection).limit(100).get();
        if (snap.docs.isEmpty) break;
        final batch = firestore.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }
    await userRef.delete();
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
                    onTap: _startDeleteAccountFlow,
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
                _startDeleteAccountFlow,
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

class _DeletePhoneVerificationPage extends StatefulWidget {
  final String phoneNumber;
  final Map<String, String> strings;

  const _DeletePhoneVerificationPage({
    required this.phoneNumber,
    required this.strings,
  });

  @override
  State<_DeletePhoneVerificationPage> createState() =>
      _DeletePhoneVerificationPageState();
}

class _DeleteDialogIcon extends StatelessWidget {
  final IconData icon;
  final bool destructive;

  const _DeleteDialogIcon({required this.icon, required this.destructive});

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? const Color(0xFFDC2626)
        : const Color(0xFF1976D2);
    final background = destructive
        ? const Color(0xFFFFE4E6)
        : const Color(0xFFE8F3FF);

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, color: color, size: 32),
    );
  }
}

class _DeletePhoneVerificationPageState
    extends State<_DeletePhoneVerificationPage> {
  final _codeController = TextEditingController();
  String _verificationId = '';
  bool _loading = false;
  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendCode());
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = widget.phoneNumber.trim();
    if (phone.isEmpty || phone == 'N/A') return;

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (credential) async {
          await _reauthenticate(credential);
        },
        verificationFailed: (e) {
          if (!mounted) return;
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${widget.strings['delete_code_failed']!}: ${e.message ?? e.code}',
              ),
            ),
          );
        },
        codeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _codeSent = true;
            _loading = false;
          });
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.strings['delete_code_failed']!}: $e')),
      );
    }
  }

  Future<void> _verifyCode() async {
    if (_verificationId.isEmpty || _codeController.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: _codeController.text.trim(),
      );
      await _reauthenticate(credential);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.strings['delete_code_failed']!}: $e')),
      );
    }
  }

  Future<void> _reauthenticate(PhoneAuthCredential credential) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await user.reauthenticateWithCredential(credential);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        title: Text(widget.strings['delete_verify_title']!),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.sms_outlined,
                    color: Color(0xFF1976D2),
                    size: 42,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.strings['delete_verify_title']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.strings['delete_verify_body']!.replaceFirst(
                      '{phone}',
                      widget.phoneNumber,
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _codeController,
                    enabled: _codeSent && !_loading,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: widget.strings['delete_code_label']!,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _loading
                        ? null
                        : (_codeSent ? _verifyCode : _sendCode),
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _codeSent
                                ? Icons.verified_outlined
                                : Icons.sms_outlined,
                          ),
                    label: Text(
                      _codeSent
                          ? widget.strings['delete_verify_code']!
                          : widget.strings['delete_send_code']!,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
