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
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/analytics_service.dart';
import 'package:untitled1/pages/subscription.dart';
import 'package:untitled1/map/map_radius_picker.dart';
import 'package:untitled1/map/location_picker.dart';
import 'package:untitled1/pages/privacy_policy_page.dart';
import 'package:untitled1/pages/terms_of_service_page.dart';
import 'package:untitled1/utils/profession_localization.dart';
import 'main.dart';

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
  final _dobController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _descriptionController = TextEditingController();

  TextEditingController? _professionsSearchController;

  late SignUpStep _currentStep;
  late UserType _userType;

  String? _selectedTown;
  List<String> _selectedProfessions = [];

  bool _loading = false;
  bool _autoCompletingFromPaidWorker = false;
  bool _agreedToPolicy = false;
  bool _codeSent = false;
  String _verificationId = "";
  File? _image;
  final ImagePicker _picker = ImagePicker();
  DateTime? _dateOfBirth;

  LatLng? _workCenter;
  double _workRadius = 5000.0;

  final List<String> _allProfessions =
      ProfessionLocalization.canonicalProfessions;

  @override
  void initState() {
    super.initState();
    _currentStep = widget.startAtStep == 1
        ? SignUpStep.phone
        : SignUpStep.profile;
    _image = widget.pendingWorkerImage;

    if (widget.pendingWorkerData != null) {
      _userType = UserType.worker;
      _nameController.text = widget.pendingWorkerData!['name'] ?? "";
      _emailController.text = widget.pendingWorkerData!['email'] ?? "";
      _selectedTown = widget.pendingWorkerData!['town'];
      _selectedProfessions = List<String>.from(
        widget.pendingWorkerData!['professions'] ?? [],
      ).map(ProfessionLocalization.toCanonical).toList();
      _altPhoneController.text =
          widget.pendingWorkerData!['optionalPhone'] ?? "";
      _descriptionController.text =
          widget.pendingWorkerData!['description'] ?? "";
      _dateOfBirth = _parseDateOfBirth(
        widget.pendingWorkerData!['dateOfBirth'],
      );
      if (_dateOfBirth != null) {
        _dobController.text = _formatDate(_dateOfBirth!);
      }
      _phoneController.text =
          widget.pendingWorkerData!['phone'] ??
          (FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
      _agreedToPolicy = true;
    } else {
      _userType = UserType.normal;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryFinalizePaidWorkerRegistrationAfterSubscription();
    });
  }

  Future<void> _tryFinalizePaidWorkerRegistrationAfterSubscription() async {
    if (_autoCompletingFromPaidWorker) return;
    if (widget.pendingWorkerData == null) return;
    if (widget.pendingWorkerData?['isSubscribed'] != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.phoneNumber == null || user.phoneNumber!.isEmpty) {
      return;
    }

    _autoCompletingFromPaidWorker = true;
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    await _commitUserDataToDatabase();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _altPhoneController.dispose();
    _descriptionController.dispose();
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
          'title': 'יצירת חשבון',
          'subtitle': 'הצטרף לקהילת הירו',
          'phone_label': 'מספר טלפון',
          'phone_subtitle': 'הכנס את מספר הטלפון שלך לאימות וסיום',
          'send_code': 'שלח קוד אימות',
          'verify_code': 'אמת וסיים הרשמה',
          'enter_code': 'הכנס קוד שקיבלת ב-SMS',
          'name_label': 'שם מלא',
          'email_label': 'אימייל (אופציונלי)',
          'dob_label': 'תאריך לידה',
          'dob_hint': 'בחר תאריך לידה',
          'dob_required': 'יש לבחור תאריך לידה',
          'town_label': 'עיר',
          'user_type': 'סוג חשבון',
          'normal': 'לקוח',
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
          'terms_content': 'תנאי השימוש...',
          'privacy_title': 'מדיניות פרטיות',
          'privacy_content': 'מדיניות פרטיות...',
          'close': 'סגור',
          'current_loc': 'מיקום נוכחי',
          'pick_map': 'בחר מהמפה',
          'work_radius': 'רדיוס עבודה',
          'radius_val': 'רדיוס: {val} ק"מ',
          'select_radius': 'בחר רדיוס על המפה',
          'edit_phone': 'ערוך מספר טלפון',
        };
      default:
        return {
          'title': 'Create Account',
          'subtitle': 'Join the Hiro community',
          'phone_label': 'Phone Number',
          'phone_subtitle': 'Enter your phone number to verify and complete',
          'send_code': 'Send Verification Code',
          'verify_code': 'Verify & Complete',
          'enter_code': 'Enter SMS Code',
          'name_label': 'Full Name',
          'email_label': 'Email (Optional)',
          'dob_label': 'Date of Birth',
          'dob_hint': 'Select date of birth',
          'dob_required': 'Date of birth is required',
          'town_label': 'City',
          'user_type': 'User Type',
          'normal': 'Client',
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
          'invalid_phone':
              'Please enter a valid Israeli phone number (05XXXXXXXX)',
          'error_verify': 'Error verifying code',
          'search_hint': 'Search...',
          'terms_title': 'Terms of Use',
          'terms_content': 'Terms of Use...',
          'privacy_title': 'Privacy Policy',
          'privacy_content': 'Privacy Policy...',
          'close': 'Close',
          'current_loc': 'Current Location',
          'pick_map': 'Select on Map',
          'work_radius': 'Work Radius',
          'radius_val': 'Radius: {val} km',
          'select_radius': 'Select radius on Map',
          'edit_phone': 'Edit Phone Number',
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

  DateTime? _parseDateOfBirth(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initial = _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );

    if (picked == null || !mounted) return;
    setState(() {
      _dateOfBirth = DateTime(picked.year, picked.month, picked.day);
      _dobController.text = _formatDate(_dateOfBirth!);
    });
  }

  Future<void> _handleSendCode() async {
    final strings = _getLocalizedStrings(context);
    String input = _phoneController.text.trim();
    if (input.isEmpty) return;

    String phone = _normalizePhone(input);
    final regExp = RegExp(r'^\+9725\d{8}$');

    if (!regExp.hasMatch(phone)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['invalid_phone']!)));
      return;
    }

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          await _onPhoneVerifiedAndSignedIn();
        },
        verificationFailed: (e) {
          if (mounted) {
            setState(() => _loading = false);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text("SMS failed: ${e.message}")));
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
          AnalyticsService.logSignUpCodeRequested(
            userType: _userType == UserType.worker ? 'worker' : 'customer',
          );
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
        ).showSnackBar(SnackBar(content: Text("Auth Error: $e")));
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
      await _onPhoneVerifiedAndSignedIn();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings['error_verify']!)));
      }
    }
  }

  Map<String, dynamic> _buildWorkerPendingDataWithPhone() {
    return {
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'dateOfBirth': _dateOfBirth != null
          ? Timestamp.fromDate(_dateOfBirth!)
          : null,
      'phone': _normalizePhone(_phoneController.text.trim()),
      'town': _selectedTown,
      'role': 'worker',
      'isSubscribed': false,
      'subscriptionStatus': 'inactive',
      'subscriptionCanceled': false,
      'professions': _selectedProfessions,
      'optionalPhone': _altPhoneController.text.trim(),
      'description': _descriptionController.text.trim(),
      'workRadius': _workRadius,
      'workCenterLat': _workCenter?.latitude,
      'workCenterLng': _workCenter?.longitude,
      'avgRating': 0.0,
      'reviewCount': 0,
    };
  }

  Future<void> _onPhoneVerifiedAndSignedIn() async {
    if (_userType == UserType.worker &&
        widget.pendingWorkerData?['isSubscribed'] != true) {
      // Persist all entered data immediately after phone verification,
      // then continue the Pro subscription step.
      await _commitUserDataToDatabase(navigateToHome: false);
      final workerPendingData = _buildWorkerPendingDataWithPhone();
      if (mounted) {
        setState(() {
          _loading = false;
          _codeSent = false;
        });
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
      }
      return;
    }

    await _commitUserDataToDatabase();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _loading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Location services are disabled.';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied)
          throw 'Location permissions are denied';
      }

      if (permission == LocationPermission.deniedForever)
        throw 'Location permissions are permanently denied.';

      Position position = await Geolocator.getCurrentPosition();
      LatLng loc = LatLng(position.latitude, position.longitude);
      setState(() => _workCenter = loc);
      await _updateTownFromLocation(loc);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateTownFromLocation(LatLng loc) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        loc.latitude,
        loc.longitude,
      );
      if (placemarks.isNotEmpty) {
        String? town =
            placemarks.first.locality ?? placemarks.first.subLocality;
        if (town != null && town.isNotEmpty) {
          setState(() => _selectedTown = town);
        }
      }
    } catch (e) {
      debugPrint("Reverse geocoding error: $e");
    }
  }

  Future<void> _commitUserDataToDatabase({bool navigateToHome = true}) async {
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
          final ref = FirebaseStorage.instance.ref().child(
            'profile_pictures/${user.uid}.jpg',
          );
          await ref.putFile(_image!).timeout(const Duration(seconds: 15));
          imageUrl = await ref.getDownloadURL();
        } catch (e) {
          debugPrint("STORAGE ERROR: $e");
        }
      }

      double? lat = _workCenter?.latitude;
      double? lng = _workCenter?.longitude;
      if (lat == null && _selectedTown != null) {
        try {
          List<Location> locations = await locationFromAddress(
            "$_selectedTown, Israel",
          );
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
        'dateOfBirth': _dateOfBirth != null
            ? Timestamp.fromDate(_dateOfBirth!)
            : null,
        'phone': _normalizePhone(_phoneController.text.trim()),
        'town': _selectedTown,
        'lat': lat,
        'lng': lng,
        'profileImageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'role': _userType == UserType.worker ? 'worker' : 'customer',
      };

      if (_userType == UserType.worker) {
        final bool hasActiveSubscriptionFromPending =
            widget.pendingWorkerData?['isSubscribed'] == true;
        final DateTime now = DateTime.now();
        final DateTime defaultExpiry = now.add(const Duration(days: 30));
        final DateTime? pendingDate = DateTime.tryParse(
          widget.pendingWorkerData?['subscriptionDate']?.toString() ?? '',
        );
        final DateTime? pendingExpiry = DateTime.tryParse(
          widget.pendingWorkerData?['subscriptionExpiresAt']?.toString() ?? '',
        );

        userData.addAll({
          'professions': _selectedProfessions,
          'optionalPhone': _altPhoneController.text.trim(),
          'description': _descriptionController.text.trim(),
          'isSubscribed': hasActiveSubscriptionFromPending,
          'subscriptionStatus': hasActiveSubscriptionFromPending
              ? 'active'
              : 'inactive',
          'subscriptionCanceled': false,
          'subscriptionProductId':
              widget.pendingWorkerData?['subscriptionProductId'],
          'subscriptionPlatform':
              widget.pendingWorkerData?['subscriptionPlatform'],
          'subscriptionPurchaseId':
              widget.pendingWorkerData?['subscriptionPurchaseId'],
          'subscriptionTransactionDate':
              widget.pendingWorkerData?['subscriptionTransactionDate'],
          'workRadius': _workRadius,
          'workCenterLat': _workCenter?.latitude,
          'workCenterLng': _workCenter?.longitude,
          'subscriptionDate': hasActiveSubscriptionFromPending
              ? Timestamp.fromDate(pendingDate ?? now)
              : null,
          'subscriptionExpiresAt': hasActiveSubscriptionFromPending
              ? Timestamp.fromDate(pendingExpiry ?? defaultExpiry)
              : null,
          'avgRating': 0.0,
          'reviewCount': 0,
        });
      }

      await firestore.collection('users').doc(user.uid).set(userData);
      await user.updateDisplayName(finalName);

      await AnalyticsService.logSignUpCompleted(
        userType: _userType == UserType.worker ? 'worker' : 'customer',
        hasEmail: _emailController.text.trim().isNotEmpty,
      );

      if (_userType == UserType.worker) {
        try {
          await firestore.collection('metadata').doc('stats').set({
            'totalWorkers': FieldValue.increment(1),
          }, SetOptions(merge: true));
        } catch (_) {}
      }

      if (mounted && navigateToHome) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MyHomePage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Database Error: $e")));
      }
    }
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked != null) setState(() => _image = File(picked.path));
  }

  void _submitProfile() {
    if (!_formKey.currentState!.validate()) return;
    final strings = _getLocalizedStrings(context);

    if (_selectedTown == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['town_label']!)));
      return;
    }

    if (_userType == UserType.worker && _selectedProfessions.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['professions']!)));
      return;
    }

    if (!_agreedToPolicy) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['policy_err']!)));
      return;
    }

    if (_userType == UserType.worker) {
      setState(() {
        _currentStep = SignUpStep.phone;
      });
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
        backgroundColor: Colors.grey[50],
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _buildCurrentStep(isRtl),
      ),
    );
  }

  Widget _buildCurrentStep(bool isRtl) {
    final strings = _getLocalizedStrings(context);
    return SingleChildScrollView(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _currentStep == SignUpStep.profile
            ? _buildProfileStep(strings, isRtl)
            : _buildPhoneStep(strings, isRtl),
      ),
    );
  }

  Widget _buildPhoneStep(Map<String, String> strings, bool isRtl) {
    return Column(
      key: const ValueKey('phone'),
      children: [
        _buildHeader(
          strings['phone_label']!,
          strings['phone_subtitle']!,
          isRtl,
          showBack: widget.pendingWorkerData == null,
        ),
        Transform.translate(
          offset: const Offset(0, -40),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
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
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _loading
                        ? null
                        : (_codeSent ? _handleVerifyCode : _handleSendCode),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _codeSent
                          ? strings['verify_code']!
                          : strings['send_code']!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (_codeSent)
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _codeSent = false),
                      child: Text(
                        strings['edit_phone']!,
                        style: const TextStyle(
                          color: Color(0xFF1976D2),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    String title,
    String subtitle,
    bool isRtl, {
    bool showBack = false,
  }) {
    return Container(
      height: 300,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -50,
            right: isRtl ? null : -50,
            left: isRtl ? -50 : null,
            child: CircleAvatar(
              radius: 100,
              backgroundColor: Colors.white.withOpacity(0.1),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showBack)
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _currentStep = SignUpStep.profile),
                    ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      showBack
                          ? Icons.phone_android_rounded
                          : Icons.person_add_rounded,
                      size: 36,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileStep(Map<String, String> strings, bool isRtl) {
    return Column(
      key: const ValueKey('profile'),
      children: [
        _buildHeader(strings['title']!, strings['subtitle']!, isRtl),
        Transform.translate(
          offset: const Offset(0, -40),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildImagePicker(),
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
                  _buildStyledTextField(
                    controller: _dobController,
                    labelText: strings['dob_label']!,
                    hintText: strings['dob_hint']!,
                    icon: Icons.cake_outlined,
                    readOnly: true,
                    onTap: _pickDateOfBirth,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? strings['dob_required']
                        : null,
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
                  _buildPolicyCheckbox(strings),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _submitProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _userType == UserType.worker
                            ? strings['pay']!
                            : strings['finish']!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF1976D2).withOpacity(0.2),
                width: 2,
              ),
            ),
            child: CircleAvatar(
              radius: 55,
              backgroundColor: Colors.grey[100],
              backgroundImage: _image != null ? FileImage(_image!) : null,
              child: _image == null
                  ? Icon(
                      Icons.person_rounded,
                      size: 50,
                      color: Colors.grey[400],
                    )
                  : null,
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF1976D2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyCheckbox(Map<String, String> strings) {
    return Row(
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: _agreedToPolicy,
            onChanged: (v) => setState(() => _agreedToPolicy = v!),
            activeColor: const Color(0xFF1976D2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              children: [
                TextSpan(text: strings['agree_prefix']!),
                TextSpan(
                  text: strings['terms_link']!,
                  style: const TextStyle(
                    color: Color(0xFF1976D2),
                    fontWeight: FontWeight.bold,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TermsOfServicePage(),
                        ),
                      );
                    },
                ),
                TextSpan(text: strings['and']!),
                TextSpan(
                  text: strings['privacy_link']!,
                  style: const TextStyle(
                    color: Color(0xFF1976D2),
                    fontWeight: FontWeight.bold,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PrivacyPolicyPage(),
                        ),
                      );
                    },
                ),
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
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _getCurrentLocation,
                icon: const Icon(Icons.my_location, size: 16),
                label: Text(
                  strings['current_loc']!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(
                    color: const Color(0xFF1976D2).withOpacity(0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openMapPicker,
                icon: const Icon(Icons.map_outlined, size: 16),
                label: Text(
                  strings['pick_map']!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(
                    color: const Color(0xFF1976D2).withOpacity(0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
        builder: (context) => LocationPicker(initialCenter: _workCenter),
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
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.radar_rounded,
                color: Color(0xFF1976D2),
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                strings['work_radius']!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                strings['radius_val']!.replaceFirst(
                  '{val}',
                  (_workRadius / 1000).toStringAsFixed(1),
                ),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1976D2),
                ),
              ),
              TextButton.icon(
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
                    if (_workCenter != null)
                      _updateTownFromLocation(_workCenter!);
                  }
                },
                icon: const Icon(Icons.edit_location_alt_rounded, size: 18),
                label: Text(strings['select_radius']!),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMultiSelectProfessions(Map<String, String> strings) {
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;
    final localizedOptions = _allProfessions
        .map((p) => ProfessionLocalization.toLocalized(p, localeCode))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) return localizedOptions;
              return localizedOptions.where(
                (option) => option.toLowerCase().contains(
                  textEditingValue.text.toLowerCase(),
                ),
              );
            },
            onSelected: (selection) {
              final canonical = ProfessionLocalization.toCanonical(selection);
              setState(() {
                if (!_selectedProfessions.contains(canonical)) {
                  _selectedProfessions.add(canonical);
                }
              });
              _professionsSearchController?.clear();
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: constraints.maxWidth,
                    constraints: const BoxConstraints(maxHeight: 250),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          title: Text(
                            option,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
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
            runSpacing: 8,
            children: _selectedProfessions
                .map(
                  (prof) => Chip(
                    label: Text(
                      ProfessionLocalization.toLocalized(prof, localeCode),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    backgroundColor: const Color(0xFF1976D2).withOpacity(0.1),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () =>
                        setState(() => _selectedProfessions.remove(prof)),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildTypeSelector(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings['user_type']!,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildTypeButton(strings['normal']!, UserType.normal),
              ),
              Expanded(
                child: _buildTypeButton(strings['pro']!, UserType.worker),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeButton(String label, UserType type) {
    final isSelected = _userType == type;
    return GestureDetector(
      onTap: () => setState(() => _userType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? const Color(0xFF1976D2) : Colors.grey[600],
            fontWeight: FontWeight.bold,
          ),
        ),
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
    TextAlign textAlign = TextAlign.start,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          enabled: enabled,
          readOnly: readOnly,
          onTap: onTap,
          focusNode: focusNode,
          textAlign: textAlign,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(icon, color: const Color(0xFF1976D2), size: 20),
            filled: true,
            fillColor: enabled ? Colors.grey[100] : Colors.grey[200],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}
