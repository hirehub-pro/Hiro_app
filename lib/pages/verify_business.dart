import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/utils/israeli_id_validator.dart';

class VerifyBusinessPage extends StatefulWidget {
  const VerifyBusinessPage({super.key});

  @override
  State<VerifyBusinessPage> createState() => _VerifyBusinessPageState();
}

class _VerifyBusinessPageState extends State<VerifyBusinessPage> {
  static const _primary = Color(0xFF1976D2);
  static const _ink = Color(0xFF07101F);
  static const _muted = Color(0xFF667085);
  static const _page = Color(0xFFF4F9FF);
  static const _line = Color(0xFFE2EAF3);

  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _streetController = TextEditingController();
  final _houseNumberController = TextEditingController();
  final _cityController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _branchNumberController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'me-west1',
  );

  String _dealerType = 'exempt';
  bool _isUploading = false;
  bool _isLoadingStatus = true;
  String? _currentStatus;
  File? _businessLogo;
  String? _businessLogoUrl;
  String? _businessSignatureUrl;
  final List<Offset?> _signaturePoints = [];

  bool _acceptedTerms = false;
  bool _isLegalDeclarationSigned = false;
  bool _acceptedResponsibility = false;
  bool _hasBranches = false;

  bool get _isBusinessApproved =>
      _currentStatus == 'approved' || _currentStatus == 'verified';

  @override
  void initState() {
    super.initState();
    _checkCurrentStatus();
  }

  @override
  void dispose() {
    _idController.dispose();
    _businessNameController.dispose();
    _streetController.dispose();
    _houseNumberController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    _branchNumberController.dispose();
    super.dispose();
  }

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = context.read<LanguageProvider>().locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'page_title': 'אימות זהות ועסק',
          'verification_intro':
              'כמה פרטים קצרים ואתה בדרך לפרופיל עסקי אמין ומאומת.',
          'secure_review':
              'המידע נשמר בצורה מאובטחת ונבדק בדרך כלל תוך 48 שעות.',
          'accept_all_legal': 'עליך לאשר את כל ההצהרות החוקיות',
          'business_id_connected': 'מספר העסק הזה כבר מחובר לחשבון אחר',
          'request_submitted': 'הבקשה הוגשה בהצלחה',
          'submitted_for_review':
              'המסמכים הועברו לבדיקה. סטטוס החשבון יעודכן תוך 48 שעות.',
          'got_it': 'הבנתי',
          'uploading': 'מעלה מסמכים ומאמת...',
          'step_business': 'פרטי העסק והרישום',
          'business_name': 'שם העסק הרשום',
          'business_id': 'מספר עוסק / ח.פ / ת.ז',
          'business_street': 'רחוב (אופציונלי)',
          'business_house_number': 'מספר בית (אופציונלי)',
          'business_city': 'עיר (אופציונלי)',
          'business_postal_code': 'מיקוד (אופציונלי)',
          'has_branches': 'האם לעסק יש סניפים?',
          'branch_number': 'מספר סניף',
          'branch_number_invalid': 'יש להזין מספר סניף של 1–7 ספרות',
          'business_logo': 'לוגו העסק',
          'business_logo_optional': 'לוגו העסק (אופציונלי)',
          'business_logo_hint': 'הלוגו יוצג במסמכים העסקיים שתפיק.',
          'document_branding': 'לוגו וחתימה למסמכים',
          'document_branding_hint':
              'אופציונלי. הלוגו והחתימה ישמשו רק במסמכים העסקיים שתפיק.',
          'add_logo': 'הוסף לוגו',
          'change_logo': 'החלף לוגו',
          'remove_logo': 'הסר לוגו',
          'business_signature_optional': 'חתימת העסק (אופציונלי)',
          'business_signature_hint':
              'חתום בתוך התיבה. החתימה תישמר למסמכים העסקיים שלך.',
          'draw_signature': 'חתום כאן',
          'tap_to_draw_signature': 'לחץ כדי לפתוח את משטח החתימה',
          'clear_signature': 'נקה חתימה',
          'save_signature': 'שמור חתימה',
          'cancel': 'ביטול',
          'required': 'חובה',
          'business_id_9_digits': 'מספר העסק חייב להכיל 9 ספרות',
          'business_id_invalid': 'מספר העוסק / ח.פ / ת.ז אינו תקין',
          'business_id_locked_title': 'לא ניתן לשנות את מספר העסק',
          'business_id_locked_message':
              'לאחר אימות העסק, לא ניתן לשנות את מספר העוסק / ח.פ / ת.ז. כדי להשתמש במספר עסק אחר, יש לפתוח חשבון חדש.',
          'close': 'סגור',
          'step_classification': 'סיווג עוסק לצרכי מס',
          'classification_note':
              'שים לב: הגדרה זו תקבע את סוגי המסמכים (חשבונית/קבלה) שתוכל להפיק.',
          'dealer_exempt': 'עוסק פטור',
          'dealer_licensed': 'עוסק מורשה',
          'dealer_company': 'חברה בע״מ',
          'step_legal': 'אישורים והצהרות משפטיות',
          'legal_terms': 'קראתי ואני מסכים לתנאי השימוש וכללי האתיקה של הירו.',
          'legal_declaration': 'אני מצהיר כי כל המידע שמסרתי נכון, תקף ומקורי.',
          'legal_responsibility': 'אני אחראי לכל מידע שגוי או מטעה שאמסור לכם.',
          'submit': 'שלח לאישור משפטי',
          'verification_pending': 'הבקשה בבדיקה',
          'business_verified': 'העסק מאומת',
          'pending_message':
              'שלחת כבר בקשת אימות. הצוות שלנו בודק את המסמכים שלך. בדרך כלל זה לוקח עד 48 שעות.',
          'verified_message': 'מזל טוב! העסק שלך מאומת במערכת.',
          'back_to_profile': 'חזור לפרופיל',
          'rejected_notice':
              'בקשת האימות הקודמת שלך נדחתה. אנא בדוק את המסמכים ושלח שוב.',
          'error_prefix': 'שגיאה: ',
        };
      case 'ar':
        return {
          'page_title': 'التحقق من الهوية والنشاط التجاري',
          'verification_intro':
              'بضع تفاصيل قصيرة تفصلك عن ملف تجاري موثوق وموثّق.',
          'secure_review':
              'تُحفظ معلوماتك بأمان وتتم مراجعتها عادة خلال 48 ساعة.',
          'accept_all_legal': 'يجب عليك الموافقة على جميع الإقرارات القانونية',
          'business_id_connected':
              'رقم النشاط التجاري هذا مرتبط بالفعل بحساب آخر',
          'request_submitted': 'تم إرسال الطلب بنجاح',
          'submitted_for_review':
              'تم إرسال المستندات للمراجعة. سيتم تحديث حالة الحساب خلال 48 ساعة.',
          'got_it': 'فهمت',
          'uploading': 'جارٍ رفع المستندات والتحقق...',
          'step_business': 'تفاصيل النشاط والتسجيل',
          'business_name': 'الاسم التجاري المسجل',
          'business_id': 'رقم النشاط / ضريبة القيمة المضافة / الهوية',
          'business_street': 'الشارع (اختياري)',
          'business_house_number': 'رقم المنزل (اختياري)',
          'business_city': 'المدينة (اختياري)',
          'business_postal_code': 'الرمز البريدي (اختياري)',
          'has_branches': 'هل للنشاط التجاري فروع؟',
          'branch_number': 'رقم الفرع',
          'branch_number_invalid': 'أدخل رقم فرع يتكون من 1–7 أرقام',
          'business_logo': 'شعار النشاط التجاري',
          'business_logo_optional': 'شعار النشاط التجاري (اختياري)',
          'business_logo_hint':
              'سيظهر الشعار على مستندات النشاط التجاري التي تنشئها.',
          'document_branding': 'الشعار والتوقيع للمستندات',
          'document_branding_hint':
              'اختياري. سيُستخدم الشعار والتوقيع فقط في مستندات النشاط التجاري التي تنشئها.',
          'add_logo': 'إضافة شعار',
          'change_logo': 'تغيير الشعار',
          'remove_logo': 'إزالة الشعار',
          'business_signature_optional': 'توقيع النشاط التجاري (اختياري)',
          'business_signature_hint':
              'وقّع داخل المربع. سيتم حفظ التوقيع لمستندات نشاطك التجاري.',
          'draw_signature': 'وقّع هنا',
          'tap_to_draw_signature': 'اضغط لفتح لوحة التوقيع',
          'clear_signature': 'مسح التوقيع',
          'save_signature': 'حفظ التوقيع',
          'cancel': 'إلغاء',
          'required': 'مطلوب',
          'business_id_9_digits': 'يجب أن يتكون رقم النشاط من 9 أرقام بالضبط',
          'business_id_invalid':
              'رقم النشاط التجاري / الشركة / الهوية الإسرائيلية غير صالح',
          'business_id_locked_title': 'لا يمكن تغيير رقم النشاط التجاري',
          'business_id_locked_message':
              'بعد توثيق النشاط التجاري، لا يمكن تغيير رقم النشاط / ضريبة القيمة المضافة / الهوية. لاستخدام رقم نشاط آخر، يجب فتح حساب جديد.',
          'close': 'إغلاق',
          'step_classification': 'تصنيف دافع الضريبة',
          'classification_note':
              'ملاحظة: هذا الإعداد يحدد أنواع المستندات (فاتورة/إيصال) التي يمكنك إصدارها.',
          'dealer_exempt': 'تاجر معفى',
          'dealer_licensed': 'تاجر مرخص',
          'dealer_company': 'شركة ذات مسؤولية محدودة',
          'step_legal': 'إقرارات قانونية',
          'legal_terms':
              'لقد قرأت ووافقت على شروط الاستخدام ومدونة الأخلاقيات الخاصة بـ hiro.',
          'legal_declaration':
              'أقر بأن جميع المعلومات المقدمة صحيحة وسارية وأصلية.',
          'legal_responsibility':
              'أتحمل مسؤولية أي معلومات خاطئة أو مضللة أقدمها.',
          'submit': 'إرسال للمراجعة القانونية',
          'verification_pending': 'الطلب قيد المراجعة',
          'business_verified': 'تم التحقق من النشاط التجاري',
          'pending_message':
              'لقد أرسلت طلب تحقق بالفعل. فريقنا يراجع مستنداتك الآن. يستغرق هذا عادة حتى 48 ساعة.',
          'verified_message': 'تهانينا! تم التحقق من نشاطك التجاري في النظام.',
          'back_to_profile': 'العودة إلى الملف الشخصي',
          'rejected_notice':
              'تم رفض طلب التحقق السابق. يرجى مراجعة مستنداتك وإعادة الإرسال.',
          'error_prefix': 'خطأ: ',
        };
      case 'ru':
        return {
          'page_title': 'Подтверждение личности и бизнеса',
          'verification_intro':
              'Несколько коротких шагов — и ваш бизнес-профиль станет подтвержденным.',
          'secure_review':
              'Данные хранятся безопасно и обычно проверяются в течение 48 часов.',
          'accept_all_legal': 'Вы должны принять все юридические подтверждения',
          'business_id_connected':
              'Этот бизнес-идентификатор уже привязан к другой учетной записи',
          'request_submitted': 'Запрос успешно отправлен',
          'submitted_for_review':
              'Документы отправлены на проверку. Статус аккаунта будет обновлен в течение 48 часов.',
          'got_it': 'Понятно',
          'uploading': 'Загрузка документов и проверка...',
          'step_business': 'Данные бизнеса и регистрации',
          'business_name': 'Зарегистрированное название бизнеса',
          'business_id': 'Бизнес ID / VAT ID',
          'business_street': 'Улица (необязательно)',
          'business_house_number': 'Номер дома (необязательно)',
          'business_city': 'Город (необязательно)',
          'business_postal_code': 'Почтовый индекс (необязательно)',
          'has_branches': 'У бизнеса есть филиалы?',
          'branch_number': 'Номер филиала',
          'branch_number_invalid': 'Введите номер филиала из 1–7 цифр',
          'business_logo': 'Логотип бизнеса',
          'business_logo_optional': 'Логотип бизнеса (необязательно)',
          'business_logo_hint':
              'Логотип будет отображаться на создаваемых вами деловых документах.',
          'document_branding': 'Логотип и подпись для документов',
          'document_branding_hint':
              'Необязательно. Логотип и подпись будут использоваться только в создаваемых вами деловых документах.',
          'add_logo': 'Добавить логотип',
          'change_logo': 'Изменить логотип',
          'remove_logo': 'Удалить логотип',
          'business_signature_optional': 'Подпись компании (необязательно)',
          'business_signature_hint':
              'Распишитесь в поле. Подпись будет сохранена для ваших деловых документов.',
          'draw_signature': 'Распишитесь здесь',
          'tap_to_draw_signature': 'Нажмите, чтобы открыть поле подписи',
          'clear_signature': 'Очистить подпись',
          'save_signature': 'Сохранить подпись',
          'cancel': 'Отмена',
          'required': 'Обязательно',
          'business_id_9_digits': 'Бизнес ID должен состоять ровно из 9 цифр',
          'business_id_invalid':
              'Недействительный израильский бизнес-ID или номер удостоверения личности',
          'business_id_locked_title': 'Идентификатор бизнеса нельзя изменить',
          'business_id_locked_message':
              'После подтверждения бизнеса его ID / VAT ID изменить нельзя. Чтобы использовать другой номер бизнеса, необходимо открыть новую учетную запись.',
          'close': 'Закрыть',
          'step_classification': 'Налоговая категория бизнеса',
          'classification_note':
              'Примечание: эта настройка определяет типы документов (счет/квитанция), которые вы сможете создавать.',
          'dealer_exempt': 'Освобожденный дилер',
          'dealer_licensed': 'Лицензированный дилер',
          'dealer_company': 'ООО',
          'step_legal': 'Юридические подтверждения',
          'legal_terms':
              'Я прочитал и согласен с условиями использования и кодексом этики hiro.',
          'legal_declaration':
              'Я подтверждаю, что вся предоставленная информация верна, действительна и подлинна.',
          'legal_responsibility':
              'Я несу ответственность за любую неверную или вводящую в заблуждение информацию, которую предоставлю.',
          'submit': 'Отправить на юридическую проверку',
          'verification_pending': 'Проверка в ожидании',
          'business_verified': 'Бизнес подтвержден',
          'pending_message':
              'Вы уже отправили запрос на проверку. Наша команда проверяет ваши документы. Обычно это занимает до 48 часов.',
          'verified_message': 'Поздравляем! Ваш бизнес подтвержден в системе.',
          'back_to_profile': 'Назад в профиль',
          'rejected_notice':
              'Ваш предыдущий запрос на проверку был отклонен. Проверьте документы и отправьте снова.',
          'error_prefix': 'Ошибка: ',
        };
      case 'am':
        return {
          'page_title': 'ማንነት እና የንግድ ማረጋገጫ',
          'verification_intro': 'ጥቂት አጭር ዝርዝሮችን በመሙላት የተረጋገጠ የንግድ መገለጫ ያግኙ።',
          'secure_review': 'መረጃዎ በደህንነት ይጠበቃል እና በአብዛኛው በ48 ሰዓት ውስጥ ይገመገማል።',
          'accept_all_legal': 'ሁሉንም የህግ ማረጋገጫዎች መቀበል አለብዎት',
          'business_id_connected': 'ይህ የንግድ መለያ ከሌላ መለያ ጋር አስቀድሞ ተያይዟል',
          'request_submitted': 'ጥያቄው በተሳካ ሁኔታ ተልኳል',
          'submitted_for_review':
              'ሰነዶቹ ለግምገማ ተልከዋል። የመለያው ሁኔታ በ48 ሰዓታት ውስጥ ይዘምናል።',
          'got_it': 'ገባኝ',
          'uploading': 'ሰነዶች እየተጫኑ እና እየተረጋገጡ ነው...',
          'step_business': 'የንግድ እና ምዝገባ ዝርዝሮች',
          'business_name': 'የተመዘገበ የንግድ ስም',
          'business_id': 'የንግድ መለያ / VAT ID',
          'business_street': 'መንገድ (አማራጭ)',
          'business_house_number': 'የቤት ቁጥር (አማራጭ)',
          'business_city': 'ከተማ (አማራጭ)',
          'business_postal_code': 'የፖስታ ኮድ (አማራጭ)',
          'has_branches': 'ንግዱ ቅርንጫፎች አሉት?',
          'branch_number': 'የቅርንጫፍ ቁጥር',
          'branch_number_invalid': 'ከ1–7 አሃዞች ያለው የቅርንጫፍ ቁጥር ያስገቡ',
          'business_logo': 'የንግድ አርማ',
          'business_logo_optional': 'የንግድ አርማ (አማራጭ)',
          'business_logo_hint': 'አርማው በሚፈጥሯቸው የንግድ ሰነዶች ላይ ይታያል።',
          'document_branding': 'ለሰነዶች አርማ እና ፊርማ',
          'document_branding_hint':
              'አማራጭ። አርማው እና ፊርማው በሚፈጥሯቸው የንግድ ሰነዶች ላይ ብቻ ይጠቀማሉ።',
          'add_logo': 'አርማ ጨምር',
          'change_logo': 'አርማ ቀይር',
          'remove_logo': 'አርማ አስወግድ',
          'business_signature_optional': 'የንግድ ፊርማ (አማራጭ)',
          'business_signature_hint': 'በሳጥኑ ውስጥ ይፈርሙ። ፊርማው ለንግድ ሰነዶችዎ ይቀመጣል።',
          'draw_signature': 'እዚህ ይፈርሙ',
          'tap_to_draw_signature': 'የፊርማ ሰሌዳውን ለመክፈት ይንኩ',
          'clear_signature': 'ፊርማውን አጽዳ',
          'save_signature': 'ፊርማ አስቀምጥ',
          'cancel': 'ሰርዝ',
          'required': 'ያስፈልጋል',
          'business_id_9_digits': 'የንግድ መለያው በትክክል 9 አሃዞች መሆን አለበት',
          'business_id_invalid': 'የእስራኤል የንግድ ወይም የመታወቂያ ቁጥሩ ትክክል አይደለም',
          'business_id_locked_title': 'የንግድ መለያውን መቀየር አይቻልም',
          'business_id_locked_message':
              'ንግዱ ከተረጋገጠ በኋላ የንግድ መለያ / VAT ID መቀየር አይቻልም። ሌላ የንግድ ቁጥር ለመጠቀም አዲስ መለያ መክፈት አለብዎት።',
          'close': 'ዝጋ',
          'step_classification': 'የግብር ንግድ ምድብ',
          'classification_note':
              'ማስታወሻ: ይህ ቅንብር ሊያወጡ የሚችሉትን የሰነድ አይነቶች (ደረሰኝ/ቅብዓት) ይወስናል።',
          'dealer_exempt': 'ነፃ ነጋዴ',
          'dealer_licensed': 'ፈቃድ ያለው ነጋዴ',
          'dealer_company': 'የተገደበ ተጠያቂነት ኩባንያ',
          'step_legal': 'የህግ ማረጋገጫዎች',
          'legal_terms': 'የ hiro የአጠቃቀም ደንቦችን እና የስነምግባር መመሪያዎችን አንብቤ ተስማምቻለሁ።',
          'legal_declaration': 'የሰጠሁት መረጃ ሁሉ ትክክል፣ የሚሰራ እና ኦሪጂናል መሆኑን እገልጻለሁ።',
          'legal_responsibility':
              'የማቀርበው ማንኛውም የተሳሳተ ወይም አሳሳች መረጃ ላይ ኃላፊነት እወስዳለሁ።',
          'submit': 'ለህጋዊ ግምገማ ላክ',
          'verification_pending': 'ማረጋገጫው በመጠባበቅ ላይ ነው',
          'business_verified': 'ንግዱ ተረጋግጧል',
          'pending_message':
              'አስቀድሞ የማረጋገጫ ጥያቄ ልከዋል። ቡድናችን ሰነዶችዎን እየገመገመ ነው። ይህ በአብዛኛው እስከ 48 ሰዓት ይወስዳል።',
          'verified_message': 'እንኳን ደስ አለዎት! ንግድዎ በስርዓቱ ውስጥ ተረጋግጧል።',
          'back_to_profile': 'ወደ መገለጫ ተመለስ',
          'rejected_notice':
              'ያለፈው የማረጋገጫ ጥያቄዎ ተቀባይነት አላገኘም። እባክዎ ሰነዶችዎን ያረጋግጡ እና እንደገና ይላኩ።',
          'error_prefix': 'ስህተት: ',
        };
      default:
        return {
          'page_title': 'Identity & Business Verification',
          'verification_intro':
              'A few quick details are all you need for a trusted, verified business profile.',
          'secure_review':
              'Your information is stored securely and usually reviewed within 48 hours.',
          'accept_all_legal': 'You must accept all legal declarations',
          'business_id_connected':
              'This business ID is already connected to an account',
          'request_submitted': 'Request Submitted!',
          'submitted_for_review':
              'Documents submitted for review. Account status will be updated within 48 hours.',
          'got_it': 'Got it',
          'uploading': 'Uploading documents and verifying...',
          'step_business': 'Business & Registration Details',
          'business_name': 'Registered Business Name',
          'business_id': 'Business ID / VAT ID',
          'business_street': 'Street (Optional)',
          'business_house_number': 'House Number (Optional)',
          'business_city': 'City (Optional)',
          'business_postal_code': 'Postal Code (Optional)',
          'has_branches': 'Does the business have branches?',
          'branch_number': 'Branch Number',
          'branch_number_invalid': 'Enter a branch number of 1–7 digits',
          'business_logo': 'Business Logo',
          'business_logo_optional': 'Business Logo (Optional)',
          'business_logo_hint':
              'Your logo will appear on the business documents you create.',
          'document_branding': 'Logo & Signature for Documents',
          'document_branding_hint':
              'Optional. Your logo and signature are used only on the business documents you create.',
          'add_logo': 'Add Logo',
          'change_logo': 'Change Logo',
          'remove_logo': 'Remove Logo',
          'business_signature_optional': 'Business Signature (Optional)',
          'business_signature_hint':
              'Sign inside the box. Your signature will be saved for your business documents.',
          'draw_signature': 'Sign here',
          'tap_to_draw_signature': 'Tap to open the signature pad',
          'clear_signature': 'Clear Signature',
          'save_signature': 'Save Signature',
          'cancel': 'Cancel',
          'required': 'Required',
          'business_id_9_digits': 'Business ID must be exactly 9 digits',
          'business_id_invalid':
              'Enter a valid Israeli business or identity number',
          'business_id_locked_title': 'Business ID cannot be changed',
          'business_id_locked_message':
              'After your business is verified, its Business ID / VAT ID cannot be changed. To use a different business number, you must open a new account.',
          'close': 'Close',
          'step_classification': 'Tax Dealer Classification',
          'classification_note':
              'Note: This setting determines the document types (Invoice/Receipt) you can generate.',
          'dealer_exempt': 'Exempt Dealer',
          'dealer_licensed': 'Licensed Dealer',
          'dealer_company': 'Limited Company',
          'step_legal': 'Legal Confirmations',
          'legal_terms':
              'I have read and agree to the hiro Terms of Use and Code of Ethics.',
          'legal_declaration':
              'I declare that all information provided is correct, valid, and original.',
          'legal_responsibility':
              'I am responsible for any wrong or misleading information I provide.',
          'submit': 'Submit for Legal Review',
          'verification_pending': 'Verification Pending',
          'business_verified': 'Business Verified',
          'pending_message':
              'You have already submitted a verification request. Our team is reviewing your documents. This usually takes up to 48 hours.',
          'verified_message':
              'Congratulations! Your business is verified in our system.',
          'back_to_profile': 'Back to Profile',
          'rejected_notice':
              'Your previous verification request was rejected. Please check your documents and resubmit.',
          'error_prefix': 'Error: ',
        };
    }
  }

  Future<void> _checkCurrentStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid);
        final snapshots = await Future.wait([
          userRef.get(),
          userRef.collection('verification_info').doc('latest').get(),
        ]);
        final userData = snapshots[0].data() ?? <String, dynamic>{};
        final doc = snapshots[1];
        if (doc.exists && mounted) {
          final data = doc.data() ?? <String, dynamic>{};
          final savedStatus =
              (data['businessVerificationStatus'] ?? data['status'])
                  ?.toString()
                  .trim()
                  .toLowerCase();
          final isApproved =
              userData['isapproved'] == true ||
              savedStatus == 'approved' ||
              savedStatus == 'verified';
          final savedDealerType = (data['dealerType'] ?? userData['dealerType'])
              ?.toString();
          setState(() {
            _currentStatus = isApproved
                ? 'approved'
                : (savedStatus?.isNotEmpty ?? false)
                ? savedStatus
                : null;
            _businessNameController.text =
                (data['businessName'] ??
                        userData['businessName'] ??
                        userData['name'] ??
                        '')
                    .toString();
            _idController.text =
                (data['businessId'] ?? userData['businessId'] ?? '').toString();
            _streetController.text =
                (data['street'] ??
                        data['address'] ??
                        userData['businessAddress'] ??
                        userData['address'] ??
                        '')
                    .toString();
            _houseNumberController.text =
                (data['houseNumber'] ?? userData['houseNumber'] ?? '')
                    .toString();
            _cityController.text = (data['city'] ?? userData['city'] ?? '')
                .toString();
            _postalCodeController.text =
                (data['postalCode'] ?? userData['postalCode'] ?? '').toString();
            _hasBranches =
                data['hasBranches'] == true || userData['hasBranches'] == true;
            _branchNumberController.text =
                (data['branchNumber'] ?? userData['branchNumber'] ?? '')
                    .toString();
            if (const {
              'exempt',
              'licensed',
              'company',
            }.contains(savedDealerType)) {
              _dealerType = savedDealerType!;
            }
            _acceptedTerms =
                isApproved ||
                data['termsAccepted'] == true ||
                data['legalAccepted'] == true;
            _isLegalDeclarationSigned =
                isApproved ||
                data['legalDeclarationAccepted'] == true ||
                data['legalAccepted'] == true;
            _acceptedResponsibility =
                isApproved || data['responsibilityAccepted'] == true;
            _businessLogoUrl =
                (data['businessLogoUrl'] ?? userData['businessLogoUrl'])
                    ?.toString()
                    .trim();
            _businessSignatureUrl =
                (data['businessSignatureUrl'] ??
                        userData['businessSignatureUrl'])
                    ?.toString()
                    .trim();
          });
        } else if (mounted && userData['isapproved'] == true) {
          setState(() {
            _currentStatus = 'approved';
            _businessNameController.text =
                (userData['businessName'] ?? userData['name'] ?? '').toString();
            _idController.text = (userData['businessId'] ?? '').toString();
            _streetController.text =
                (userData['businessAddress'] ?? userData['address'] ?? '')
                    .toString();
            _houseNumberController.text = (userData['houseNumber'] ?? '')
                .toString();
            _cityController.text = (userData['city'] ?? '').toString();
            _postalCodeController.text = (userData['postalCode'] ?? '')
                .toString();
            _hasBranches = userData['hasBranches'] == true;
            _branchNumberController.text = (userData['branchNumber'] ?? '')
                .toString();
            _dealerType =
                const {
                  'exempt',
                  'licensed',
                  'company',
                }.contains(userData['dealerType'])
                ? userData['dealerType'].toString()
                : _dealerType;
            _acceptedTerms = true;
            _isLegalDeclarationSigned = true;
            _acceptedResponsibility = true;
            _businessLogoUrl = userData['businessLogoUrl']?.toString().trim();
            _businessSignatureUrl = userData['businessSignatureUrl']
                ?.toString()
                .trim();
          });
        }
      } catch (e) {
        debugPrint("Status check error: $e");
      }
    }
    if (mounted) setState(() => _isLoadingStatus = false);
  }

  Future<void> _submitVerification() async {
    final strings = _getLocalizedStrings(context);

    if (!_formKey.currentState!.validate()) return;

    if (!_acceptedTerms ||
        !_isLegalDeclarationSigned ||
        !_acceptedResponsibility) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings['accept_all_legal']!),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final businessId = _idController.text.trim();
      String? businessLogoUrl = _businessLogoUrl;
      String? businessSignatureUrl = _businessSignatureUrl;

      if (_businessLogo != null) {
        final ref = FirebaseStorage.instance.ref().child(
          'business_logos/${user.uid}.jpg',
        );
        await ref.putFile(_businessLogo!);
        businessLogoUrl = await ref.getDownloadURL();
      }

      final signatureBytes = await _renderSignaturePng();
      if (signatureBytes != null) {
        final ref = FirebaseStorage.instance.ref().child(
          'business_signatures/${user.uid}.png',
        );
        await ref.putData(
          signatureBytes,
          SettableMetadata(contentType: 'image/png'),
        );
        businessSignatureUrl = await ref.getDownloadURL();
      }

      await _functions.httpsCallable('submitBusinessVerification').call({
        'businessId': businessId,
        'businessName': _businessNameController.text.trim(),
        'street': _streetController.text.trim(),
        'houseNumber': _houseNumberController.text.trim(),
        'city': _cityController.text.trim(),
        'postalCode': _postalCodeController.text.trim(),
        'hasBranches': _hasBranches,
        'branchNumber': _hasBranches ? _branchNumberController.text.trim() : '',
        'dealerType': _dealerType,
        'legalAccepted': _acceptedTerms && _isLegalDeclarationSigned,
        'termsAccepted': _acceptedTerms,
        'legalDeclarationAccepted': _isLegalDeclarationSigned,
        'responsibilityAccepted': _acceptedResponsibility,
        'businessLogoUrl': businessLogoUrl,
        'businessSignatureUrl': businessSignatureUrl,
      });

      if (mounted) {
        _showSuccessDialog(strings);
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint("Verification submit error: $e");
      if (mounted) {
        final message = e.code == 'already-exists'
            ? strings['business_id_connected']!
            : '${strings['error_prefix']}${e.message ?? e.code}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: e.code == 'already-exists' ? Colors.red : null,
          ),
        );
      }
    } catch (e) {
      debugPrint("Verification submit error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${strings['error_prefix']}$e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickBusinessLogo() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _businessLogo = File(picked.path));
  }

  bool get _hasDrawnSignature => _signaturePoints.any((point) => point != null);

  Future<Uint8List?> _renderSignaturePng() async {
    if (!_hasDrawnSignature) return null;

    const width = 1200;
    const height = 400;
    const size = Size(1200, 400);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _SignaturePainter(_signaturePoints).paint(canvas, size);
    final image = await recorder.endRecording().toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData?.buffer.asUint8List();
  }

  void _showBusinessIdLockedDialog(Map<String, String> strings) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_outline_rounded, color: _primary, size: 34),
        title: Text(strings['business_id_locked_title']!),
        content: Text(strings['business_id_locked_message']!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings['close']!),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(Map<String, String> strings) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Icon(Icons.verified_user, size: 50, color: Colors.green[600]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings['request_submitted']!,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(strings['submitted_for_review']!, textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Text(strings['got_it']!),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final strings = _getLocalizedStrings(context);
    final isRtl = locale == 'he' || locale == 'ar';
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _page,
        appBar: AppBar(
          title: Text(
            strings['page_title']!,
            style: const TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          centerTitle: true,
          backgroundColor: _page,
          foregroundColor: _ink,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: _isLoadingStatus
            ? _buildLoadingState()
            : _currentStatus == 'pending'
            ? _buildStatusScreen(strings)
            : _buildVerificationForm(strings),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: SizedBox.square(
        dimension: 34,
        child: CircularProgressIndicator(strokeWidth: 3, color: _primary),
      ),
    );
  }

  Widget _buildVerificationForm(Map<String, String> strings) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildIntroCard(strings),
                      const SizedBox(height: 16),
                      if (_currentStatus == 'rejected') ...[
                        _buildRejectedNotice(strings),
                        const SizedBox(height: 16),
                      ],
                      _buildBusinessSection(strings),
                      const SizedBox(height: 16),
                      _buildDocumentBrandingSection(strings),
                      const SizedBox(height: 16),
                      _buildClassificationSection(strings),
                      const SizedBox(height: 16),
                      _buildLegalSection(strings),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _isUploading ? null : _submitVerification,
                        icon: const Icon(Icons.verified_user_rounded, size: 21),
                        label: Text(strings['submit']!),
                        style: FilledButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _primary.withValues(
                            alpha: 0.55,
                          ),
                          minimumSize: const Size.fromHeight(58),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_isUploading) _buildUploadingOverlay(strings),
      ],
    );
  }

  Widget _buildIntroCard(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [Color(0xFF1669C1), Color(0xFF2E8AE6)],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.17),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: Colors.white,
              size: 27,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            strings['page_title']!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings['verification_intro']!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded, color: Colors.white, size: 17),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings['secure_review']!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessSection(Map<String, String> strings) {
    return _buildSectionCard(
      step: 1,
      title: strings['step_business']!,
      icon: Icons.storefront_rounded,
      child: Column(
        children: [
          TextFormField(
            controller: _businessNameController,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            decoration: _inputStyle(
              strings['business_name']!,
              Icons.business_outlined,
            ),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? strings['required'] : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _idController,
            textInputAction: TextInputAction.next,
            readOnly: _isBusinessApproved,
            decoration: _inputStyle(
              strings['business_id']!,
              Icons.badge_outlined,
              suffixIcon: _isBusinessApproved
                  ? IconButton(
                      tooltip: strings['business_id_locked_title']!,
                      onPressed: () => _showBusinessIdLockedDialog(strings),
                      icon: const Icon(Icons.help_outline_rounded),
                      color: _primary,
                    )
                  : null,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            validator: (value) {
              final id = value?.trim() ?? '';
              if (id.isEmpty) return strings['required'];
              if (!RegExp(r'^\d{9}$').hasMatch(id)) {
                return strings['business_id_9_digits'];
              }
              if (!isValidIsraeliId(id)) {
                return strings['business_id_invalid'];
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _streetController,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            decoration: _inputStyle(
              strings['business_street']!,
              Icons.signpost_outlined,
            ),
            inputFormatters: [LengthLimitingTextInputFormatter(50)],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _houseNumberController,
            textInputAction: TextInputAction.next,
            decoration: _inputStyle(
              strings['business_house_number']!,
              Icons.home_outlined,
            ),
            inputFormatters: [LengthLimitingTextInputFormatter(10)],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _cityController,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            decoration: _inputStyle(
              strings['business_city']!,
              Icons.location_city_outlined,
            ),
            inputFormatters: [LengthLimitingTextInputFormatter(30)],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _postalCodeController,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.number,
            decoration: _inputStyle(
              strings['business_postal_code']!,
              Icons.local_post_office_outlined,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
          ),
          const SizedBox(height: 14),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(
              strings['has_branches']!,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            value: _hasBranches,
            activeThumbColor: _primary,
            onChanged: (value) {
              setState(() {
                _hasBranches = value;
                if (!value) _branchNumberController.clear();
              });
            },
          ),
          if (_hasBranches) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _branchNumberController,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.number,
              decoration: _inputStyle(
                strings['branch_number']!,
                Icons.account_tree_outlined,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(7),
              ],
              validator: (value) {
                if (!_hasBranches) return null;
                final branchNumber = value?.trim() ?? '';
                return RegExp(r'^\d{1,7}$').hasMatch(branchNumber)
                    ? null
                    : strings['branch_number_invalid'];
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDocumentBrandingSection(Map<String, String> strings) {
    return _buildSectionCard(
      step: 2,
      title: strings['document_branding']!,
      icon: Icons.add_photo_alternate_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInfoNote(strings['document_branding_hint']!),
          const SizedBox(height: 14),
          _buildLogoPicker(strings),
          const SizedBox(height: 14),
          _buildSignaturePicker(strings),
        ],
      ),
    );
  }

  Widget _buildClassificationSection(Map<String, String> strings) {
    return _buildSectionCard(
      step: 3,
      title: strings['step_classification']!,
      icon: Icons.receipt_long_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInfoNote(strings['classification_note']!),
          const SizedBox(height: 14),
          _buildDealerTypePicker(strings),
        ],
      ),
    );
  }

  Widget _buildLegalSection(Map<String, String> strings) {
    return _buildSectionCard(
      step: 4,
      title: strings['step_legal']!,
      icon: Icons.gavel_rounded,
      child: Column(
        children: [
          _buildLegalCheckbox(
            value: _acceptedTerms,
            onChanged: (value) =>
                setState(() => _acceptedTerms = value ?? false),
            label: strings['legal_terms']!,
          ),
          const SizedBox(height: 10),
          _buildLegalCheckbox(
            value: _isLegalDeclarationSigned,
            onChanged: (value) =>
                setState(() => _isLegalDeclarationSigned = value ?? false),
            label: strings['legal_declaration']!,
          ),
          const SizedBox(height: 10),
          _buildLegalCheckbox(
            value: _acceptedResponsibility,
            onChanged: (value) =>
                setState(() => _acceptedResponsibility = value ?? false),
            label: strings['legal_responsibility']!,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required int step,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C0F4C81),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepHeader(step, title, icon),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoNote(String message) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: _primary, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF315777),
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDealerTypePicker(Map<String, String> strings) {
    final options = [
      ('exempt', strings['dealer_exempt']!, Icons.money_off_rounded),
      ('licensed', strings['dealer_licensed']!, Icons.payments_outlined),
      ('company', strings['dealer_company']!, Icons.apartment_rounded),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620
            ? 3
            : constraints.maxWidth >= 440
            ? 2
            : 1;
        const spacing = 10.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final option in options)
              SizedBox(
                width: itemWidth,
                child: _dealerTypeCard(option.$1, option.$2, option.$3),
              ),
          ],
        );
      },
    );
  }

  Widget _buildUploadingOverlay(Map<String, String> strings) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x9907101F),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(28),
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 38,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: _primary,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  strings['uploading']!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusScreen(Map<String, String> strings) {
    final isPending = _currentStatus == 'pending';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPending
                  ? Icons.hourglass_bottom_rounded
                  : Icons.verified_rounded,
              size: 80,
              color: isPending ? Colors.orange : Colors.green,
            ),
            const SizedBox(height: 24),
            Text(
              isPending
                  ? strings['verification_pending']!
                  : strings['business_verified']!,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              isPending
                  ? strings['pending_message']!
                  : strings['verified_message']!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], height: 1.5),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(strings['back_to_profile']!),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRejectedNotice(Map<String, String> strings) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red[100]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              strings['rejected_notice']!,
              style: TextStyle(
                color: Colors.red[900],
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoPicker(Map<String, String> strings) {
    return _buildDocumentImagePicker(
      title: strings['business_logo_optional']!,
      hint: strings['business_logo_hint']!,
      image: _businessLogo,
      imageUrl: _businessLogoUrl,
      placeholderIcon: Icons.storefront_outlined,
      onPick: _pickBusinessLogo,
      onRemove: () => setState(() {
        _businessLogo = null;
        _businessLogoUrl = null;
      }),
      addLabel: strings['add_logo']!,
      changeLabel: strings['change_logo']!,
      removeLabel: strings['remove_logo']!,
    );
  }

  Widget _buildSignaturePicker(Map<String, String> strings) {
    final hasSavedSignature = _businessSignatureUrl?.isNotEmpty ?? false;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings['business_signature_optional']!,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            strings['business_signature_hint']!,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => _showSignatureDrawingDialog(strings),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 120,
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasSavedSignature && !_hasDrawnSignature)
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Image.network(
                          _businessSignatureUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    if (_hasDrawnSignature)
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: CustomPaint(
                          painter: _SignaturePainter(_signaturePoints),
                        ),
                      ),
                    if (!hasSavedSignature && !_hasDrawnSignature)
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.draw_outlined,
                              color: Color(0xFF64748B),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              strings['tap_to_draw_signature']!,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (hasSavedSignature || _hasDrawnSignature)
                      const PositionedDirectional(
                        top: 8,
                        end: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFFEAF4FF),
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(7),
                            child: Icon(
                              Icons.edit_rounded,
                              color: _primary,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSignatureDrawingDialog(Map<String, String> strings) async {
    final draftPoints = List<Offset?>.from(_signaturePoints);
    var showSavedSignature =
        draftPoints.every((point) => point == null) &&
        (_businessSignatureUrl?.isNotEmpty ?? false);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final hasDraft = draftPoints.any((point) => point != null);
          final dialogHeight = (MediaQuery.sizeOf(context).height * 0.72).clamp(
            360.0,
            600.0,
          );
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SizedBox(
                height: dialogHeight,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              strings['business_signature_optional']!,
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: strings['cancel']!,
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        strings['business_signature_hint']!,
                        style: const TextStyle(color: _muted, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final padSize = Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );
                            Offset normalized(Offset position) => Offset(
                              (position.dx / padSize.width)
                                  .clamp(0.0, 1.0)
                                  .toDouble(),
                              (position.dy / padSize.height)
                                  .clamp(0.0, 1.0)
                                  .toDouble(),
                            );

                            void finishStroke() {
                              if (draftPoints.isNotEmpty &&
                                  draftPoints.last != null) {
                                setDialogState(() => draftPoints.add(null));
                              }
                            }

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (details) {
                                setDialogState(() {
                                  showSavedSignature = false;
                                  draftPoints.add(
                                    normalized(details.localPosition),
                                  );
                                });
                              },
                              onPanUpdate: (details) {
                                setDialogState(() {
                                  draftPoints.add(
                                    normalized(details.localPosition),
                                  );
                                });
                              },
                              onPanEnd: (_) => finishStroke(),
                              onPanCancel: finishStroke,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF94A3B8),
                                    width: 1.4,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (showSavedSignature)
                                        Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Image.network(
                                            _businessSignatureUrl!,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      if (!showSavedSignature && !hasDraft)
                                        Center(
                                          child: Text(
                                            strings['draw_signature']!,
                                            style: const TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 17,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      CustomPaint(
                                        painter: _SignaturePainter(draftPoints),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        overflowAlignment: OverflowBarAlignment.end,
                        spacing: 8,
                        overflowSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              setDialogState(() {
                                draftPoints.clear();
                                showSavedSignature = false;
                              });
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: Text(strings['clear_signature']!),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Text(strings['cancel']!),
                          ),
                          FilledButton.icon(
                            onPressed: () {
                              setState(() {
                                _signaturePoints
                                  ..clear()
                                  ..addAll(draftPoints);
                                if (!showSavedSignature) {
                                  _businessSignatureUrl = null;
                                }
                              });
                              Navigator.pop(dialogContext);
                            },
                            icon: const Icon(Icons.check_rounded),
                            label: Text(strings['save_signature']!),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDocumentImagePicker({
    required String title,
    required String hint,
    required File? image,
    required String? imageUrl,
    required IconData placeholderIcon,
    required VoidCallback onPick,
    required VoidCallback onRemove,
    required String addLabel,
    required String changeLabel,
    required String removeLabel,
  }) {
    final hasRemoteImage = imageUrl?.isNotEmpty ?? false;
    final hasImage = image != null || hasRemoteImage;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                clipBehavior: Clip.antiAlias,
                child: image != null
                    ? Image.file(image, fit: BoxFit.contain)
                    : hasRemoteImage
                    ? Image.network(
                        imageUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Icon(
                          placeholderIcon,
                          color: const Color(0xFF94A3B8),
                          size: 32,
                        ),
                      )
                    : Icon(
                        placeholderIcon,
                        color: const Color(0xFF94A3B8),
                        size: 32,
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onPick,
                      icon: Icon(
                        !hasImage
                            ? Icons.upload_outlined
                            : Icons.refresh_rounded,
                      ),
                      label: Text(!hasImage ? addLabel : changeLabel),
                    ),
                    if (hasImage)
                      TextButton(onPressed: onRemove, child: Text(removeLabel)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepHeader(int step, String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: _primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '0$step',
                style: const TextStyle(
                  color: _primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inputStyle(
    String label,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _muted, fontSize: 14),
      floatingLabelStyle: const TextStyle(
        color: _primary,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF7290AC), size: 21),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FBFE),
      border: border(_line),
      enabledBorder: border(_line),
      focusedBorder: border(_primary, 1.6),
      errorBorder: border(const Color(0xFFDC2626)),
      focusedErrorBorder: border(const Color(0xFFDC2626), 1.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    );
  }

  Widget _dealerTypeCard(String type, String label, IconData icon) {
    final isSelected = _dealerType == type;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _dealerType = type),
        borderRadius: BorderRadius.circular(17),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEAF4FF) : Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: isSelected ? _primary : _line,
              width: isSelected ? 1.7 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : const Color(0xFFF3F6F9),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? _primary : const Color(0xFF7B8FA3),
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: isSelected ? _primary : const Color(0xFF425466),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: isSelected
                    ? const Icon(
                        Icons.check_circle_rounded,
                        key: ValueKey('selected'),
                        color: _primary,
                        size: 21,
                      )
                    : const SizedBox(key: ValueKey('unselected'), width: 21),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegalCheckbox({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String label,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: value ? const Color(0xFFF0F7FF) : const Color(0xFFF9FBFD),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: value ? const Color(0xFFA9D2FA) : _line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IgnorePointer(
                child: SizedBox.square(
                  dimension: 24,
                  child: Checkbox(
                    value: value,
                    onChanged: onChanged,
                    activeColor: _primary,
                    side: const BorderSide(
                      color: Color(0xFF9AAFC2),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Color(0xFF425466),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.points);

  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.shortestSide * 0.012;
    final paint = Paint()
      ..color = const Color(0xFF07101F)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    Offset? previous;
    for (final point in points) {
      if (point == null) {
        previous = null;
        continue;
      }
      final current = Offset(point.dx * size.width, point.dy * size.height);
      if (previous == null) {
        canvas.drawCircle(
          current,
          strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
        paint.style = PaintingStyle.stroke;
      } else {
        canvas.drawLine(previous, current, paint);
      }
      previous = current;
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
