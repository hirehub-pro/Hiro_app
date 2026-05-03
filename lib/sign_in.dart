import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/analytics_service.dart';
import 'package:untitled1/services/auth_service.dart';
import 'package:untitled1/sign_up.dart';
import 'main.dart';

class SignInPage extends StatefulWidget {
  final bool showDeletionFeedbackPrompt;

  const SignInPage({super.key, this.showDeletionFeedbackPrompt = false});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> with TickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  AnimationController? _introController;
  AnimationController? _backgroundController;
  AnimationController? _logoTapController;
  Animation<double>? _logoScale;
  Animation<double>? _logoTwist;
  Animation<double>? _logoGlow;

  AnimationController get _introAnimationController {
    final controller = _introController;
    if (controller != null) return controller;
    final created = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _introController = created;
    return created;
  }

  AnimationController get _backgroundAnimationController {
    final controller = _backgroundController;
    if (controller != null) return controller;
    final created = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);
    _backgroundController = created;
    return created;
  }

  AnimationController get _logoTapAnimationController {
    final controller = _logoTapController;
    if (controller != null) return controller;
    final created = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _logoScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0.9,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.9,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 43,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.08,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 35,
      ),
    ]).animate(created);
    _logoTwist = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: -0.07,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 33,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: -0.07,
          end: 0.06,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 33,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.06,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 34,
      ),
    ]).animate(created);
    _logoGlow = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.28,
          end: 0.5,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.5,
          end: 0.28,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 55,
      ),
    ]).animate(created);
    _logoTapController = created;
    return created;
  }

  Animation<double> get _logoScaleAnimation {
    _logoTapAnimationController;
    return _logoScale!;
  }

  Animation<double> get _logoTwistAnimation {
    _logoTapAnimationController;
    return _logoTwist!;
  }

  Animation<double> get _logoGlowAnimation {
    _logoTapAnimationController;
    return _logoGlow!;
  }

  void _ensureAnimationControllers() {
    _introAnimationController;
    _backgroundAnimationController;
    _logoTapAnimationController;
  }

  void _playLogoTapAnimation() {
    _logoTapAnimationController.forward(from: 0);
  }

  String _verificationId = "";
  bool _codeSent = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ensureAnimationControllers();
    if (widget.showDeletionFeedbackPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showDeletionFeedbackDialog();
      });
    }
  }

  @override
  void dispose() {
    _introController?.dispose();
    _backgroundController?.dispose();
    _logoTapController?.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'welcome': 'ברוכים הבאים',
          'subtitle': 'הכניסו מספר טלפון ואשרו את קוד ה-SMS.',
          'access': 'גישה מקצועית',
          'signin_title': 'התחברות',
          'signin_subtitle': 'בחרו את הדרך המהירה להמשיך.',
          'phone_label': 'מספר טלפון',
          'phone_hint': 'לדוגמה: 0501234567',
          'get_code': 'שלח קוד אימות',
          'enter_code': 'הכנס קוד אימות',
          'verify': 'אמת והתחבר',
          'or': 'או',
          'guest': 'המשך כאורח',
          'signup': 'הרשמה',
          'no_account': 'אין לך חשבון? ',
          'not_registered_title': 'משתמש לא רשום',
          'not_registered_body':
              'מספר הטלפון שהוזן אינו רשום. האם תרצה להירשם?',
          'ok': 'אישור',
          'invalid_phone': 'אנא הכנס מספר טלפון ישראלי תקין (05XXXXXXXX)',
          'edit_phone': 'ערוך מספר טלפון',
          'secure_title': 'כניסה מאובטחת',
          'secure_body': 'אימות טלפוני מובנה לגישה אמינה.',
          'mobile_title': 'מהיר בנייד',
          'mobile_body': 'מותאם לכניסה מהירה ופעולות ברורות.',
          'guest_title': 'אפשרות אורח',
          'guest_body': 'אפשר להתחיל לגלוש בלי חשבון מלא.',
          'delete_feedback_title': 'נשמח להבין מה קרה',
          'delete_feedback_body':
              'החשבון נמחק. אם יש לך רגע, ספר לנו מה גרם לך לעזוב כדי שנוכל לשפר את Hiro.',
          'delete_feedback_hint': 'מה הייתה הסיבה העיקרית?',
          'delete_feedback_skip': 'דלג',
          'delete_feedback_send': 'שלח',
          'delete_feedback_sent': 'תודה על המשוב',
          'change_language': 'שנה שפה',
          'verification_failed': 'האימות נכשל: {msg}',
          'generic_error': 'שגיאה: {err}',
          'invalid_code_error': 'קוד לא תקין או אירעה שגיאה',
          'sign_in_error': 'שגיאת התחברות: {err}',
        };
      case 'ar':
        return {
          'welcome': 'مرحبًا',
          'subtitle': 'أدخل رقم هاتفك وأكد رمز SMS.',
          'access': 'وصول احترافي',
          'signin_title': 'تسجيل الدخول',
          'signin_subtitle': 'اختر أسرع طريقة للمتابعة.',
          'phone_label': 'رقم الهاتف',
          'phone_hint': 'مثال: 0501234567',
          'get_code': 'إرسال رمز التحقق',
          'enter_code': 'أدخل رمز SMS',
          'verify': 'تحقق وسجّل الدخول',
          'or': 'أو',
          'guest': 'المتابعة كضيف',
          'signup': 'إنشاء حساب',
          'no_account': 'ليس لديك حساب؟ ',
          'not_registered_title': 'المستخدم غير مسجل',
          'not_registered_body':
              'رقم الهاتف الذي أدخلته غير مسجل. هل تريد إنشاء حساب؟',
          'ok': 'موافق',
          'invalid_phone': 'يرجى إدخال رقم هاتف إسرائيلي صالح (05XXXXXXXX)',
          'edit_phone': 'تعديل رقم الهاتف',
          'secure_title': 'تسجيل دخول آمن',
          'secure_body': 'تحقق عبر الهاتف مصمم للوصول الموثوق.',
          'mobile_title': 'سريع على الهاتف',
          'mobile_body': 'مُحسّن للإدخال السريع والإجراءات الواضحة.',
          'guest_title': 'خيار الضيف',
          'guest_body': 'تصفح فورًا بدون حساب كامل.',
          'delete_feedback_title': 'أخبرنا بما حدث',
          'delete_feedback_body':
              'تم حذف حسابك. إذا كان لديك وقت، أخبرنا لماذا غادرت حتى نتمكن من تحسين Hiro.',
          'delete_feedback_hint': 'ما هو السبب الرئيسي؟',
          'delete_feedback_skip': 'تخطي',
          'delete_feedback_send': 'إرسال',
          'delete_feedback_sent': 'شكرًا على ملاحظتك',
          'change_language': 'تغيير اللغة',
          'verification_failed': 'فشل التحقق: {msg}',
          'generic_error': 'خطأ: {err}',
          'invalid_code_error': 'رمز غير صالح أو حدث خطأ',
          'sign_in_error': 'خطأ في تسجيل الدخول: {err}',
        };
      case 'ru':
        return {
          'welcome': 'Добро пожаловать',
          'subtitle': 'Введите номер телефона и подтвердите SMS-код.',
          'access': 'Профессиональный доступ',
          'signin_title': 'Вход',
          'signin_subtitle': 'Выберите самый быстрый способ продолжить.',
          'phone_label': 'Номер телефона',
          'phone_hint': 'например: 0501234567',
          'get_code': 'Отправить код подтверждения',
          'enter_code': 'Введите SMS-код',
          'verify': 'Подтвердить и войти',
          'or': 'или',
          'guest': 'Продолжить как гость',
          'signup': 'Регистрация',
          'no_account': 'Нет аккаунта? ',
          'not_registered_title': 'Пользователь не зарегистрирован',
          'not_registered_body':
              'Введённый номер телефона не зарегистрирован. Хотите зарегистрироваться?',
          'ok': 'OK',
          'invalid_phone':
              'Введите действительный израильский номер телефона (05XXXXXXXX)',
          'edit_phone': 'Изменить номер телефона',
          'secure_title': 'Безопасный вход',
          'secure_body': 'Проверка по телефону для надежного доступа.',
          'mobile_title': 'Быстро на телефоне',
          'mobile_body':
              'Оптимизировано для быстрого ввода и понятных действий.',
          'guest_title': 'Гостевой режим',
          'guest_body': 'Начните просмотр без полного аккаунта.',
          'delete_feedback_title': 'Расскажите, что произошло',
          'delete_feedback_body':
              'Ваш аккаунт удалён. Если у вас есть минутка, расскажите, почему вы ушли, чтобы мы могли улучшить Hiro.',
          'delete_feedback_hint': 'В чем была основная причина?',
          'delete_feedback_skip': 'Пропустить',
          'delete_feedback_send': 'Отправить',
          'delete_feedback_sent': 'Спасибо за отзыв',
          'change_language': 'Изменить язык',
          'verification_failed': 'Ошибка подтверждения: {msg}',
          'generic_error': 'Ошибка: {err}',
          'invalid_code_error': 'Неверный код или произошла ошибка',
          'sign_in_error': 'Ошибка входа: {err}',
        };
      case 'am':
        return {
          'welcome': 'እንኳን ደህና መጡ',
          'subtitle': 'የስልክ ቁጥርዎን ያስገቡ እና የSMS ኮድን ያረጋግጡ።',
          'access': 'ሙያዊ መዳረሻ',
          'signin_title': 'መግቢያ',
          'signin_subtitle': 'ለመቀጠል በጣም ፈጣኑን መንገድ ይምረጡ።',
          'phone_label': 'የስልክ ቁጥር',
          'phone_hint': 'ለምሳሌ፡ 0501234567',
          'get_code': 'የማረጋገጫ ኮድ ላክ',
          'enter_code': 'የSMS ኮድ ያስገቡ',
          'verify': 'ያረጋግጡ እና ይግቡ',
          'or': 'ወይም',
          'guest': 'እንደ እንግዳ ቀጥል',
          'signup': 'መመዝገብ',
          'no_account': 'መለያ የለዎትም? ',
          'not_registered_title': 'ተጠቃሚው አልተመዘገበም',
          'not_registered_body': 'ያስገቡት የስልክ ቁጥር አልተመዘገበም። መመዝገብ ይፈልጋሉ?',
          'ok': 'እሺ',
          'invalid_phone': 'እባክዎ ትክክለኛ የእስራኤል የስልክ ቁጥር ያስገቡ (05XXXXXXXX)',
          'edit_phone': 'የስልክ ቁጥር ያስተካክሉ',
          'secure_title': 'ደህንነቱ የተጠበቀ መግቢያ',
          'secure_body': 'በስልክ የሚደረግ ማረጋገጫ ለታማኝ መዳረሻ።',
          'mobile_title': 'በሞባይል ፈጣን',
          'mobile_body': 'ለፈጣን ግቤት እና ግልጽ እርምጃዎች የተመቻቸ።',
          'guest_title': 'የእንግዳ አማራጭ',
          'guest_body': 'ያለ ሙሉ መለያ በቀጥታ ይጀምሩ።',
          'delete_feedback_title': 'የሆነውን ንገሩን',
          'delete_feedback_body':
              'መለያዎ ተሰርዟል። ካለዎት ትንሽ ጊዜ ምክንያቱን ያካፍሉን እንዲሁ Hiroን እንሻሻል።',
          'delete_feedback_hint': 'ዋናው ምክንያት ምን ነበር?',
          'delete_feedback_skip': 'ዝለል',
          'delete_feedback_send': 'ላክ',
          'delete_feedback_sent': 'ለአስተያየትዎ እናመሰግናለን',
          'change_language': 'ቋንቋ ቀይር',
          'verification_failed': 'ማረጋገጫ አልተሳካም: {msg}',
          'generic_error': 'ስህተት: {err}',
          'invalid_code_error': 'ልክ ያልሆነ ኮድ ወይም ስህተት ተከሰተ',
          'sign_in_error': 'የመግቢያ ስህተት: {err}',
        };
      default:
        return {
          'welcome': 'Welcome',
          'subtitle': 'Enter your phone number and confirm the SMS code.',
          'access': 'Professional Access',
          'signin_title': 'Sign In',
          'signin_subtitle': 'Choose the fastest way to continue.',
          'phone_label': 'Phone Number',
          'phone_hint': 'e.g. 0501234567',
          'get_code': 'Send Verification Code',
          'enter_code': 'Enter SMS Code',
          'verify': 'Verify & Sign In',
          'or': 'or',
          'guest': 'Continue as Guest',
          'signup': 'Register',
          'no_account': "Don't have an account? ",
          'not_registered_title': 'User Not Registered',
          'not_registered_body':
              'The phone number you entered is not registered. Would you like to sign up?',
          'ok': 'OK',
          'invalid_phone':
              'Please enter a valid Israeli phone number (05XXXXXXXX)',
          'edit_phone': 'Edit Phone Number',
          'secure_title': 'Secure sign-in',
          'secure_body': 'Phone verification built for trusted access.',
          'mobile_title': 'Fast on mobile',
          'mobile_body': 'Optimized for quick entry and clear actions.',
          'guest_title': 'Guest option',
          'guest_body': 'Browse immediately without a full account.',
          'delete_feedback_title': 'Tell us what happened',
          'delete_feedback_body':
              'Your account has been deleted. If you have a moment, tell us what made you leave so we can improve Hiro.',
          'delete_feedback_hint': 'What was the main reason?',
          'delete_feedback_skip': 'Skip',
          'delete_feedback_send': 'Send',
          'delete_feedback_sent': 'Thanks for the feedback',
          'change_language': 'Change language',
          'verification_failed': 'Verification Failed: {msg}',
          'generic_error': 'Error: {err}',
          'invalid_code_error': 'Invalid code or an error occurred',
          'sign_in_error': 'Sign in error: {err}',
        };
    }
  }

  Future<void> _showDeletionFeedbackDialog() async {
    final strings = _getLocalizedStrings(context);
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F3FF),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Icon(
                  Icons.rate_review_outlined,
                  color: Color(0xFF1976D2),
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                strings['delete_feedback_title']!,
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
                strings['delete_feedback_body']!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: strings['delete_feedback_hint']!,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
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
                    borderSide: const BorderSide(
                      color: Color(0xFF1976D2),
                      width: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(strings['delete_feedback_skip']!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(strings['delete_feedback_send']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();

    if (reason == null || reason.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('accountDeletionFeedback')
          .add({'reason': reason, 'createdAt': FieldValue.serverTimestamp()});
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['delete_feedback_sent']!)));
    } catch (_) {
      // Feedback is optional; failed writes should not block sign-in.
    }
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

  Future<bool> _isPhoneRegistered(String normalizedPhone) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('phone', isEqualTo: normalizedPhone)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  Future<void> _sendCode() async {
    final strings = _getLocalizedStrings(context);
    String input = _phoneController.text.trim();
    if (input.isEmpty) return;

    String phone = _normalizePhone(input);
    final regExp = RegExp(r'^\+9725\d{8}$');

    if (!regExp.hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings['invalid_phone'] ?? 'Invalid phone number'),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final isRegistered = await _isPhoneRegistered(phone);
      if (!isRegistered) {
        if (mounted) {
          setState(() => _loading = false);
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                strings['not_registered_title'] ?? 'User Not Registered',
              ),
              content: Text(
                strings['not_registered_body'] ??
                    'The phone number you entered is not registered.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings['ok'] ?? 'OK'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignUpPage()),
                    );
                  },
                  child: Text(strings['signup'] ?? 'Sign Up'),
                ),
              ],
            ),
          );
        }
        return;
      }

      await AnalyticsService.logSignInCodeRequested();
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _signInAndCheckRegistration(credential);
        },
        verificationFailed: (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  strings['verification_failed']!.replaceAll(
                    '{msg}',
                    e.message ?? '',
                  ),
                ),
              ),
            );
            setState(() => _loading = false);
          }
        },
        codeSent: (verificationId, resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _codeSent = true;
              _loading = false;
            });
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings['generic_error']!.replaceAll('{err}', e.toString()),
            ),
          ),
        );
      }
    }
  }

  Future<void> _verifyCode() async {
    final strings = _getLocalizedStrings(context);
    if (_codeController.text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: _codeController.text.trim(),
      );
      await _signInAndCheckRegistration(credential);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings['invalid_code_error']!)));
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _signInAndCheckRegistration(
    PhoneAuthCredential credential,
  ) async {
    final strings = _getLocalizedStrings(context);
    try {
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = userCredential.user;

      if (user != null) {
        final firestore = FirebaseFirestore.instance;

        // Check unified 'users' collection
        DocumentSnapshot userDoc = await firestore
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          await AnalyticsService.logSignInSuccess(method: 'phone');
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MyHomePage()),
            );
          }
        } else {
          // User is authenticated but NOT in our database
          await AuthService().signOut();
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(
                  strings['not_registered_title'] ?? 'User Not Registered',
                ),
                content: Text(
                  strings['not_registered_body'] ??
                      'The phone number you entered is not registered.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings['ok'] ?? 'OK'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignUpPage()),
                      );
                    },
                    child: Text(strings['signup'] ?? 'Sign Up'),
                  ),
                ],
              ),
            );
            setState(() {
              _loading = false;
              _codeSent = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("SIGN IN ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings['sign_in_error']!.replaceAll('{err}', e.toString()),
            ),
          ),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _handleGuestSignIn() async {
    await AnalyticsService.logGuestSignIn();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MyHomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureAnimationControllers();
    final strings = _getLocalizedStrings(context);
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';
    final backgroundController = _backgroundAnimationController;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFF),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 980;
            final horizontalPadding = isWide
                ? 64.0
                : (constraints.maxWidth < 420 ? 20.0 : 28.0);
            final verticalPadding = isWide ? 64.0 : 28.0;

            return Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: backgroundController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _SignInBackgroundPainter(
                          backgroundController.value,
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(
                          0,
                          constraints.maxHeight -
                              MediaQuery.paddingOf(context).vertical,
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                          vertical: verticalPadding,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1440),
                            child: isWide
                                ? _buildWideLayout(strings, isRtl)
                                : _buildNarrowLayout(strings),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, right: 14),
                      child: _buildLanguageButton(context),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLanguageButton(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;
    final currentLabel = _languageShortLabel(localeCode);

    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: PopupMenuButton<String>(
          tooltip: strings['change_language']!,
          offset: const Offset(0, 12),
          onSelected: (code) {
            Provider.of<LanguageProvider>(
              context,
              listen: false,
            ).setLocale(code);
          },
          itemBuilder: (context) => [
            _buildLanguageMenuItem(
              value: 'en',
              label: 'English',
              currentCode: localeCode,
            ),
            _buildLanguageMenuItem(
              value: 'he',
              label: 'עברית',
              currentCode: localeCode,
            ),
            _buildLanguageMenuItem(
              value: 'ar',
              label: 'العربية',
              currentCode: localeCode,
            ),
            _buildLanguageMenuItem(
              value: 'ru',
              label: 'Русский',
              currentCode: localeCode,
            ),
            _buildLanguageMenuItem(
              value: 'am',
              label: 'አማርኛ',
              currentCode: localeCode,
            ),
          ],
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.96),
                  const Color(0xFFF4F8FF).withValues(alpha: 0.96),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.98)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.language_rounded,
                  size: 18,
                  color: Color(0xFF1976D2),
                ),
                const SizedBox(width: 8),
                Text(
                  currentLabel,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: Color(0xFF64748B),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildLanguageMenuItem({
    required String value,
    required String label,
    required String currentCode,
  }) {
    final isSelected = value == currentCode;
    return PopupMenuItem<String>(
      value: value,
      height: 48,
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 18,
            color: isSelected
                ? const Color(0xFF1976D2)
                : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF334155),
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _languageShortLabel(String localeCode) {
    switch (localeCode) {
      case 'he':
        return 'HE';
      case 'ar':
        return 'AR';
      case 'ru':
        return 'RU';
      case 'am':
        return 'AM';
      default:
        return 'EN';
    }
  }

  Widget _buildWideLayout(Map<String, String> strings, bool isRtl) {
    final intro = Expanded(
      child: _buildAnimatedEntry(
        delay: 0.0,
        begin: isRtl ? const Offset(0.06, 0) : const Offset(-0.06, 0),
        child: _buildIntroPanel(strings, compact: false),
      ),
    );
    final form = _buildAnimatedEntry(
      delay: 0.18,
      begin: isRtl ? const Offset(-0.06, 0) : const Offset(0.06, 0),
      child: _buildAuthColumn(strings, compact: false),
    );
    final gap = const SizedBox(width: 64);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: isRtl ? [form, gap, intro] : [intro, gap, form],
    );
  }

  Widget _buildNarrowLayout(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAnimatedEntry(
          delay: 0.0,
          child: _buildIntroPanel(strings, compact: true),
        ),
        const SizedBox(height: 24),
        _buildAnimatedEntry(
          delay: 0.14,
          child: _buildSignInCard(strings, compact: true),
        ),
        const SizedBox(height: 22),
        _buildFeatureHighlights(strings, compact: true),
        const SizedBox(height: 22),
        _buildSignUpLink(strings),
      ],
    );
  }

  Widget _buildAnimatedEntry({
    required Widget child,
    double delay = 0,
    Offset begin = const Offset(0, 0.08),
  }) {
    final start = delay.clamp(0.0, 0.9).toDouble();
    final animation = CurvedAnimation(
      parent: _introAnimationController,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: begin,
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  Widget _buildAuthColumn(
    Map<String, String> strings, {
    required bool compact,
  }) {
    return SizedBox(
      width: compact ? double.infinity : 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _backgroundAnimationController,
            builder: (context, child) {
              final offset =
                  math.sin(_backgroundAnimationController.value * math.pi * 2) *
                  5;
              return Transform.translate(
                offset: Offset(0, offset),
                child: child,
              );
            },
            child: _buildSignInCard(strings, compact: compact),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroPanel(
    Map<String, String> strings, {
    required bool compact,
  }) {
    final textAlign = compact ? TextAlign.center : TextAlign.start;
    final alignment = compact
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        _buildAccessPill(strings),
        SizedBox(height: compact ? 24 : 28),
        Text(
          strings['welcome'] ?? 'Welcome',
          textAlign: textAlign,
          style: TextStyle(
            color: const Color(0xFF070B18),
            fontSize: compact ? 42 : 58,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 520 : 620),
          child: Text(
            strings['subtitle'] ?? 'Enter your phone number.',
            textAlign: textAlign,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 20,
              height: 1.45,
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 48),
          _buildFeatureHighlights(strings, compact: false),
          const SizedBox(height: 92),
          _buildSignUpLink(strings),
        ],
      ],
    );
  }

  Widget _buildAccessPill(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF1976D2),
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              (strings['access'] ?? 'Professional Access').toUpperCase(),
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: Color(0xFF1976D2),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureHighlights(
    Map<String, String> strings, {
    required bool compact,
  }) {
    final features = [
      _SignInFeature(
        icon: Icons.verified_user_rounded,
        title: strings['secure_title'] ?? 'Secure sign-in',
        body: strings['secure_body'] ?? 'Phone verification built for access.',
      ),
      _SignInFeature(
        icon: Icons.phone_iphone_rounded,
        title: strings['mobile_title'] ?? 'Fast on mobile',
        body: strings['mobile_body'] ?? 'Optimized for quick entry.',
      ),
      _SignInFeature(
        icon: Icons.person_outline_rounded,
        title: strings['guest_title'] ?? 'Guest option',
        body: strings['guest_body'] ?? 'Browse without a full account.',
      ),
    ];

    if (compact) {
      return Column(
        children: [
          for (var index = 0; index < features.length; index++) ...[
            _buildAnimatedEntry(
              delay: 0.24 + index * 0.06,
              child: _buildFeatureCard(features[index], compact: true),
            ),
            if (index != features.length - 1) const SizedBox(height: 12),
          ],
        ],
      );
    }

    return Wrap(
      spacing: 18,
      runSpacing: 18,
      children: [
        for (var index = 0; index < features.length; index++)
          _buildAnimatedEntry(
            delay: 0.24 + index * 0.06,
            begin: const Offset(0, 0.12),
            child: SizedBox(
              width: 190,
              height: 156,
              child: _buildFeatureCard(features[index], compact: false),
            ),
          ),
      ],
    );
  }

  Widget _buildFeatureCard(_SignInFeature feature, {required bool compact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B2A41).withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: compact
          ? Row(
              children: [
                Icon(feature.icon, color: const Color(0xFF1976D2), size: 30),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        feature.title,
                        style: const TextStyle(
                          color: Color(0xFF101827),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        feature.body,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(feature.icon, color: const Color(0xFF1976D2), size: 34),
                const Spacer(),
                Text(
                  feature.title,
                  style: const TextStyle(
                    color: Color(0xFF101827),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  feature.body,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 14,
                    height: 1.25,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSignInCard(
    Map<String, String> strings, {
    required bool compact,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 24 : 42),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(compact ? 28 : 34),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),
            blurRadius: 48,
            offset: const Offset(0, 28),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLogoMark(),
          const SizedBox(height: 26),
          Text(
            strings['signin_title'] ?? 'Sign In',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF070B18),
              fontSize: compact ? 34 : 38,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            strings['signin_subtitle'] ?? 'Choose the fastest way to continue.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 17,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 34),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: _codeSent
                ? KeyedSubtree(
                    key: const ValueKey('code-input'),
                    child: _buildCodeInput(strings),
                  )
                : KeyedSubtree(
                    key: const ValueKey('phone-input'),
                    child: _buildPhoneInput(strings),
                  ),
          ),
          const SizedBox(height: 26),
          _buildDivider(strings),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: OutlinedButton(
              onPressed: _loading ? null : _handleGuestSignIn,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF374151),
                side: const BorderSide(color: Color(0xFFDCE5EE)),
                backgroundColor: Colors.white.withValues(alpha: 0.65),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_outline_rounded, size: 23),
                    const SizedBox(width: 14),
                    Text(
                      strings['guest'] ?? 'Continue as Guest',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
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

  Widget _buildLogoMark() {
    return GestureDetector(
      onTap: _playLogoTapAnimation,
      child: AnimatedBuilder(
        animation: _logoTapAnimationController,
        builder: (context, child) {
          return Transform.rotate(
            angle: _logoTwistAnimation.value,
            child: Transform.scale(
              scale: _logoScaleAnimation.value,
              child: Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  image: const DecorationImage(
                    image: AssetImage('assets/icon/app_icon.jpg'),
                    fit: BoxFit.cover,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(
                        0xFF1976D2,
                      ).withValues(alpha: _logoGlowAnimation.value),
                      blurRadius: 30,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPhoneInput(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings['phone_label'] ?? 'Phone Number',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 9),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: strings['phone_hint'],
            hintStyle: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: const Icon(
              Icons.phone_iphone_rounded,
              color: Color(0xFF9CA3AF),
              size: 22,
            ),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: Color(0xFF1976D2),
                width: 1.4,
              ),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 18,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildPrimaryButton(
          label: strings['get_code'] ?? 'Send Verification Code',
          icon: Icons.sms_outlined,
          onPressed: _loading ? null : _sendCode,
        ),
      ],
    );
  }

  Widget _buildCodeInput(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings['enter_code'] ?? 'Enter SMS Code',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 9),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: Color(0xFF1976D2),
                width: 1.4,
              ),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 18,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildPrimaryButton(
          label: strings['verify'] ?? 'Verify & Sign In',
          icon: Icons.verified_rounded,
          onPressed: _loading ? null : _verifyCode,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _codeSent = false),
            child: Text(
              strings['edit_phone'] ?? 'Edit Phone Number',
              style: const TextStyle(
                color: Color(0xFF1976D2),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF8ABCEA),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _loading
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : FittedBox(
                  key: ValueKey(label),
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 18,
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

  Widget _buildDivider(Map<String, String> strings) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            strings['or'] ?? 'or',
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
      ],
    );
  }

  Widget _buildSignUpLink(Map<String, String> strings) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          strings['no_account'] ?? "Don't have an account? ",
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 16,
            height: 1.4,
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SignUpPage()),
          ),
          child: Text(
            strings['signup'] ?? 'Sign Up',
            style: const TextStyle(
              color: Color(0xFF1976D2),
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _SignInFeature {
  const _SignInFeature({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _SignInBackgroundPainter extends CustomPainter {
  const _SignInBackgroundPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final eased = Curves.easeInOut.transform(progress);
    final begin = Alignment.lerp(Alignment.topLeft, Alignment.topRight, eased)!;
    final end = Alignment.lerp(
      Alignment.bottomRight,
      Alignment.bottomLeft,
      eased,
    )!;

    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: begin,
        end: end,
        colors: const [
          Color(0xFFFDFEFF),
          Color(0xFFEAF5FF),
          Color(0xFFF7FBFF),
          Color(0xFFE3F8FF),
        ],
        stops: const [0, 0.38, 0.68, 1],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    final width = size.width;
    final height = size.height;
    final phase = progress * math.pi * 2;

    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(120, size.shortestSide * 0.18)
      ..color = const Color(0xFF1976D2).withValues(alpha: 0.055)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 54);
    final path = Path()
      ..moveTo(-width * 0.2, height * (0.22 + math.sin(phase) * 0.03))
      ..cubicTo(
        width * 0.24,
        height * (0.02 + math.cos(phase) * 0.04),
        width * 0.58,
        height * (0.54 + math.sin(phase) * 0.03),
        width * 1.2,
        height * (0.25 + math.cos(phase) * 0.03),
      );
    canvas.drawPath(path, highlightPaint);

    final lowerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(90, size.shortestSide * 0.13)
      ..color = const Color(0xFF62D6E8).withValues(alpha: 0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 46);
    final lowerPath = Path()
      ..moveTo(width * 0.36, height * 1.12)
      ..cubicTo(
        width * (0.46 + math.sin(phase) * 0.04),
        height * 0.78,
        width * (0.72 + math.cos(phase) * 0.03),
        height * 0.95,
        width * 1.16,
        height * (0.65 + math.sin(phase) * 0.04),
      );
    canvas.drawPath(lowerPath, lowerPaint);
  }

  @override
  bool shouldRepaint(covariant _SignInBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
