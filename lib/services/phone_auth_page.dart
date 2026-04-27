import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import '../main.dart';

/// A page that handles phone number authentication using Firebase Auth.
class PhoneAuthPage extends StatefulWidget {
  final bool isReauth;
  final Function(String)? onVerified;

  const PhoneAuthPage({super.key, this.isReauth = false, this.onVerified});

  @override
  State<PhoneAuthPage> createState() => _PhoneAuthPageState();
}

class _PhoneAuthPageState extends State<PhoneAuthPage>
    with TickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  String _verificationId = "";
  bool _codeSent = false;
  bool _loading = false;
  AnimationController? _introController;
  AnimationController? _backgroundController;

  /// Returns localized strings based on the current app locale.
  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'אימות טלפוני',
          'phone_label': 'מספר טלפון',
          'phone_hint': '05X-XXXXXXX',
          'send_code': 'שלח קוד',
          'code_label': 'קוד אימות',
          'code_hint': 'הכנס את הקוד שקיבלת',
          'verify': 'אמת והתחבר',
          'verify_reauth': 'אמת ועדכן',
          'invalid_phone': 'מספר טלפון לא תקין',
        };
      case 'am':
        return {
          'title': 'የስልክ ማረጋገጫ',
          'phone_label': 'የስልክ ቁጥር',
          'phone_hint': '05X-XXXXXXX',
          'send_code': 'ኮድ ላክ',
          'code_label': 'የማረጋገጫ ኮድ',
          'code_hint': 'የተቀበሉትን ኮድ ያስገቡ',
          'verify': 'አረጋግጥ እና ግባ',
          'verify_reauth': 'አረጋግጥ እና አዘምን',
          'invalid_phone': 'ትክክለኛ ያልሆነ የስልክ ቁጥር',
        };
      default:
        return {
          'title': 'Phone Authentication',
          'subtitle': 'Verify your number to keep your account secure.',
          'access': 'Secure Access',
          'phone_label': 'Phone Number',
          'phone_hint': '05X-XXXXXXX',
          'send_code': 'Send Code',
          'code_label': 'Verification Code',
          'code_hint': 'Enter the code you received',
          'verify': 'Verify & Sign In',
          'verify_reauth': 'Verify & Update',
          'invalid_phone': 'Invalid phone number',
        };
    }
  }

  @override
  void initState() {
    super.initState();
    _ensureAnimationControllers();
  }

  @override
  void dispose() {
    _introController?.dispose();
    _backgroundController?.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  AnimationController get _introAnimationController {
    final controller = _introController;
    if (controller != null) return controller;
    final created = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
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

  void _ensureAnimationControllers() {
    _introAnimationController;
    _backgroundAnimationController;
  }

  /// Sanitizes and formats the phone number for Firebase.
  /// Handles formats: +9725XXXXXXXX, 05XXXXXXXX, +97205XXXXXXXX
  String _formatPhoneNumber(String phone) {
    phone = phone.replaceAll(RegExp(r'[\s\-]'), ''); // Remove spaces and dashes

    if (phone.startsWith('0')) {
      return '+972${phone.substring(1)}';
    }

    if (phone.startsWith('+9720')) {
      return '+972${phone.substring(5)}';
    }

    if (RegExp(r'^\d{9}$').hasMatch(phone)) {
      // If 9 digits provided without leading 0 or prefix
      return '+972$phone';
    }

    if (!phone.startsWith('+')) {
      return '+$phone';
    }

    return phone;
  }

  /// Initiates the phone number verification process.
  Future<void> _verifyPhone() async {
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.isEmpty) return;

    final formattedPhone = _formatPhoneNumber(rawPhone);

    setState(() => _loading = true);

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          if (widget.isReauth) {
            if (widget.onVerified != null) {
              widget.onVerified!(formattedPhone);
            }
            return;
          }
          await FirebaseAuth.instance.signInWithCredential(credential);
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MyHomePage()),
            );
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? "Verification Failed")),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _codeSent = true;
            _loading = false;
          });
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  /// Signs the user in or verifies the code for re-authentication.
  Future<void> _signInWithCode() async {
    setState(() => _loading = true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: _codeController.text.trim(),
      );

      if (widget.isReauth) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await user.updatePhoneNumber(credential);
          if (widget.onVerified != null) {
            // Pass back the formatted phone number
            final formattedPhone = _formatPhoneNumber(
              _phoneController.text.trim(),
            );
            widget.onVerified!(formattedPhone);
          }
        }
      } else {
        await FirebaseAuth.instance.signInWithCredential(credential);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MyHomePage()),
          );
        }
      }
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureAnimationControllers();
    final strings = _getLocalizedStrings(context);
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;
    final isRtl = localeCode == 'he' || localeCode == 'ar';
    final backgroundController = _backgroundAnimationController;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFF),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 420 ? 20.0 : 28.0;
            return Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: backgroundController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _PhoneAuthBackgroundPainter(
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
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          24,
                          horizontalPadding,
                          24,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 540),
                            child: _buildAnimatedEntry(
                              delay: 0.05,
                              child: _buildAuthShellCard(strings),
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildAuthShellCard(Map<String, String> strings) {
    final content = _codeSent
        ? _buildCodeInput(strings)
        : _buildPhoneInput(strings);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(30),
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
          if (widget.isReauth)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
                color: const Color(0xFF1F2937),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              ),
            ),
          _buildAccessPill(strings),
          const SizedBox(height: 18),
          const Icon(
            Icons.phone_android_rounded,
            size: 34,
            color: Color(0xFF1976D2),
          ),
          const SizedBox(height: 14),
          Text(
            strings['title'] ?? 'Phone Authentication',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF070B18),
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            strings['subtitle'] ??
                'Verify your number to keep your account secure.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 16,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          else
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey(_codeSent ? 'code' : 'phone'),
                child: content,
              ),
            ),
        ],
      ),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.verified_user_rounded,
            color: Color(0xFF1976D2),
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            (strings['access'] ?? 'Secure Access').toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF1976D2),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneInput(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputField(
          controller: _phoneController,
          labelText: strings['phone_label'] ?? 'Phone Number',
          hintText: strings['phone_hint'],
          icon: Icons.phone_iphone_rounded,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 24),
        _buildPrimaryButton(
          label: strings['send_code']!,
          icon: Icons.sms_outlined,
          onPressed: _verifyPhone,
        ),
      ],
    );
  }

  Widget _buildCodeInput(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputField(
          controller: _codeController,
          labelText: strings['code_label'] ?? 'Verification Code',
          hintText: strings['code_hint'],
          icon: Icons.sms_rounded,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 24),
        _buildPrimaryButton(
          label: widget.isReauth
              ? strings['verify_reauth']!
              : strings['verify']!,
          icon: Icons.verified_rounded,
          onPressed: _signInWithCode,
        ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(
        color: Color(0xFF111827),
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF9CA3AF),
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 22),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF1976D2), width: 1.4),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: const Color(0xFF1976D2),
          shadowColor: const Color(0xFF1976D2).withValues(alpha: 0.35),
          elevation: 10,
        ),
      ),
    );
  }
}

class _PhoneAuthBackgroundPainter extends CustomPainter {
  const _PhoneAuthBackgroundPainter(this.progress);

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
  bool shouldRepaint(covariant _PhoneAuthBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
