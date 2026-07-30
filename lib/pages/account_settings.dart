import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/pages/edit_profile.dart';
import 'package:untitled1/pages/help_page.dart';
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
  late String _currentEmail;
  String _userRole = "customer";
  bool _isBusinessVerified = false;

  @override
  void initState() {
    super.initState();
    _currentPhone =
        widget.userData['phone'] ??
        FirebaseAuth.instance.currentUser?.phoneNumber ??
        'N/A';
    _currentEmail =
        widget.userData['email'] ??
        FirebaseAuth.instance.currentUser?.email ??
        'N/A';
    _userRole = widget.userData['role'] ?? "customer";
    _isBusinessVerified = widget.userData['isVerified'] ?? false;
  }

  static Map<String, String> _getLocalizedStrings(
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
          'change_email': 'שנה אימייל',
          'change_password': 'שנה סיסמה',
          'email_secure_link': 'נשלח קישור מאובטח לכתובת האימייל החדשה שלך.',
          'confirm_current_email': 'אימות האימייל הנוכחי',
          'open_email': 'פתח את האימייל',
          'current_email_address': 'כתובת אימייל נוכחית',
          'new_email_address': 'כתובת אימייל חדשה',
          'send_verification_email': 'שלח אימייל אימות',
          'email_change_help':
              'נשלח קישור מאובטח לכתובת החדשה. האימייל ישתנה רק לאחר פתיחת הקישור.',
          'email_confirm_help':
              'אמת את האימייל שמחובר כעת לחשבון שלך לפני בחירת כתובת חדשה.',
          'verification_sent': 'אימייל אימות נשלח אל ',
          'enter_current_email': 'הזן את כתובת האימייל שמחוברת לחשבון שלך.',
          'enter_different_email': 'הזן כתובת אימייל חדשה ושונה.',
          'password_secure_link': 'נשלח לך קישור מאובטח להגדרת סיסמה חדשה.',
          'reset_your_password': 'איפוס הסיסמה שלך',
          'password_reset_help':
              'נשלח את קישור האיפוס לאימייל שמחובר לחשבון שלך.',
          'current_password': 'סיסמה נוכחית',
          'enter_current_password': 'הזן את הסיסמה הנוכחית שלך',
          'send_password_reset_email': 'שלח אימייל לאיפוס סיסמה',
          'secure_reset_link': 'קישור איפוס מאובטח',
          'secure_reset_help':
              'למען אבטחתך, ניתן לשנות את הסיסמה רק דרך הקישור שנשלח לאימייל שלך.',
          'password_reset_sent': 'אימייל לאיפוס סיסמה נשלח אל ',
          'no_linked_email': 'אין כתובת אימייל מקושרת לחשבון זה.',
          'password_required': 'הזן את הסיסמה הנוכחית כדי להמשיך.',
          'sending': 'שולח…',
          'phone_updated': 'מספר הטלפון עודכן בהצלחה',
          'change_phone_verify_title': 'אמת את המספר הנוכחי',
          'change_phone_verify_body':
              'לפני שינוי מספר הטלפון, אמת את המספר שמחובר כרגע לחשבון שלך.',
          'change_phone_verify_cta': 'אמת מספר נוכחי',
          'change_phone_confirm_title': 'להחליף מספר טלפון?',
          'change_phone_confirm_body':
              'לאחר שתמשיך, נעביר אותך למסך שבו תוכל להזין את מספר הטלפון החדש שלך.',
          'change_phone_confirm_continue': 'כן, המשך',
          'change_phone_code_failed': 'אימות מספר הטלפון נכשל',
          'change_phone_phone_mismatch':
              'המספר שהוזן לא תואם למספר הנוכחי של החשבון',
          'change_phone_no_access': 'אין לי גישה למספר הנוכחי',
          'change_phone_contact_title': 'אין גישה למספר הנוכחי?',
          'change_phone_contact_body':
              'כדי לשנות את מספר הטלפון בלי גישה למספר הנוכחי, צריך ליצור איתנו קשר.',
          'change_phone_open_help': 'פתח עזרה',
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
          'delete_verify_body':
              'הקלד את מספר הטלפון שלך ולאחר מכן נשלח אליו קוד SMS.',
          'delete_phone_label': 'מספר טלפון',
          'delete_phone_hint': 'לדוגמה: 0501234567',
          'delete_code_label': 'קוד SMS',
          'delete_send_code': 'שלח קוד',
          'delete_resend_code': 'שלח SMS שוב',
          'delete_verify_code': 'אמת קוד',
          'delete_final_title': 'אישור אחרון',
          'delete_final_body':
              'זה השלב האחרון. אחרי אישור, נמחק את החשבון וננתק אותך מהאפליקציה.',
          'delete_failed': 'מחיקת החשבון נכשלה',
          'delete_code_failed': 'האימות נכשל',
          'delete_phone_invalid':
              'אנא הכנס מספר טלפון ישראלי תקין (05XXXXXXXX)',
          'delete_phone_mismatch':
              'מספר הטלפון לא תואם למספר שמחובר לחשבון הזה',
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
          'change_email': 'تغيير البريد الإلكتروني',
          'change_password': 'تغيير كلمة المرور',
          'email_secure_link':
              'سنرسل رابطًا آمنًا إلى عنوان بريدك الإلكتروني الجديد.',
          'confirm_current_email': 'تأكيد البريد الإلكتروني الحالي',
          'open_email': 'افتح البريد الإلكتروني',
          'current_email_address': 'عنوان البريد الإلكتروني الحالي',
          'new_email_address': 'عنوان البريد الإلكتروني الجديد',
          'send_verification_email': 'إرسال بريد التحقق',
          'email_change_help':
              'سنرسل رابطًا آمنًا إلى العنوان الجديد. لن يتغير بريدك إلا بعد فتح الرابط.',
          'email_confirm_help':
              'أكد البريد الإلكتروني المرتبط حاليًا بحسابك قبل اختيار بريد جديد.',
          'verification_sent': 'تم إرسال بريد تحقق إلى ',
          'enter_current_email': 'أدخل عنوان البريد الإلكتروني المرتبط بحسابك.',
          'enter_different_email': 'أدخل عنوان بريد إلكتروني جديدًا ومختلفًا.',
          'password_secure_link':
              'سنرسل إليك رابطًا آمنًا لتعيين كلمة مرور جديدة.',
          'reset_your_password': 'إعادة تعيين كلمة المرور',
          'password_reset_help':
              'سنرسل رابط إعادة التعيين إلى البريد الإلكتروني المرتبط بحسابك.',
          'current_password': 'كلمة المرور الحالية',
          'enter_current_password': 'أدخل كلمة المرور الحالية',
          'send_password_reset_email': 'إرسال بريد إعادة تعيين كلمة المرور',
          'secure_reset_link': 'رابط إعادة تعيين آمن',
          'secure_reset_help':
              'لحمايتك، لا يمكن تغيير كلمة المرور إلا عبر الرابط المرسل إلى بريدك الإلكتروني.',
          'password_reset_sent': 'تم إرسال بريد إعادة تعيين كلمة المرور إلى ',
          'no_linked_email': 'لا يوجد بريد إلكتروني مرتبط بهذا الحساب.',
          'password_required': 'أدخل كلمة المرور الحالية للمتابعة.',
          'sending': 'جارٍ الإرسال…',
          'phone_updated': 'تم تحديث رقم الهاتف بنجاح',
          'change_phone_verify_title': 'تحقق من الرقم الحالي',
          'change_phone_verify_body':
              'قبل تغيير رقم الهاتف، قم بتأكيد الرقم المرتبط حاليًا بحسابك.',
          'change_phone_verify_cta': 'تحقق من الرقم الحالي',
          'change_phone_confirm_title': 'تغيير رقم الهاتف؟',
          'change_phone_confirm_body':
              'عند المتابعة سننقلك إلى الشاشة التي يمكنك فيها إدخال رقم الهاتف الجديد.',
          'change_phone_confirm_continue': 'نعم، تابع',
          'change_phone_code_failed': 'فشل التحقق من رقم الهاتف',
          'change_phone_phone_mismatch':
              'الرقم الذي أدخلته لا يطابق الرقم الحالي للحساب',
          'change_phone_no_access': 'ليس لدي وصول إلى الرقم الحالي',
          'change_phone_contact_title': 'لا يمكنك الوصول إلى الرقم الحالي؟',
          'change_phone_contact_body':
              'لتغيير رقم الهاتف بدون الوصول إلى الرقم الحالي، يجب التواصل معنا.',
          'change_phone_open_help': 'افتح صفحة المساعدة',
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
          'delete_verify_body': 'اكتب رقم هاتفك أولاً ثم سنرسل إليه رمز SMS.',
          'delete_phone_label': 'رقم الهاتف',
          'delete_phone_hint': 'مثال: 0501234567',
          'delete_code_label': 'رمز SMS',
          'delete_send_code': 'إرسال الرمز',
          'delete_resend_code': 'إرسال SMS مرة أخرى',
          'delete_verify_code': 'تأكيد الرمز',
          'delete_final_title': 'تأكيد أخير',
          'delete_final_body':
              'هذه هي الخطوة الأخيرة. بعد التأكيد سنحذف حسابك ونسجل خروجك من التطبيق.',
          'delete_failed': 'فشل حذف الحساب',
          'delete_code_failed': 'فشل التحقق',
          'delete_phone_invalid':
              'يرجى إدخال رقم هاتف إسرائيلي صالح (05XXXXXXXX)',
          'delete_phone_mismatch':
              'رقم الهاتف لا يطابق الرقم المرتبط بهذا الحساب',
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
          'change_email': 'ኢሜይል ቀይር',
          'change_password': 'የይለፍ ቃል ቀይር',
          'email_secure_link': 'ወደ አዲሱ የኢሜይል አድራሻዎ ደህንነቱ የተጠበቀ ሊንክ እንልካለን።',
          'confirm_current_email': 'አሁን ያለውን ኢሜይል ያረጋግጡ',
          'open_email': 'ኢሜይሉን ይክፈቱ',
          'current_email_address': 'አሁን ያለው የኢሜይል አድራሻ',
          'new_email_address': 'አዲስ የኢሜይል አድራሻ',
          'send_verification_email': 'የማረጋገጫ ኢሜይል ላክ',
          'email_change_help':
              'ወደ አዲሱ አድራሻ ደህንነቱ የተጠበቀ ሊንክ እንልካለን። ሊንኩን ከከፈቱ በኋላ ብቻ ኢሜይሉ ይቀየራል።',
          'email_confirm_help':
              'አዲስ ከመምረጥዎ በፊት በአሁኑ ጊዜ ከመለያዎ ጋር የተገናኘውን ኢሜይል ያረጋግጡ።',
          'verification_sent': 'የማረጋገጫ ኢሜይል ተልኳል ወደ ',
          'enter_current_email': 'ከመለያዎ ጋር የተገናኘውን ኢሜይል ያስገቡ።',
          'enter_different_email': 'የተለየ አዲስ የኢሜይል አድራሻ ያስገቡ።',
          'password_secure_link':
              'አዲስ የይለፍ ቃል ለማዘጋጀት ደህንነቱ የተጠበቀ ሊንክ በኢሜይል እንልክልዎታለን።',
          'reset_your_password': 'የይለፍ ቃልዎን ዳግም ያስጀምሩ',
          'password_reset_help':
              'የዳግም ማስጀመሪያ ሊንኩን ከመለያዎ ጋር ወደተገናኘው ኢሜይል እንልካለን።',
          'current_password': 'የአሁኑ የይለፍ ቃል',
          'enter_current_password': 'የአሁኑን የይለፍ ቃል ያስገቡ',
          'send_password_reset_email': 'የይለፍ ቃል ዳግም ማስጀመሪያ ኢሜይል ላክ',
          'secure_reset_link': 'ደህንነቱ የተጠበቀ የዳግም ማስጀመሪያ ሊንክ',
          'secure_reset_help':
              'ለደህንነትዎ የይለፍ ቃሉ መቀየር የሚችለው ወደ ኢሜይልዎ በተላከው ሊንክ ብቻ ነው።',
          'password_reset_sent': 'የይለፍ ቃል ዳግም ማስጀመሪያ ኢሜይል ተልኳል ወደ ',
          'no_linked_email': 'ከዚህ መለያ ጋር የተገናኘ ኢሜይል የለም።',
          'password_required': 'ለመቀጠል የአሁኑን የይለፍ ቃል ያስገቡ።',
          'sending': 'በመላክ ላይ…',
          'phone_updated': 'የስልክ ቁጥር በተሳካ ሁኔታ ተዘምኗል',
          'change_phone_verify_title': 'ያለውን ቁጥር ያረጋግጡ',
          'change_phone_verify_body':
              'የስልክ ቁጥርዎን ከመቀየርዎ በፊት አሁን ከመለያዎ ጋር የተገናኘውን ቁጥር ያረጋግጡ።',
          'change_phone_verify_cta': 'ያለውን ቁጥር ያረጋግጡ',
          'change_phone_confirm_title': 'የስልክ ቁጥር ይቀየር?',
          'change_phone_confirm_body':
              'ከቀጠሉ አዲሱን የስልክ ቁጥርዎን ማስገባት ወደሚችሉበት ገጽ እንወስድዎታለን።',
          'change_phone_confirm_continue': 'አዎ፣ ቀጥል',
          'change_phone_code_failed': 'የስልክ ቁጥር ማረጋገጫ አልተሳካም',
          'change_phone_phone_mismatch':
              'ያስገቡት ቁጥር ከመለያው አሁን ካለው ቁጥር ጋር አይዛመድም',
          'change_phone_no_access': 'አሁን ያለውን ቁጥር ማግኘት አልችልም',
          'change_phone_contact_title': 'ያለውን ቁጥር ማግኘት አልቻሉም?',
          'change_phone_contact_body':
              'አሁን ያለውን ቁጥር ሳይደርሱበት የስልክ ቁጥርዎን ለመቀየር እባክዎ ከእኛ ጋር ይገናኙ።',
          'change_phone_open_help': 'የእገዛ ገጽ ክፈት',
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
          'delete_verify_body': 'መጀመሪያ የስልክ ቁጥርዎን ያስገቡ ከዚያ የSMS ኮድ እንልካለን።',
          'delete_phone_label': 'ስልክ ቁጥር',
          'delete_phone_hint': 'ለምሳሌ፡ 0501234567',
          'delete_code_label': 'SMS ኮድ',
          'delete_send_code': 'ኮድ ላክ',
          'delete_resend_code': 'SMS እንደገና ላክ',
          'delete_verify_code': 'ኮድ አረጋግጥ',
          'delete_final_title': 'የመጨረሻ ማረጋገጫ',
          'delete_final_body': 'ይህ የመጨረሻው ደረጃ ነው። ካረጋገጡ መለያዎን እንሰርዛለን።',
          'delete_failed': 'መለያውን መሰረዝ አልተሳካም',
          'delete_code_failed': 'ማረጋገጫው አልተሳካም',
          'delete_phone_invalid':
              'እባክዎ ትክክለኛ የእስራኤል የስልክ ቁጥር ያስገቡ (05XXXXXXXX)',
          'delete_phone_mismatch': 'የስልክ ቁጥሩ ከዚህ መለያ ጋር ከተገናኘው ቁጥር ጋር አይዛመድም',
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
          'change_email': 'Изменить email',
          'change_password': 'Изменить пароль',
          'email_secure_link':
              'Мы отправим защищенную ссылку на ваш новый адрес электронной почты.',
          'confirm_current_email': 'Подтвердите текущий email',
          'open_email': 'Откройте email',
          'current_email_address': 'Текущий адрес email',
          'new_email_address': 'Новый адрес email',
          'send_verification_email': 'Отправить письмо для подтверждения',
          'email_change_help':
              'Мы отправим защищенную ссылку на новый адрес. Email изменится только после открытия ссылки.',
          'email_confirm_help':
              'Подтвердите email, который сейчас привязан к аккаунту, прежде чем выбрать новый.',
          'verification_sent': 'Письмо для подтверждения отправлено на ',
          'enter_current_email':
              'Введите адрес email, привязанный к вашему аккаунту.',
          'enter_different_email': 'Введите другой новый адрес email.',
          'password_secure_link':
              'Мы отправим вам защищенную ссылку для установки нового пароля.',
          'reset_your_password': 'Сброс пароля',
          'password_reset_help':
              'Мы отправим ссылку для сброса на email, привязанный к вашему аккаунту.',
          'current_password': 'Текущий пароль',
          'enter_current_password': 'Введите текущий пароль',
          'send_password_reset_email': 'Отправить письмо для сброса пароля',
          'secure_reset_link': 'Защищенная ссылка для сброса',
          'secure_reset_help':
              'Для вашей безопасности пароль можно изменить только по ссылке, отправленной на ваш email.',
          'password_reset_sent': 'Письмо для сброса пароля отправлено на ',
          'no_linked_email': 'К этому аккаунту не привязан адрес email.',
          'password_required': 'Введите текущий пароль, чтобы продолжить.',
          'sending': 'Отправка…',
          'phone_updated': 'Номер телефона успешно обновлен',
          'change_phone_verify_title': 'Подтвердите текущий номер',
          'change_phone_verify_body':
              'Перед изменением номера телефона подтвердите номер, который сейчас привязан к аккаунту.',
          'change_phone_verify_cta': 'Подтвердить текущий номер',
          'change_phone_confirm_title': 'Изменить номер телефона?',
          'change_phone_confirm_body':
              'После продолжения мы переведем вас на экран, где можно будет ввести новый номер телефона.',
          'change_phone_confirm_continue': 'Да, продолжить',
          'change_phone_code_failed': 'Не удалось подтвердить номер телефона',
          'change_phone_phone_mismatch':
              'Введенный номер не совпадает с текущим номером аккаунта',
          'change_phone_no_access': 'У меня нет доступа к текущему номеру',
          'change_phone_contact_title': 'Нет доступа к текущему номеру?',
          'change_phone_contact_body':
              'Чтобы изменить номер телефона без доступа к текущему номеру, нужно связаться с нами.',
          'change_phone_open_help': 'Открыть помощь',
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
          'delete_verify_body':
              'Сначала введите свой номер телефона, затем мы отправим на него SMS-код.',
          'delete_phone_label': 'Номер телефона',
          'delete_phone_hint': 'например: 0501234567',
          'delete_code_label': 'SMS-код',
          'delete_send_code': 'Отправить код',
          'delete_resend_code': 'Отправить SMS снова',
          'delete_verify_code': 'Подтвердить код',
          'delete_final_title': 'Последнее подтверждение',
          'delete_final_body':
              'Это последний шаг. После подтверждения мы удалим аккаунт и выйдем из приложения.',
          'delete_failed': 'Не удалось удалить аккаунт',
          'delete_code_failed': 'Проверка не удалась',
          'delete_phone_invalid':
              'Введите корректный израильский номер телефона (05XXXXXXXX)',
          'delete_phone_mismatch':
              'Номер телефона не совпадает с номером этого аккаунта',
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
          'change_email': 'Change Email',
          'change_password': 'Change Password',
          'email_secure_link':
              'We will send a secure link to your new email address.',
          'confirm_current_email': 'Confirm current email',
          'open_email': 'Open the email',
          'current_email_address': 'Current email address',
          'new_email_address': 'New email address',
          'send_verification_email': 'Send verification email',
          'email_change_help':
              'We will send a secure link to the new address. Your email changes only after you open the link.',
          'email_confirm_help':
              'Confirm the email currently connected to your account before choosing a new one.',
          'verification_sent': 'A verification email was sent to ',
          'enter_current_email':
              'Enter the email address currently linked to your account.',
          'enter_different_email': 'Enter a different new email address.',
          'password_secure_link':
              'We will email you a secure link to set a new password.',
          'reset_your_password': 'Reset your password',
          'password_reset_help':
              'We will send the reset link to the email connected to your account.',
          'current_password': 'Current password',
          'enter_current_password': 'Enter your current password',
          'send_password_reset_email': 'Send password reset email',
          'secure_reset_link': 'A secure reset link',
          'secure_reset_help':
              'For your security, the password can only be changed through the link sent to your email.',
          'password_reset_sent': 'A password reset email was sent to ',
          'no_linked_email': 'No email address is linked to this account.',
          'password_required': 'Enter your current password to continue.',
          'sending': 'Sending…',
          'phone_updated': 'Phone number updated successfully',
          'change_phone_verify_title': 'Verify your current number',
          'change_phone_verify_body':
              'Before changing your phone number, verify the number currently connected to your account.',
          'change_phone_verify_cta': 'Verify Current Number',
          'change_phone_confirm_title': 'Change phone number?',
          'change_phone_confirm_body':
              'If you continue, we will take you to the page where you can enter your new phone number.',
          'change_phone_confirm_continue': 'Yes, continue',
          'change_phone_code_failed': 'Phone number verification failed',
          'change_phone_phone_mismatch':
              'The number you entered does not match the current account number',
          'change_phone_no_access': "I don't have access to my current number",
          'change_phone_contact_title': "Can't access your current number?",
          'change_phone_contact_body':
              'To change your phone number without access to the current number, you need to contact us.',
          'change_phone_open_help': 'Open Help Page',
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
          'delete_verify_body':
              'Type your phone number first, then we will send an SMS code.',
          'delete_phone_label': 'Phone Number',
          'delete_phone_hint': 'e.g. 0501234567',
          'delete_code_label': 'SMS Code',
          'delete_send_code': 'Send Code',
          'delete_resend_code': 'Send SMS Again',
          'delete_verify_code': 'Verify Code',
          'delete_final_title': 'Final confirmation',
          'delete_final_body':
              'This is the last step. If you confirm, we will delete your account and sign you out.',
          'delete_failed': 'Failed to delete account',
          'delete_code_failed': 'Verification failed',
          'delete_phone_invalid':
              'Please enter a valid Israeli phone number (05XXXXXXXX)',
          'delete_phone_mismatch':
              'The phone number does not match this account',
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
        builder: (context) => _CurrentPhoneVerificationPage(
          currentPhone: _currentPhone,
          strings: _getLocalizedStrings(context, listen: false),
        ),
      ),
    ).then((verified) async {
      if (verified != true || !mounted) return;

      final strings = _getLocalizedStrings(context, listen: false);
      final wantsToChange = await _showDeleteStepDialog(
        title: strings['change_phone_confirm_title']!,
        body: strings['change_phone_confirm_body']!,
        primaryLabel: strings['change_phone_confirm_continue']!,
        secondaryLabel: strings['cancel']!,
        icon: Icons.phone_android_outlined,
      );
      if (wantsToChange != true || !mounted) return;

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
    });
  }

  Future<void> _onChangeEmail() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _ChangeEmailPage(
          strings: _getLocalizedStrings(context, listen: false),
        ),
      ),
    );
  }

  Future<void> _onChangePassword() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _ChangePasswordPage(
          strings: _getLocalizedStrings(context, listen: false),
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

    final email = _currentEmail;
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
                  CupertinoListTile(
                    leading: const Icon(
                      CupertinoIcons.envelope,
                      color: CupertinoColors.systemBlue,
                    ),
                    title: Text(strings['change_email']!),
                    trailing: const CupertinoListTileChevron(),
                    onTap: _onChangeEmail,
                  ),
                  CupertinoListTile(
                    leading: const Icon(
                      CupertinoIcons.lock,
                      color: CupertinoColors.systemBlue,
                    ),
                    title: Text(strings['change_password']!),
                    trailing: const CupertinoListTileChevron(),
                    onTap: _onChangePassword,
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
              const Divider(height: 1, indent: 50),
              _buildTile(
                Icons.email_outlined,
                strings['change_email']!,
                _onChangeEmail,
              ),
              const Divider(height: 1, indent: 50),
              _buildTile(
                Icons.lock_outline,
                strings['change_password']!,
                _onChangePassword,
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

class _ChangeEmailPage extends StatefulWidget {
  final Map<String, String> strings;
  const _ChangeEmailPage({required this.strings});

  @override
  State<_ChangeEmailPage> createState() => _ChangeEmailPageState();
}

class _ChangeEmailPageState extends State<_ChangeEmailPage> {
  final _currentEmailController = TextEditingController();
  final _newEmailController = TextEditingController();
  bool _isLoading = false;
  String _t(String key) => widget.strings[key]!;

  @override
  void dispose() {
    _currentEmailController.dispose();
    _newEmailController.dispose();
    super.dispose();
  }

  Future<void> _sendVerificationEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    final accountEmail = user?.email;
    final currentEmail = _currentEmailController.text.trim();
    final newEmail = _newEmailController.text.trim();
    if (user == null || accountEmail == null || accountEmail.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t('no_linked_email'))));
      return;
    }
    if (currentEmail.toLowerCase() != accountEmail.toLowerCase()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t('enter_current_email'))));
      return;
    }
    if (newEmail.isEmpty ||
        newEmail.toLowerCase() == accountEmail.toLowerCase()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t('enter_different_email'))));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await user.verifyBeforeUpdateEmail(newEmail);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_t('verification_sent')}$newEmail')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        title: Text(_t('change_email')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('change_email'),
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t('email_secure_link'),
                    style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 28),
                  _progressIndicator(),
                  const SizedBox(height: 28),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final changeCard = _buildChangeCard();
                      final infoCard = _buildInfoCard();
                      return constraints.maxWidth >= 620
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: changeCard),
                                const SizedBox(width: 20),
                                Expanded(child: infoCard),
                              ],
                            )
                          : Column(
                              children: [
                                changeCard,
                                const SizedBox(height: 20),
                                infoCard,
                              ],
                            );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressIndicator() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
    ),
    child: Row(
      children: [
        Expanded(
          child: _ProgressStep(
            icon: Icons.shield_outlined,
            label: _t('confirm_current_email'),
            active: true,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _ProgressStep(
            icon: Icons.email_outlined,
            label: _t('change_email'),
            active: true,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _ProgressStep(
            icon: Icons.check_circle_outline,
            label: _t('open_email'),
          ),
        ),
      ],
    ),
  );

  Widget _buildChangeCard() => _emailCard(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _CardIcon(icon: Icons.email_outlined),
            SizedBox(width: 14),
            Text(
              _t('change_email'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          _t('email_change_help'),
          style: TextStyle(
            fontSize: 16,
            height: 1.45,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _t('current_email_address'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _emailField(_currentEmailController, 'current@example.com'),
        const SizedBox(height: 20),
        Text(
          _t('new_email_address'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _emailField(_newEmailController, 'new@example.com'),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isLoading ? null : _sendVerificationEmail,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(
              _isLoading ? _t('sending') : _t('send_verification_email'),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 17),
              backgroundColor: const Color(0xFF1976D2),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _emailField(TextEditingController controller, String hint) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: InputDecoration(
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );

  Widget _buildInfoCard() => _emailCard(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardIcon(icon: Icons.shield_outlined),
        SizedBox(height: 24),
        Text(
          _t('confirm_current_email'),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 14),
        Text(
          _t('email_confirm_help'),
          style: TextStyle(fontSize: 16, height: 1.5, color: Color(0xFF6B7280)),
        ),
      ],
    ),
  );

  Widget _emailCard(Widget child) => Container(
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
    ),
    child: child,
  );
}

class _ProgressStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _ProgressStep({
    required this.icon,
    required this.label,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
    decoration: BoxDecoration(
      color: active ? const Color(0xFFE3F2FD) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        Icon(
          icon,
          color: active ? const Color(0xFF1976D2) : const Color(0xFF94A3B8),
          size: 21,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: active ? const Color(0xFF1976D2) : const Color(0xFF94A3B8),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ChangePasswordPage extends StatefulWidget {
  final Map<String, String> strings;
  const _ChangePasswordPage({required this.strings});

  @override
  State<_ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<_ChangePasswordPage> {
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String _t(String key) => widget.strings[key]!;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendPasswordResetEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    final password = _passwordController.text;
    if (user == null || email == null || email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t('no_linked_email'))));
      return;
    }
    if (password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t('password_required'))));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_t('password_reset_sent')}$email')),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email =
        FirebaseAuth.instance.currentUser?.email ?? _t('no_linked_email');
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        title: Text(_t('change_password')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('change_password'),
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t('password_secure_link'),
                    style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 28),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 620;
                      final resetCard = _buildResetCard(email);
                      final infoCard = _buildInfoCard();
                      return isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: resetCard),
                                const SizedBox(width: 20),
                                Expanded(child: infoCard),
                              ],
                            )
                          : Column(
                              children: [
                                resetCard,
                                const SizedBox(height: 20),
                                infoCard,
                              ],
                            );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResetCard(String email) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CardIcon(icon: Icons.key_outlined),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  _t('reset_your_password'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _t('password_reset_help'),
            style: TextStyle(
              fontSize: 16,
              height: 1.45,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              email,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _t('current_password'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: _t('enter_current_password'),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _sendPasswordResetEmail,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _isLoading ? _t('sending') : _t('send_password_reset_email'),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 17),
                backgroundColor: const Color(0xFF1976D2),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardIcon(icon: Icons.email_outlined),
        SizedBox(height: 24),
        Text(
          _t('secure_reset_link'),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 14),
        Text(
          _t('secure_reset_help'),
          style: TextStyle(fontSize: 16, height: 1.5, color: Color(0xFF6B7280)),
        ),
      ],
    ),
  );

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
    ),
    child: child,
  );
}

