import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/subscription.dart';
import 'package:untitled1/pages/map_radius_picker.dart';
import 'package:untitled1/pages/location_picker.dart';
import '../main.dart';

class SignUpPage extends StatefulWidget {
  final Map<String, dynamic>? pendingWorkerData;
  final File? pendingWorkerImage;
  final int startAtStep;

  const SignUpPage({
    super.key,
    this.pendingWorkerData,
    this.pendingWorkerImage,
    this.startAtStep = 0,
  });

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

enum SignUpStep { profile, phone }
enum UserType { normal, worker }

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  // Controller to clear the professions search bar after selection
  TextEditingController? _professionsSearchController;

  late SignUpStep _currentStep;
  late UserType _userType;
  
  String? _selectedTown;
  List<String> _selectedProfessions = [];
  
  bool _loading = false;
  bool _agreedToPolicy = false;
  bool _codeSent = false;
  String _verificationId = "";
  File? _image;
  final ImagePicker _picker = ImagePicker();
  
  LatLng? _workCenter;
  double _workRadius = 5000.0;

  final List<String> _allProfessions = [
    'Plumber', 'Carpenter', 'Electrician', 'Painter', 'Cleaner', 'Handyman',
    'Landscaper', 'HVAC', 'Locksmith', 'Gardener', 'Mechanic', 'Photographer',
    'Tutor', 'Tailor', 'Mover', 'Interior Designer', 'Beautician', 'Pet Groomer',
    'Welder', 'Roofer', 'Flooring Expert', 'AC Technician', 'Pest Control'
  ];

