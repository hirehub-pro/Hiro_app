import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Map<String, String> _strings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'שחזור סיסמה',
          'subtitle': 'הכניסו אימייל ומספר טלפון כדי לוודא שזה החשבון שלכם.',
          'email': 'אימייל',
          'phone': 'מספר טלפון',
          'phone_hint': 'לדוגמה: 0501234567',
          'send': 'שלח אימייל איפוס',
          'sent_title': 'בדקו את האימייל',
          'sent_body':
              'שלחנו קישור מאובטח לאיפוס הסיסמה. פתחו אותו כדי לאמת שזה אתם ולהגדיר סיסמה חדשה.',
          'required': 'יש למלא אימייל ומספר טלפון.',
          'invalid_phone': 'מספר הטלפון לא תקין.',
          'not_match': 'האימייל ומספר הטלפון לא שייכים לאותו משתמש.',
          'back': 'חזרה להתחברות',
          'no_email_access': 'אין לי גישה לאימייל כרגע',
          'contact_failed': 'לא הצלחנו לפתוח את אפליקציית האימייל.',
          'phone_required_contact': 'יש להזין מספר טלפון לפני יצירת קשר.',
          'invalid_email': 'כתובת האימייל אינה תקינה.',
          'user_not_found': 'לא נמצא חשבון סיסמה עבור האימייל הזה.',
          'operation_not_allowed':
              'התחברות באמצעות אימייל וסיסמה אינה זמינה כרגע.',
          'too_many_requests': 'בוצעו יותר מדי ניסיונות. נסו שוב מאוחר יותר.',
          'reset_failed': 'לא הצלחנו לאפס את הסיסמה. נסו שוב מאוחר יותר.',
          'support_subject': 'בקשה לעזרה בשחזור סיסמה',
          'support_body':
              'שלום לצוות Hiro,\n\nאין לי כרגע גישה לכתובת האימייל שמחוברת לחשבון שלי.\n\nאימייל החשבון: {email}\nמספר טלפון: {phone}\n\nאשמח לעזרתכם בשחזור הגישה לחשבון.',
        };
      case 'ar':
        return {
          'title': 'استعادة كلمة المرور',
          'subtitle': 'أدخل البريد والهاتف للتأكد من أنه حسابك.',
          'email': 'البريد الإلكتروني',
          'phone': 'رقم الهاتف',
          'phone_hint': 'مثال: 0501234567',
          'send': 'إرسال بريد إعادة التعيين',
          'sent_title': 'تحقق من بريدك',
          'sent_body':
              'أرسلنا رابطًا آمنًا لإعادة تعيين كلمة المرور. افتحه لتأكيد هويتك وتعيين كلمة مرور جديدة.',
          'required': 'أدخل البريد الإلكتروني ورقم الهاتف.',
          'invalid_phone': 'رقم الهاتف غير صالح.',
          'not_match': 'البريد ورقم الهاتف لا يخصان نفس المستخدم.',
          'back': 'العودة لتسجيل الدخول',
          'no_email_access': 'لا يمكنني الوصول إلى البريد الآن',
          'contact_failed': 'تعذر فتح تطبيق البريد الإلكتروني.',
          'phone_required_contact': 'أدخل رقم الهاتف قبل التواصل معنا.',
          'invalid_email': 'عنوان البريد الإلكتروني غير صالح.',
          'user_not_found': 'لم يتم العثور على حساب بكلمة مرور لهذا البريد.',
          'operation_not_allowed':
              'تسجيل الدخول بالبريد الإلكتروني وكلمة المرور غير متاح حاليًا.',
          'too_many_requests': 'عدد المحاولات كبير جدًا. حاول مرة أخرى لاحقًا.',
          'reset_failed':
              'تعذرت إعادة تعيين كلمة المرور. حاول مرة أخرى لاحقًا.',
          'support_subject': 'طلب مساعدة في استعادة كلمة المرور',
          'support_body':
              'مرحبًا بفريق Hiro،\n\nلا يمكنني حاليًا الوصول إلى البريد الإلكتروني المرتبط بحسابي.\n\nبريد الحساب: {email}\nرقم الهاتف: {phone}\n\nأرجو مساعدتي في استعادة الوصول إلى حسابي.',
        };
      case 'ru':
        return {
          'title': 'Восстановление пароля',
          'subtitle':
              'Введите электронную почту и номер телефона, чтобы подтвердить аккаунт.',
          'email': 'Электронная почта',
          'phone': 'Номер телефона',
          'phone_hint': 'например: 0501234567',
          'send': 'Отправить письмо для сброса',
          'sent_title': 'Проверьте почту',
          'sent_body':
              'Мы отправили безопасную ссылку для сброса пароля. Откройте её, чтобы подтвердить свою личность и задать новый пароль.',
          'required': 'Введите электронную почту и номер телефона.',
          'invalid_phone': 'Введите действительный номер телефона.',
          'not_match':
              'Электронная почта и номер телефона не принадлежат одному аккаунту.',
          'back': 'Вернуться ко входу',
          'no_email_access': 'Сейчас у меня нет доступа к этой почте',
          'contact_failed': 'Не удалось открыть почтовое приложение.',
          'phone_required_contact':
              'Введите номер телефона, прежде чем связаться с нами.',
          'invalid_email': 'Недействительный адрес электронной почты.',
          'user_not_found':
              'Для этой электронной почты не найден аккаунт с паролем.',
          'operation_not_allowed':
              'Вход по электронной почте и паролю сейчас недоступен.',
          'too_many_requests':
              'Слишком много попыток. Повторите попытку позже.',
          'reset_failed':
              'Не удалось сбросить пароль. Повторите попытку позже.',
          'support_subject': 'Помощь с восстановлением пароля',
          'support_body':
              'Здравствуйте, команда Hiro!\n\nСейчас у меня нет доступа к электронной почте, связанной с моим аккаунтом.\n\nПочта аккаунта: {email}\nНомер телефона: {phone}\n\nПомогите, пожалуйста, восстановить доступ к аккаунту.',
        };
      case 'am':
        return {
          'title': 'የይለፍ ቃል መልሶ ማግኘት',
          'subtitle': 'መለያው የእርስዎ መሆኑን ለማረጋገጥ ኢሜይልዎን እና ስልክ ቁጥርዎን ያስገቡ።',
          'email': 'ኢሜይል',
          'phone': 'የስልክ ቁጥር',
          'phone_hint': 'ለምሳሌ፡ 0501234567',
          'send': 'የይለፍ ቃል ማስጀመሪያ ኢሜይል ላክ',
          'sent_title': 'ኢሜይልዎን ይመልከቱ',
          'sent_body':
              'የይለፍ ቃልዎን ለማደስ ደህንነቱ የተጠበቀ አገናኝ ልከናል። ማንነትዎን ለማረጋገጥ እና አዲስ የይለፍ ቃል ለማዘጋጀት ይክፈቱት።',
          'required': 'ኢሜይልዎን እና ስልክ ቁጥርዎን ያስገቡ።',
          'invalid_phone': 'ትክክለኛ የስልክ ቁጥር ያስገቡ።',
          'not_match': 'ኢሜይሉ እና ስልክ ቁጥሩ የአንድ ተጠቃሚ አይደሉም።',
          'back': 'ወደ መግቢያ ተመለስ',
          'no_email_access': 'አሁን ወደዚያ ኢሜይል መግባት አልችልም',
          'contact_failed': 'የኢሜይል መተግበሪያዎን መክፈት አልተቻለም።',
          'phone_required_contact': 'እኛን ከማነጋገርዎ በፊት ስልክ ቁጥርዎን ያስገቡ።',
          'invalid_email': 'የኢሜይል አድራሻው ትክክል አይደለም።',
          'user_not_found': 'ለዚህ ኢሜይል የይለፍ ቃል መለያ አልተገኘም።',
          'operation_not_allowed': 'በኢሜይልና በይለፍ ቃል መግባት አሁን አይገኝም።',
          'too_many_requests': 'ብዙ ሙከራዎች ተደርገዋል። እባክዎ ቆይተው እንደገና ይሞክሩ።',
          'reset_failed': 'የይለፍ ቃሉን ማደስ አልተቻለም። እባክዎ ቆይተው እንደገና ይሞክሩ።',
          'support_subject': 'የይለፍ ቃል መልሶ ለማግኘት የእገዛ ጥያቄ',
          'support_body':
              'ሰላም የHiro ቡድን፣\n\nአሁን ከመለያዬ ጋር የተገናኘውን ኢሜይል መድረስ አልችልም።\n\nየመለያ ኢሜይል፡ {email}\nየስልክ ቁጥር፡ {phone}\n\nወደ መለያዬ እንድገባ እርዳታዎን እጠይቃለሁ።',
        };
      default:
        return {
          'title': 'Forgot Password',
          'subtitle':
              'Enter your email and phone number so we can verify the account.',
          'email': 'Email',
          'phone': 'Phone Number',
          'phone_hint': 'e.g. 0501234567',
          'send': 'Send Reset Email',
          'sent_title': 'Check your email',
          'sent_body':
              'We sent a secure password reset link. Open it to verify it is you and set a new password.',
          'required': 'Enter your email and phone number.',
          'invalid_phone': 'Enter a valid phone number.',
          'not_match':
              'The email and phone number do not belong to the same user.',
          'back': 'Back to Sign In',
          'no_email_access': "I don't have access to that email right now",
          'contact_failed': 'Could not open your email app.',
          'phone_required_contact':
              'Please enter your phone number before contacting us.',
          'invalid_email': 'The email address is invalid.',
          'user_not_found': 'No password account was found for this email.',
          'operation_not_allowed':
              'Email/password sign-in is not available right now.',
          'too_many_requests': 'Too many attempts. Please try again later.',
          'reset_failed':
              'Could not reset the password. Please try again later.',
          'support_subject': 'Help with password recovery',
          'support_body':
              "Hello Hiro team,\n\nI currently don't have access to the email address connected to my account.\n\nAccount email: {email}\nPhone number: {phone}\n\nPlease help me restore access to my account.",
        };
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

  Future<void> _sendResetEmail() async {
    final strings = _strings(context);
    final email = _emailController.text.trim();
    final phone = _normalizePhone(_phoneController.text.trim());

    if (email.isEmpty || _phoneController.text.trim().isEmpty) {
      _showSnack(strings['required']!);
      return;
    }

    if (!RegExp(r'^\+9725\d{8}$').hasMatch(phone)) {
      _showSnack(strings['invalid_phone']!);
      return;
    }

    setState(() => _loading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('publicWorkerProfiles')
          .where('isSearchVisible', isEqualTo: true)
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        if (mounted) {
          setState(() => _loading = false);
          _showSnack(strings['not_match']!);
        }
        return;
      }

      final storedEmail = (snapshot.docs.first.data()['email'] ?? '')
          .toString()
          .trim();
      if (storedEmail.isEmpty ||
          storedEmail.toLowerCase() != email.toLowerCase()) {
        if (mounted) {
          setState(() => _loading = false);
          _showSnack(strings['not_match']!);
        }
        return;
      }

      await FirebaseAuth.instance.sendPasswordResetEmail(email: storedEmail);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sent = true;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final message = switch (e.code) {
        'invalid-email' => strings['invalid_email']!,
        'user-not-found' => strings['user_not_found']!,
        'operation-not-allowed' => strings['operation_not_allowed']!,
        'too-many-requests' => strings['too_many_requests']!,
        _ => strings['reset_failed']!,
      };
      _showSnack(message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      debugPrint('Password reset failed: $e');
      _showSnack(strings['reset_failed']!);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _contactSupport() async {
    final strings = _strings(context);
    final accountEmail = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showSnack(strings['phone_required_contact']!);
      return;
    }

    final subject = strings['support_subject']!;
    final body = strings['support_body']!
        .replaceAll('{email}', accountEmail)
        .replaceAll('{phone}', phone);
    final uri = Uri.parse(
      'mailto:support@hiro-services.com'
      '?subject=${Uri.encodeComponent(subject)}'
      '&body=${Uri.encodeComponent(body)}',
    );

    final opened = await launchUrl(uri);
    if (!opened && mounted) {
      _showSnack(strings['contact_failed']!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings(context);
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFF),
        body: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _ResetBackground())),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: Colors.white),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 44,
                            offset: const Offset(0, 24),
                          ),
                        ],
                      ),
                      child: _sent ? _buildSent(strings) : _buildForm(strings),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(Map<String, String> strings) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMark(Icons.lock_reset_rounded),
        const SizedBox(height: 24),
        Text(
          strings['title']!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF070B18),
            fontSize: 34,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          strings['subtitle']!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 16,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),
        _buildField(
          controller: _emailController,
          label: strings['email']!,
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        _buildField(
          controller: _phoneController,
          label: strings['phone']!,
          hint: strings['phone_hint'],
          icon: Icons.phone_iphone_rounded,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 58,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _sendResetEmail,
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.mark_email_read_outlined),
            label: Text(strings['send']!),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF8ABCEA),
              elevation: 0,
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _loading ? null : _contactSupport,
          icon: const Icon(Icons.support_agent_rounded),
          label: Text(strings['no_email_access']!, textAlign: TextAlign.center),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF1976D2),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(strings['back']!),
        ),
      ],
    );
  }

  Widget _buildSent(Map<String, String> strings) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMark(Icons.mark_email_read_outlined),
        const SizedBox(height: 24),
        Text(
          strings['sent_title']!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF070B18),
            fontSize: 32,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          strings['sent_body']!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 16,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _contactSupport,
          icon: const Icon(Icons.support_agent_rounded),
          label: Text(strings['no_email_access']!, textAlign: TextAlign.center),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF1976D2),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1976D2),
              side: const BorderSide(color: Color(0xFFBFD7F2)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              strings['back']!,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 9),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 22),
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
      ],
    );
  }

  Widget _buildMark(IconData icon) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 34),
    );
  }
}

class _ResetBackground extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFDFEFF),
          Color(0xFFEAF5FF),
          Color(0xFFF7FBFF),
          Color(0xFFE3F8FF),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    final curvePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * 0.16
      ..color = const Color(0xFF1976D2).withValues(alpha: 0.055)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 52);
    final path = Path()
      ..moveTo(-size.width * 0.15, size.height * 0.28)
      ..cubicTo(
        size.width * 0.2,
        size.height * 0.04,
        size.width * 0.7,
        size.height * 0.58,
        size.width * 1.15,
        size.height * 0.28,
      );
    canvas.drawPath(path, curvePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