class _CardIcon extends StatelessWidget {
  final IconData icon;
  const _CardIcon({required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    width: 64,
    decoration: BoxDecoration(
      color: const Color(0xFFE3F2FD),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Icon(icon, color: const Color(0xFF1976D2), size: 30),
  );
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

class _CurrentPhoneVerificationPage extends StatefulWidget {
  final String currentPhone;
  final Map<String, String> strings;

  const _CurrentPhoneVerificationPage({
    required this.currentPhone,
    required this.strings,
  });

  @override
  State<_CurrentPhoneVerificationPage> createState() =>
      _CurrentPhoneVerificationPageState();
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

class _CurrentPhoneVerificationPageState
    extends State<_CurrentPhoneVerificationPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  String _verificationId = '';
  int? _resendToken;
  bool _loading = false;
  bool _codeSent = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String _normalizePhone(String input) {
    String digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('972')) {
      digits = digits.substring(3);
    }
    while (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '+972$digits';
  }

  Future<void> _sendCode() async {
    final enteredPhone = _phoneController.text.trim();
    if (enteredPhone.isEmpty) return;

    final phone = _normalizePhone(enteredPhone);
    final expectedPhone = _normalizePhone(widget.currentPhone.trim());
    final regExp = RegExp(r'^\+9725\d{8}$');

    if (!regExp.hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings['delete_phone_invalid']!)),
      );
      return;
    }

    if (phone != expectedPhone) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings['change_phone_phone_mismatch']!)),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        forceResendingToken: _resendToken,
        verificationCompleted: (credential) async {
          await _reauthenticate(credential);
        },
        verificationFailed: (e) {
          if (!mounted) return;
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${widget.strings['change_phone_code_failed']!}: ${e.message ?? e.code}',
              ),
            ),
          );
        },
        codeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
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
        SnackBar(
          content: Text('${widget.strings['change_phone_code_failed']!}: $e'),
        ),
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
        SnackBar(
          content: Text('${widget.strings['change_phone_code_failed']!}: $e'),
        ),
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

  Future<void> _showContactDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings['change_phone_contact_title']!),
        content: Text(widget.strings['change_phone_contact_body']!),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                this.context,
                MaterialPageRoute(builder: (_) => const HelpPage()),
              );
            },
            child: Text(widget.strings['change_phone_open_help']!),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.strings['close'] ?? widget.strings['cancel']!),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        title: Text(widget.strings['change_phone_verify_title']!),
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
                    Icons.phone_locked_outlined,
                    color: Color(0xFF1976D2),
                    size: 42,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.strings['change_phone_verify_title']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.strings['change_phone_verify_body']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _phoneController,
                    enabled: !_codeSent && !_loading,
                    keyboardType: TextInputType.phone,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: widget.strings['phone']!,
                      hintText: widget.currentPhone,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                          : widget.strings['change_phone_verify_cta']!,
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
                  if (_codeSent) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: _loading ? null : _sendCode,
                        child: Text(widget.strings['delete_resend_code']!),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: _loading ? null : _showContactDialog,
                        child: Text(widget.strings['change_phone_no_access']!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeletePhoneVerificationPageState
    extends State<_DeletePhoneVerificationPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  String _verificationId = '';
  int? _resendToken;
  bool _loading = false;
  bool _codeSent = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String _normalizePhone(String input) {
    String digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('972')) {
      digits = digits.substring(3);
    }
    while (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '+972$digits';
  }

  Future<void> _sendCode() async {
    final enteredPhone = _phoneController.text.trim();
    if (enteredPhone.isEmpty) return;

    final phone = _normalizePhone(enteredPhone);
    final expectedPhone = _normalizePhone(widget.phoneNumber.trim());
    final regExp = RegExp(r'^\+9725\d{8}$');

    if (!regExp.hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings['delete_phone_invalid']!)),
      );
      return;
    }

    if (phone != expectedPhone) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings['delete_phone_mismatch']!)),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        forceResendingToken: _resendToken,
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
            _resendToken = resendToken;
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
                    widget.strings['delete_verify_body']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _phoneController,
                    enabled: !_codeSent && !_loading,
                    keyboardType: TextInputType.phone,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: widget.strings['delete_phone_label']!,
                      hintText: widget.strings['delete_phone_hint'],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                  if (_codeSent) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: _loading ? null : _sendCode,
                        child: Text(widget.strings['delete_resend_code']!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
