import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/sighn_up.dart';
import 'package:untitled1/auth_service.dart';
import 'package:untitled1/pages/phone_auth_page.dart';
import '../main.dart';

class SignInPage extends StatefulWidget {
  final String? initialEmail;
  const SignInPage({super.key, this.initialEmail});

  static Route route() {
    return MaterialPageRoute(builder: (_) => const SignInPage());
  }

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _emailCtrl;
  late TextEditingController _passwordCtrl;
  bool _loading = false;
  bool _obscure = true;

  final AuthService _authService = AuthService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instanceFor(
      app: FirebaseAuth.instance.app,
      databaseURL: 'https://hire-hub-fe6c4-default-rtdb.firebaseio.com'
  ).ref();

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail);
    _passwordCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Map<String, String> _getLocalizedStrings(BuildContext context, {bool listen = true}) {
    final locale = Provider.of<LanguageProvider>(context, listen: listen).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'welcome': 'ברוכים\nהבאים',
          'email': 'אימייל',
          'password': 'סיסמה',
          'forgot': 'שכחת סיסמה?',
          'signin': 'התחברות',
          'no_account': 'אין לך חשבון? ',
          'signup': 'הרשמה',
          'email_required': 'אימייל שדה חובה',
          'valid_email': 'הכנס אימייל תקין',
          'pass_required': 'סיסמה שדה חובה',
          'success': 'התחברת בהצלחה',
          'or': 'או התחבר באמצעות',
          'guest': 'המשך כאורח',
          'phone': 'התחבר עם טלפון',
        };
      case 'ar':
        return {
          'welcome': 'أهلاً\nبكم',
          'email': 'البريد الإلكتروني',
          'password': 'كلمة المرور',
          'forgot': 'نسيت كلمة المرور؟',
          'signin': 'تسجيل الدخول',
          'no_account': 'ليس لديك حساب؟ ',
          'signup': 'إنشاء حساب',
          'email_required': 'البريد الإلكتروني مطلوب',
          'valid_email': 'أدخل بريداً إلكترونياً صالحاً',
          'pass_required': 'كلمة المرور مطلوبة',
          'success': 'تم تسجيل الدخول بنجاح',
          'or': 'أو سجل الدخول عبر',
          'guest': 'الدخول كضيف',
          'phone': 'رقم الهاتف',
        };
      default:
        return {
          'welcome': 'Welcome\nBack',
          'email': 'Email',
          'password': 'Password',
          'forgot': 'Forgot Password?',
          'signin': 'Sign In',
          'no_account': "Don't have an account? ",
          'signup': 'Sign Up',
          'email_required': 'Email is required',
          'valid_email': 'Enter a valid email',
          'pass_required': 'Password is required',
          'success': 'Signed in successfully',
          'or': 'Or sign in with',
          'guest': 'Continue as Guest',
          'phone': 'Phone Number',
        };
    }
  }

  Future<void> _handleSocialSignIn(Future<User?> Function() signInMethod) async {
    setState(() => _loading = true);
    final user = await signInMethod();
    if (user != null && mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MyHomePage()));
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final strings = _getLocalizedStrings(context, listen: false);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      if (userCredential.user != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings['success']!)));
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MyHomePage()));
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Authentication failed')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final isRtl = Provider.of<LanguageProvider>(context).locale.languageCode == 'he' || 
                  Provider.of<LanguageProvider>(context).locale.languageCode == 'ar';
    
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(strings),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildEmailField(strings),
                      const SizedBox(height: 20),
                      _buildPasswordField(strings),
                      _buildForgotPassword(strings, isRtl),
                      const SizedBox(height: 32),
                      _buildSignInButton(strings),
                      const SizedBox(height: 24),
                      _buildSocialDivider(strings),
                      const SizedBox(height: 24),
                      _buildSocialButtons(),
                      const SizedBox(height: 24),
                      _buildGuestAndPhone(strings),
                      const SizedBox(height: 24),
                      _buildSignUpLink(strings),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Map<String, String> strings) {
    return Container(
      height: 250,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A8A), Color(0xFF1976D2)],
        ),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.handyman_rounded, size: 40, color: Colors.white),
            const SizedBox(height: 20),
            Text(strings['welcome']!, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, height: 1.1)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailField(Map<String, String> strings) {
    return TextFormField(
      controller: _emailCtrl,
      decoration: InputDecoration(
        labelText: strings['email'],
        prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF1976D2)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
      validator: (v) => (v == null || v.isEmpty) ? strings['email_required'] : null,
    );
  }

  Widget _buildPasswordField(Map<String, String> strings) {
    return TextFormField(
      controller: _passwordCtrl,
      obscureText: _obscure,
      decoration: InputDecoration(
        labelText: strings['password'],
        prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF1976D2)),
        suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscure = !_obscure)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
      validator: (v) => (v == null || v.isEmpty) ? strings['pass_required'] : null,
    );
  }

  Widget _buildForgotPassword(Map<String, String> strings, bool isRtl) {
    return Align(
      alignment: isRtl ? Alignment.centerLeft : Alignment.centerRight,
      child: TextButton(onPressed: () {}, child: Text(strings['forgot']!, style: const TextStyle(color: Color(0xFF64748B)))),
    );
  }

  Widget _buildSignInButton(Map<String, String> strings) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _loading ? null : _submit,
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1976D2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: _loading ? const CircularProgressIndicator(color: Colors.white) : Text(strings['signin']!, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSocialDivider(Map<String, String> strings) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(strings['or']!, style: const TextStyle(color: Colors.grey))),
        const Expanded(child: Divider()),
      ],
    );
  }

  Widget _buildSocialButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildSocialIcon('assets/icon/google.png', () => _handleSocialSignIn(_authService.signInWithGoogle)),
        _buildSocialIcon('assets/icon/facebook.png', () => _handleSocialSignIn(_authService.signInWithFacebook)),
        _buildSocialIcon('assets/icon/apple.png', () => _handleSocialSignIn(_authService.signInWithApple)),
      ],
    );
  }

  Widget _buildSocialIcon(String iconPath, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
        child: Image.asset(iconPath, height: 30, width: 30, errorBuilder: (c, e, s) => const Icon(Icons.login)),
      ),
    );
  }

  Widget _buildGuestAndPhone(Map<String, String> strings) {
    return Column(
      children: [
        TextButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PhoneAuthPage())),
          icon: const Icon(Icons.phone),
          label: Text(strings['phone']!),
        ),
        TextButton(
          onPressed: () => _handleSocialSignIn(_authService.signInAnonymously),
          child: Text(strings['guest']!, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildSignUpLink(Map<String, String> strings) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(strings['no_account']!),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpPage())),
          child: Text(strings['signup']!, style: const TextStyle(color: Color(0xFF1976D2), fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