  @override
  void initState() {
    super.initState();
    _currentStep = widget.startAtStep == 1 ? SignUpStep.phone : SignUpStep.profile;
    _image = widget.pendingWorkerImage;
    
    if (widget.pendingWorkerData != null) {
      _userType = UserType.worker;
      _nameController.text = widget.pendingWorkerData!['name'] ?? "";
      _emailController.text = widget.pendingWorkerData!['email'] ?? "";
      _selectedTown = widget.pendingWorkerData!['town'];
      _selectedProfessions = List<String>.from(widget.pendingWorkerData!['professions'] ?? []);
      _altPhoneController.text = widget.pendingWorkerData!['optionalPhone'] ?? "";
      _descriptionController.text = widget.pendingWorkerData!['description'] ?? "";
      _agreedToPolicy = true; 
    } else {
      _userType = UserType.normal;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _altPhoneController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context, listen: false).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'הרשמה',
          'phone_label': 'מספר טלפון',
          'phone_subtitle': 'הכנס את מספר הטלפון שלך לאימות וסיום',
          'send_code': 'שלח קוד אימות',
          'verify_code': 'אמת וסיים הרשמה',
          'enter_code': 'הכנס קוד שקיבלת ב-SMS',
          'name_label': 'שם מלא',
          'email_label': 'אימייל (אופציונלי)',
          'town_label': 'עיר',
          'user_type': 'סוג חשבון',
          'normal': 'משתמש רגיל',
          'pro': 'בעל מקצוע',
          'professions': 'בחר מקצועות',
          'alt_phone': 'טלפון נוסף (אופציונלי)',
          'desc_label': 'ספר על עצמך (אופציונלי)',
          'agree_prefix': 'אני מסכים ל-',
          'and': ' ו-',
          'terms_link': 'תנאי השימוש',
          'privacy_link': 'מדיניות הפרטיות',
          'finish': 'המשך לאימות טלפון',
          'pay': 'המשך לתשלום מנוי',
          'req': 'שדה חובה',
          'policy_err': 'עליך להסכים לתנאים',
          'invalid_phone': 'אנא הכנס מספר טלפון ישראלי תקין (05XXXXXXXX)',
          'error_verify': 'שגיאה באימות הקוד',
          'search_hint': 'חפש...',
          'terms_title': 'תנאי שימוש',
          'terms_content': 'תנאי השימוש:\n\n1. השירות: האפליקציה משמשת כפלטפורמה המקשרת בין משתמשים לבעלי מקצוע. המפעיל אינו צד בעסקה ואינו מספק את השירותים בעצמו.\n2. אחריות: המפעיל אינו אחראי לטיב העבודה, ללוחות הזמנים, למחיר או לכל נזק שייגרם כתוצאה מההתקשרות בין הצדדים.\n3. התנהגות משתמש: הנך מתחייב לספק מידע אמיתי ומדויק. חל איסור על שימוש לרעה במערכת או פרסום תוכן פוגעני.\n4. קניין רוחני: כל הזכויות באפליקציה שמורות למפעיליה.\n5. שינוי תנאים: המפעיל רשאי לעדכן את תנאי השימוש בכל עת.',
          'privacy_title': 'מדיניות פרטיות',
          'privacy_content': 'מדיניות פרטיות:\n\n1. איסוף מידע: אנו אוספים פרטי זיהוי (שם, טלפון, אימייל) ונתוני מיקום לצורך תפעול ושיפור השירות.\n2. שימוש במידע: המידע משמש לחיבור בין משתמשים, ניהול חשבונות ושליחת עדכונים רלוונטיים.\n3. שיתוף מידע: פרטי הקשר של בעלי מקצוע מוצגים למשתמשים לצורך התקשרות עסקית בלבד. איננו מוכרים מידע לצד ג\'.\n4. אבטחה: המידע נשמר בטכנולוגיות ענן מאובטחות בתקנים מחמירים.\n5. זכויותיך: הנך רשאי לבקש לעיין במידע, לתקנו או למחוק את חשבונך בכל עת דרך הגדרות האפליקציה.',
          'close': 'סגור',
          'current_loc': 'השתמש במיקום נוכחי',
          'pick_map': 'בחר מהמפה',
          'work_radius': 'רדיוס עבודה',
          'radius_val': 'רדיוס: {val} ק"מ',
          'select_radius': 'בחר רדיוס על המפה',
        };
      default:
        return {
          'title': 'Sign Up',
          'phone_label': 'Phone Number',
          'phone_subtitle': 'Enter your phone number to verify and complete',
          'send_code': 'Send Verification Code',
          'verify_code': 'Verify & Complete',
          'enter_code': 'Enter SMS Code',
          'name_label': 'Full Name',
          'email_label': 'Email (Optional)',
          'town_label': 'City',
          'user_type': 'User Type',
          'normal': 'Normal User',
          'pro': 'Professional',
          'professions': 'Select Professions',
          'alt_phone': 'Alt Phone (Optional)',
          'desc_label': 'Description (Optional)',
          'agree_prefix': 'I agree to the ',
          'and': ' and ',
          'terms_link': 'Terms of Use',
          'privacy_link': 'Privacy Policy',
          'finish': 'Continue to Phone Verification',
          'pay': 'Proceed to Subscription',
          'req': 'Required',
          'policy_err': 'You must agree to the terms',
          'invalid_phone': 'Please enter a valid Israeli phone number (05XXXXXXXX)',
          'error_verify': 'Error verifying code',
          'search_hint': 'Search...',
          'terms_title': 'Terms of Use',
          'terms_content': 'Terms of Use:\n\n1. Service: This app is a platform connecting users with service professionals. We are not a party to the actual contract between users.\n2. Liability: We are not responsible for the quality, legality, or any outcome of the services provided by professionals.\n3. User Conduct: You must provide accurate information and use the app in a lawful and respectful manner.\n4. Intellectual Property: All content and software are owned by the app operators.\n5. Modifications: We reserve the right to update these terms at any time without prior notice.',
          'privacy_title': 'Privacy Policy',
          'privacy_content': 'Privacy Policy:\n\n1. Data Collection: We collect name, phone number, email, and location data to facilitate our services.\n2. Data Usage: Your information is used to enable connections, manage accounts, and improve user experience.\n3. Data Sharing: Professional contact details are visible to users to enable business transactions. We do not sell your data.\n4. Security: We employ industry-standard security measures to protect your personal information.\n5. Your Rights: You can access, update, or request the deletion of your account and personal data at any time via the app settings.',
          'close': 'Close',
          'current_loc': 'Use Current Location',
          'pick_map': 'Select on Map',
          'work_radius': 'Work Radius',
          'radius_val': 'Radius: {val} km',
          'select_radius': 'Select radius on Map',
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

  Future<void> _handleSendCode() async {
    final strings = _getLocalizedStrings(context);
    String input = _phoneController.text.trim();
    if (input.isEmpty) return;

    String phone = _normalizePhone(input);
    final regExp = RegExp(r'^\+9725\d{8}$');
    
    if (!regExp.hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings['invalid_phone']!)));
      return;
    }

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          await _commitUserDataToDatabase();
        },
        verificationFailed: (e) {
          if (mounted) {
            setState(() => _loading = false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("SMS failed: ${e.message}")));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Auth Error: $e")));
      }
    }
  }

  Future<void> _handleVerifyCode() async {
    final strings = _getLocalizedStrings(context);
    if (_codeController.text.trim().isEmpty) return;

    setState(() => _loading = true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: _codeController.text.trim(),
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      await _commitUserDataToDatabase();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings['error_verify']!)));
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _loading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Location services are disabled.';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw 'Location permissions are denied';
      }
      
      if (permission == LocationPermission.deniedForever) throw 'Location permissions are permanently denied.';

      Position position = await Geolocator.getCurrentPosition();
      LatLng loc = LatLng(position.latitude, position.longitude);
      setState(() => _workCenter = loc);
      await _updateTownFromLocation(loc);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateTownFromLocation(LatLng loc) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(loc.latitude, loc.longitude);
      if (placemarks.isNotEmpty) {
        String? town = placemarks.first.locality ?? placemarks.first.subLocality;
        if (town != null && town.isNotEmpty) {
          setState(() => _selectedTown = town);
        }
      }
    } catch (e) {
      debugPrint("Reverse geocoding error: $e");
    }
  }

  Future<void> _commitUserDataToDatabase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      final firestore = FirebaseFirestore.instance;
      String imageUrl = "";
      String finalName = _nameController.text.trim();

      if (_image != null) {
        try {
          final ref = FirebaseStorage.instance.ref().child('profile_pictures/${user.uid}.jpg');
          await ref.putFile(_image!).timeout(const Duration(seconds: 15));
          imageUrl = await ref.getDownloadURL();
        } catch (e) {
          debugPrint("STORAGE ERROR: $e");
        }
      }

      // Geocode town if center not set
      double? lat = _workCenter?.latitude;
      double? lng = _workCenter?.longitude;
      if (lat == null && _selectedTown != null) {
        try {
          List<Location> locations = await locationFromAddress("$_selectedTown, Israel");
          if (locations.isNotEmpty) {
            lat = locations.first.latitude;
            lng = locations.first.longitude;
          }
        } catch (_) {}
      }

      final userData = {
        'uid': user.uid,
        'name': finalName,
        'email': _emailController.text.trim(),
        'phone': _normalizePhone(_phoneController.text.trim()),
        'town': _selectedTown,
        'lat': lat,
        'lng': lng,
        'userType': _userType == UserType.worker ? 'worker' : 'normal',
        'profileImageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'isAnonymous': user.isAnonymous,
      };

      if (_userType == UserType.worker) {
        userData.addAll({
          'professions': _selectedProfessions,
          'optionalPhone': _altPhoneController.text.trim(),
          'description': _descriptionController.text.trim(),
          'isSubscribed': true,
          'isPro': true,
          'workRadius': _workRadius,
          'workCenterLat': _workCenter?.latitude,
          'workCenterLng': _workCenter?.longitude,
          'subscriptionDate': FieldValue.serverTimestamp(),
        });
      }

      await firestore.collection('users').doc(user.uid).set(userData);
      await user.updateDisplayName(finalName);
      
      if (_userType == UserType.worker) {
        try {
          await firestore.collection('metadata').doc('stats').set({
            'totalWorkers': FieldValue.increment(1)
          }, SetOptions(merge: true));
        } catch (_) {} 
      }

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MyHomePage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Database Error: $e"),
        ));
      }
    }
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) setState(() => _image = File(picked.path));
  }

  void _showPolicyDialog(String title, String content) {
    final strings = _getLocalizedStrings(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
        content: SingleChildScrollView(
          child: Text(
            content,
            style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings['close']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1976D2))),
          ),
        ],
      ),
    );
  }

  void _submitProfile() {
    if (!_formKey.currentState!.validate()) return;
    final strings = _getLocalizedStrings(context);
    
    if (_selectedTown == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings['town_label']!)));
      return;
    }

    if (_userType == UserType.worker && _selectedProfessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings['professions']!)));
      return;
    }

    if (!_agreedToPolicy) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings['policy_err']!)));
      return;
    }

    if (_userType == UserType.worker) {
      final workerPendingData = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'town': _selectedTown,
        'userType': 'worker',
        'professions': _selectedProfessions,
        'optionalPhone': _altPhoneController.text.trim(),
        'description': _descriptionController.text.trim(),
        'workRadius': _workRadius,
        'workCenterLat': _workCenter?.latitude,
        'workCenterLng': _workCenter?.longitude,
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SubscriptionPage(
            email: _emailController.text.trim(),
            pendingUserData: workerPendingData,
            pendingImage: _image,
            isNewRegistration: true,
          ),
        ),
      );
    } else {
      setState(() => _currentStep = SignUpStep.phone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _buildCurrentStep(),
      ),
    );
  }

  Widget _buildCurrentStep() {
    final strings = _getLocalizedStrings(context);
    return SingleChildScrollView(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _currentStep == SignUpStep.profile 
            ? _buildProfileStep(strings) 
            : _buildPhoneStep(strings),
      ),
    );
  }

  Widget _buildPhoneStep(Map<String, String> strings) {
    return Column(
      key: const ValueKey('phone'),
      children: [
        Container(
          height: 300,
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
                if (widget.pendingWorkerData == null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => setState(() => _currentStep = SignUpStep.profile),
                  ),
                const Icon(Icons.phone_android_rounded, size: 50, color: Colors.white),
                const SizedBox(height: 24),
                Text(
                  strings['phone_label']!,
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings['phone_subtitle']!,
                style: const TextStyle(fontSize: 16, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 40),
              _buildStyledTextField(
                controller: _phoneController,
                labelText: strings['phone_label']!,
                icon: Icons.phone_android_rounded,
                keyboardType: TextInputType.phone,
                hintText: 'e.g. 0501234567',
                enabled: !_codeSent,
              ),
              if (_codeSent) ...[
                const SizedBox(height: 16),
                _buildStyledTextField(
                  controller: _codeController,
                  labelText: strings['enter_code']!,
                  icon: Icons.lock_outline_rounded,
                  keyboardType: TextInputType.number,
                ),
              ],
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: _loading ? null : (_codeSent ? _handleVerifyCode : _handleSendCode),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_codeSent ? strings['verify_code']! : strings['send_code']!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 22),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileStep(Map<String, String> strings) {
    return Column(
      key: const ValueKey('profile'),
      children: [
        Container(
          height: 200,
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF1E3A8A), Color(0xFF1976D2)]),
            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(80)),
          ),
          child: Center(
            child: Text(
              strings['title']!,
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: const Color(0xFFF1F5F9),
                    backgroundImage: _image != null ? FileImage(_image!) : null,
                    child: _image == null
                        ? Icon(Icons.person_rounded, size: 60, color: Colors.grey[400])
                        : null,
                  ),
                ),
                const SizedBox(height: 32),
                _buildStyledTextField(
                  controller: _nameController,
                  labelText: strings['name_label']!,
                  icon: Icons.person_outline,
                  validator: (v) => v!.isEmpty ? strings['req'] : null,
                ),
                const SizedBox(height: 16),
                _buildStyledTextField(
                  controller: _emailController,
                  labelText: strings['email_label']!,
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                
                _buildLocationSelectionSection(strings),

                const SizedBox(height: 24),
                _buildTypeSelector(strings),

                if (_userType == UserType.worker) ...[
                  const SizedBox(height: 24),
                  _buildWorkRadiusSelector(strings),
                  const SizedBox(height: 24),
                  _buildMultiSelectProfessions(strings),
                  const SizedBox(height: 16),
                  _buildStyledTextField(
                    controller: _altPhoneController,
                    labelText: strings['alt_phone']!,
                    icon: Icons.phone_android_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  _buildStyledTextField(
                    controller: _descriptionController,
                    labelText: strings['desc_label']!,
                    icon: Icons.description_outlined,
                    maxLines: 3,
                  ),
                ],

                const SizedBox(height: 24),
                Row(
                  children: [
                    Checkbox(
                      value: _agreedToPolicy,
                      onChanged: (v) => setState(() => _agreedToPolicy = v!),
                      activeColor: const Color(0xFF1976D2),
                    ),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          children: [
                            TextSpan(text: strings['agree_prefix']!),
                            TextSpan(
                              text: strings['terms_link']!,
                              style: const TextStyle(color: Color(0xFF1976D2), decoration: TextDecoration.underline, fontWeight: FontWeight.bold),
                              recognizer: TapGestureRecognizer()..onTap = () => _showPolicyDialog(strings['terms_title']!, strings['terms_content']!),
                            ),
                            TextSpan(text: strings['and']!),
                            TextSpan(
                              text: strings['privacy_link']!,
                              style: const TextStyle(color: Color(0xFF1976D2), decoration: TextDecoration.underline, fontWeight: FontWeight.bold),
                              recognizer: TapGestureRecognizer()..onTap = () => _showPolicyDialog(strings['privacy_title']!, strings['privacy_content']!),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _submitProfile,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1976D2), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: Text(_userType == UserType.worker ? strings['pay']! : strings['finish']!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationSelectionSection(Map<String, String> strings) {
    final townController = TextEditingController(text: _selectedTown ?? '');
    return Column(
      children: [
        _buildStyledTextField(
          controller: townController,
          labelText: strings['town_label']!,
          icon: Icons.location_on_outlined,
          readOnly: true,
          onTap: _openMapPicker,
          validator: (v) => (v == null || v.isEmpty) ? strings['req'] : null,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _getCurrentLocation,
                icon: const Icon(Icons.my_location, size: 18),
                label: Text(strings['current_loc']!, style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Color(0xFF1976D2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openMapPicker,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: Text(strings['pick_map']!, style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Color(0xFF1976D2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openMapPicker() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPicker(
          initialCenter: _workCenter,
        ),
      ),
    );
    if (result != null && result is LatLng) {
      setState(() {
        _workCenter = result;
      });
      _updateTownFromLocation(result);
    }
  }

  Widget _buildWorkRadiusSelector(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map_outlined, color: Color(0xFF1976D2)),
              const SizedBox(width: 12),
              Text(strings['work_radius']!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                strings['radius_val']!.replaceFirst('{val}', (_workRadius / 1000).toStringAsFixed(1)),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MapRadiusPicker(
                        initialCenter: _workCenter,
                        initialRadius: _workRadius,
                      ),
                    ),
                  );
                  if (result != null) {
                    setState(() {
                      _workCenter = result['center'];
                      _workRadius = result['radius'];
                    });
                    if (_workCenter != null) _updateTownFromLocation(_workCenter!);
                  }
                },
                icon: const Icon(Icons.my_location, size: 18),
                label: Text(strings['select_radius']!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMultiSelectProfessions(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return _allProfessions;
              }
              return _allProfessions.where((String option) {
                return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
              });
            },
            onSelected: (String selection) {
              setState(() {
                if (!_selectedProfessions.contains(selection)) {
                  _selectedProfessions.add(selection);
                }
              });
              _professionsSearchController?.clear();
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: 250,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8.0),
                      itemCount: options.length,
                      itemBuilder: (BuildContext context, int index) {
                        final String option = options.elementAt(index);
                        return ListTile(
                          title: Text(option),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              _professionsSearchController = controller;
              return _buildStyledTextField(
                controller: controller,
                labelText: strings['professions']!,
                icon: Icons.work_outline,
                focusNode: focusNode,
                hintText: strings['search_hint'],
              );
            },
          ),
        ),
        if (_selectedProfessions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _selectedProfessions.map((prof) => Chip(
              label: Text(prof),
              onDeleted: () {
                setState(() {
                  _selectedProfessions.remove(prof);
                });
              },
            )).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildTypeSelector(Map<String, String> strings) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(child: _buildTypeButton(strings['normal']!, UserType.normal)),
          Expanded(child: _buildTypeButton(strings['pro']!, UserType.worker)),
        ],
      ),
    );
  }

  Widget _buildTypeButton(String label, UserType type) {
    final isSelected = _userType == type;
    return GestureDetector(
      onTap: () => setState(() => _userType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1976D2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF64748B), fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    String? hintText,
    bool enabled = true,
    bool readOnly = false,
    VoidCallback? onTap,
    FocusNode? focusNode,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: enabled,
      readOnly: readOnly,
      onTap: onTap,
      focusNode: focusNode,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: Icon(icon, color: const Color(0xFF1976D2)),
        filled: true,
        fillColor: enabled ? const Color(0xFFF8FAFC) : const Color(0xFFE2E8F0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: validator,
    );
  }
}
