import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';

class VerifyBusinessPage extends StatefulWidget {
  const VerifyBusinessPage({super.key});

  @override
  State<VerifyBusinessPage> createState() => _VerifyBusinessPageState();
}

class _VerifyBusinessPageState extends State<VerifyBusinessPage> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _addressController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

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
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'page_title': 'אימות זהות ועסק',
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
          'business_logo_hint':
              'ንግድዎን በፍጥነት እንድንለይ ለማገዝ አርማ ማከል ይችላሉ።',
          'add_logo': 'አርማ ጨምር',
          'change_logo': 'አርማ ቀይር',
          'remove_logo': 'አርማ አስወግድ',
          'required': 'ያስፈልጋል',
          'business_id_9_digits': 'የንግድ መለያው በትክክል 9 አሃዞች መሆን አለበት',
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
          'business_logo_hint':
              'Add logo to put on your documents.',
          'add_logo': 'Add Logo',
          'change_logo': 'Change Logo',
          'remove_logo': 'Remove Logo',
          'required': 'Required',
          'business_id_9_digits': 'Business ID must be exactly 9 digits',
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
            .collection('verifications')
            .doc(user.uid)
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

  Future<bool> _isBusinessIdConnectedToAnotherAccount(
    String businessId,
    String currentUserId,
  ) async {
    final usersMatch = await FirebaseFirestore.instance
        .collection('users')
        .where('businessId', isEqualTo: businessId)
        .limit(5)
        .get();

    final userAlreadyConnected = usersMatch.docs.any(
      (doc) => doc.id != currentUserId,
    );
    if (userAlreadyConnected) return true;

    final verificationMatch = await FirebaseFirestore.instance
        .collection('verifications')
        .where('businessId', isEqualTo: businessId)
        .limit(5)
        .get();

    return verificationMatch.docs.any((doc) => doc.id != currentUserId);
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
      final alreadyConnected = await _isBusinessIdConnectedToAnotherAccount(
        businessId,
        user.uid,
      );

      if (alreadyConnected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(strings['business_id_connected']!),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (_businessLogo != null) {
        final ref = FirebaseStorage.instance.ref().child(
          'business_logos/${user.uid}.jpg',
        );
        await ref.putFile(_businessLogo!);
        businessLogoUrl = await ref.getDownloadURL();
      }

      final verificationData = {
        'userId': user.uid,
        'businessId': businessId,
        'businessName': _businessNameController.text.trim(),
        'address': _addressController.text.trim(),
        'dealerType': _dealerType,
        'status': 'pending',
        'legalAccepted': true,
        'responsibilityAccepted': true,
        'timestamp': FieldValue.serverTimestamp(),
        'businessLogoUrl': businessLogoUrl,
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('verification_info')
          .doc('latest')
          .set(verificationData, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
            'dealerType': _dealerType,
            'businessId': businessId,
            'businessVerificationStatus': 'pending',
            'businessLogoUrl': businessLogoUrl,
          });

      if (mounted) {
        _showSuccessDialog(strings);
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

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(strings['page_title']!),
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _isLoadingStatus
            ? const Center(child: CircularProgressIndicator())
            : _isUploading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      strings['uploading']!,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )
            : _currentStatus == 'pending' || _currentStatus == 'verified'
            ? _buildStatusScreen(strings)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_currentStatus == 'rejected')
                        _buildRejectedNotice(strings),
                      _buildStepHeader(1, strings['step_business']!),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _businessNameController,
                        decoration: _inputStyle(
                          strings['business_name']!,
                          Icons.business,
                        ),
                        validator: (v) =>
                            v!.isEmpty ? strings['required'] : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _idController,
                        decoration: _inputStyle(
                          strings['business_id']!,
                          Icons.badge_outlined,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(9),
                        ],
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) return strings['required'];
                          if (!RegExp(r'^\d{9}$').hasMatch(value)) {
                            return strings['business_id_9_digits'];
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addressController,
                        decoration: _inputStyle(
                          strings['business_address']!,
                          Icons.location_on_outlined,
                        ),
                        validator: (v) =>
                            v!.isEmpty ? strings['required'] : null,
                      ),
                      const SizedBox(height: 12),
                      _buildLogoPicker(strings),
                      const SizedBox(height: 24),
                      _buildStepHeader(2, strings['step_classification']!),
                      const SizedBox(height: 8),
                      Text(
                        strings['classification_note']!,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _dealerTypeCard(
                              'exempt',
                              strings['dealer_exempt']!,
                              Icons.money_off,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _dealerTypeCard(
                              'licensed',
                              strings['dealer_licensed']!,
                              Icons.payments_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _dealerTypeCard(
                              'company',
                              strings['dealer_company']!,
                              Icons.apartment_outlined,
                            ),
                          ),
                        ],
                      ),
                      _buildStepHeader(3, strings['step_legal']!),
                      const SizedBox(height: 12),
                      _buildLegalCheckbox(
                        value: _acceptedTerms,
                        onChanged: (v) => setState(() => _acceptedTerms = v!),
                        label: strings['legal_terms']!,
                      ),
                      _buildLegalCheckbox(
                        value: _isLegalDeclarationSigned,
                        onChanged: (v) => setState(() {
                          _isLegalDeclarationSigned = v!;
                        }),
                        label: strings['legal_declaration']!,
                      ),
                      _buildLegalCheckbox(
                        value: _acceptedResponsibility,
                        onChanged: (v) => setState(() {
                          _acceptedResponsibility = v!;
                        }),
                        label: strings['legal_responsibility']!,
                      ),
                      const SizedBox(height: 40),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1976D2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 4,
                        ),
                        onPressed: _submitVerification,
                        child: Text(
                          strings['submit']!,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
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

  Widget _buildStepHeader(int step, String title) {
    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: const Color(0xFF1976D2),
          child: Text(
            step.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputStyle(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.blueGrey, size: 20),
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget _dealerTypeCard(String type, String label, IconData icon) {
    final isSelected = _dealerType == type;
    return InkWell(
      onTap: () => setState(() => _dealerType = type),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1976D2).withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF1976D2)
                : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF1976D2) : Colors.grey,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isSelected ? const Color(0xFF1976D2) : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegalCheckbox({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 24,
            width: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF1976D2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ),
        ],
      ),
    );
  }
}
