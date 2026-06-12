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
          .collection('users')
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
        'invalid-email' => 'The email address is invalid.',
        'user-not-found' => 'No password account was found for this email.',
        'operation-not-allowed' =>
          'Email/password sign-in must be enabled in Firebase Authentication.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        _ => e.message ?? e.code,
      };
      _showSnack(message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack(e.toString());
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

    const subject = 'בקשה לעזרה בשחזור סיסמה';
    final body =
        'שלום לצוות Hiro,\n\n'
        'אין לי כרגע גישה לכתובת האימייל שמחוברת לחשבון שלי.\n\n'
        'אימייל החשבון: $accountEmail\n'
        'מספר טלפון: $phone\n\n'
        'אשמח לעזרתכם בשחזור הגישה לחשבון.';
    final uri = Uri.parse(
      'mailto:my.hire.hub@gmail.com'
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
