import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/analytics_service.dart';
import 'package:untitled1/sign_up.dart';
import 'main.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> with TickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  AnimationController? _introController;
  AnimationController? _backgroundController;

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

  void _ensureAnimationControllers() {
    _introAnimationController;
    _backgroundAnimationController;
  }

  String _verificationId = "";
  bool _codeSent = false;
  bool _loading = false;

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
              SnackBar(content: Text("Verification Failed: ${e.message}")),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _verifyCode() async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid code or an error occurred")),
        );
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
          await FirebaseAuth.instance.signOut();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Sign in error: $e")));
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
              ],
            );
          },
        ),
      ),
    );
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
            style: const TextStyle(
              color: Color(0xFF1976D2),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
            ),
          ),
        ],
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
    return Container(
      width: 78,
      height: 78,
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
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'H',
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
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
