import 'dart:io';

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
  final _addressController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'me-west1',
  );

  String _dealerType = 'exempt';
  bool _isUploading = false;
  bool _isLoadingStatus = true;
  String? _currentStatus;
  File? _businessLogo;

  bool _acceptedTerms = false;
  bool _isLegalDeclarationSigned = false;
  bool _acceptedResponsibility = false;

  @override
  void initState() {
    super.initState();
    _checkCurrentStatus();
  }

  @override
  void dispose() {
    _idController.dispose();
    _businessNameController.dispose();
    _addressController.dispose();
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
          'business_address': 'כתובת העסק המלאה',
          'business_logo': 'לוגו העסק',
          'business_logo_optional': 'לוגו העסק (אופציונלי)',
          'business_logo_hint':
              'אפשר להוסיף לוגו כדי לעזור לנו לזהות את העסק שלך מהר יותר.',
          'add_logo': 'הוסף לוגו',
          'change_logo': 'החלף לוגו',
          'remove_logo': 'הסר לוגו',
          'required': 'חובה',
          'business_id_9_digits': 'מספר העסק חייב להכיל 9 ספרות',
          'business_id_invalid': 'מספר העוסק / ח.פ / ת.ז אינו תקין',
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
          'business_address': 'عنوان النشاط التجاري',
          'business_logo': 'شعار النشاط التجاري',
          'business_logo_optional': 'شعار النشاط التجاري (اختياري)',
          'business_logo_hint':
              'يمكنك إضافة شعار لمساعدتنا في التعرف على نشاطك بشكل أسرع.',
          'add_logo': 'إضافة شعار',
          'change_logo': 'تغيير الشعار',
          'remove_logo': 'إزالة الشعار',
          'required': 'مطلوب',
          'business_id_9_digits': 'يجب أن يتكون رقم النشاط من 9 أرقام بالضبط',
          'business_id_invalid':
              'رقم النشاط التجاري / الشركة / الهوية الإسرائيلية غير صالح',
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
          'business_address': 'Адрес бизнеса',
          'business_logo': 'Логотип бизнеса',
          'business_logo_optional': 'Логотип бизнеса (необязательно)',
          'business_logo_hint':
              'Вы можете добавить логотип, чтобы нам было проще быстрее распознать ваш бизнес.',
          'add_logo': 'Добавить логотип',
          'change_logo': 'Изменить логотип',
          'remove_logo': 'Удалить логотип',
          'required': 'Обязательно',
          'business_id_9_digits': 'Бизнес ID должен состоять ровно из 9 цифр',
          'business_id_invalid':
              'Недействительный израильский бизнес-ID или номер удостоверения личности',
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
          'business_address': 'የንግድ አድራሻ',
          'business_logo': 'የንግድ አርማ',
          'business_logo_optional': 'የንግድ አርማ (አማራጭ)',
          'business_logo_hint': 'ንግድዎን በፍጥነት እንድንለይ ለማገዝ አርማ ማከል ይችላሉ።',
          'add_logo': 'አርማ ጨምር',
          'change_logo': 'አርማ ቀይር',
          'remove_logo': 'አርማ አስወግድ',
          'required': 'ያስፈልጋል',
          'business_id_9_digits': 'የንግድ መለያው በትክክል 9 አሃዞች መሆን አለበት',
          'business_id_invalid': 'የእስራኤል የንግድ ወይም የመታወቂያ ቁጥሩ ትክክል አይደለም',
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
          'business_address': 'Business Address',
          'business_logo': 'Business Logo',
          'business_logo_optional': 'Business Logo (Optional)',
          'business_logo_hint': 'Add logo to put on your documents.',
          'add_logo': 'Add Logo',
          'change_logo': 'Change Logo',
          'remove_logo': 'Remove Logo',
          'required': 'Required',
          'business_id_9_digits': 'Business ID must be exactly 9 digits',
          'business_id_invalid':
              'Enter a valid Israeli business or identity number',
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
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('verification_info')
            .doc('latest')
            .get();
        if (doc.exists && mounted) {
          setState(() {
            _currentStatus = doc.data()?['status'];
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
      String? businessLogoUrl;

      if (_businessLogo != null) {
        final ref = FirebaseStorage.instance.ref().child(
          'business_logos/${user.uid}.jpg',
        );
        await ref.putFile(_businessLogo!);
        businessLogoUrl = await ref.getDownloadURL();
      }

      await _functions.httpsCallable('submitBusinessVerification').call({
        'businessId': businessId,
        'businessName': _businessNameController.text.trim(),
        'address': _addressController.text.trim(),
        'dealerType': _dealerType,
        'legalAccepted': _acceptedTerms && _isLegalDeclarationSigned,
        'termsAccepted': _acceptedTerms,
        'legalDeclarationAccepted': _isLegalDeclarationSigned,
        'responsibilityAccepted': _acceptedResponsibility,
        'businessLogoUrl': businessLogoUrl,
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
    final isApproved =
        _currentStatus == 'approved' || _currentStatus == 'verified';

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
            : _currentStatus == 'pending' || isApproved
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
            decoration: _inputStyle(
              strings['business_id']!,
              Icons.badge_outlined,
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
            controller: _addressController,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.words,
            decoration: _inputStyle(
              strings['business_address']!,
              Icons.location_on_outlined,
            ),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? strings['required'] : null,
          ),
          const SizedBox(height: 14),
          _buildLogoPicker(strings),
        ],
      ),
    );
  }

  Widget _buildClassificationSection(Map<String, String> strings) {
    return _buildSectionCard(
      step: 2,
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
      step: 3,
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
            strings['business_logo_optional']!,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            strings['business_logo_hint']!,
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
                child: _businessLogo == null
                    ? const Icon(
                        Icons.storefront_outlined,
                        color: Color(0xFF94A3B8),
                        size: 32,
                      )
                    : Image.file(_businessLogo!, fit: BoxFit.cover),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickBusinessLogo,
                      icon: Icon(
                        _businessLogo == null
                            ? Icons.upload_outlined
                            : Icons.refresh_rounded,
                      ),
                      label: Text(
                        _businessLogo == null
                            ? strings['add_logo']!
                            : strings['change_logo']!,
                      ),
                    ),
                    if (_businessLogo != null)
                      TextButton(
                        onPressed: () => setState(() => _businessLogo = null),
                        child: Text(strings['remove_logo']!),
                      ),
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

  InputDecoration _inputStyle(String label, IconData icon) {
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
