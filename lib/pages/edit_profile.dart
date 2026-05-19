import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/map/map_radius_picker.dart';
import 'package:untitled1/map/location_picker.dart';
import 'package:untitled1/utils/profession_localization.dart';

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> userData;
  const EditProfilePage({super.key, required this.userData});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage>
    with TickerProviderStateMixin {
  static const List<String> _spokenLanguageOptions = [
    'Hebrew',
    'Arabic',
    'English',
    'Russian',
    'Amharic',
  ];
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _altPhoneController;
  late TextEditingController _descriptionController;
  late TextEditingController _townController;
  TextEditingController? _professionsSearchController;

  String? _selectedTown;
  List<String> _selectedProfessions = [];
  List<String> _selectedSpokenLanguages = [];
  List<Map<String, dynamic>> _professionItems = [];
  File? _image;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  double _workRadius = 25000.0;
  LatLng? _workCenter;
  AnimationController? _introController;
  AnimationController? _backgroundController;

  @override
  void initState() {
    super.initState();
    _ensureAnimationControllers();
    _nameController = TextEditingController(text: widget.userData['name']);
    _emailController = TextEditingController(text: widget.userData['email']);
    _phoneController = TextEditingController(text: widget.userData['phone']);
    _altPhoneController = TextEditingController(
      text: widget.userData['optionalPhone'],
    );
    _descriptionController = TextEditingController(
      text: widget.userData['description'] ?? widget.userData['bio'],
    );
    _selectedTown = widget.userData['town'];
    _townController = TextEditingController(text: _selectedTown);
    _selectedProfessions = List<String>.from(
      widget.userData['professions'] ?? [],
    ).map(ProfessionLocalization.toCanonical).toList();
    _selectedSpokenLanguages = List<String>.from(
      widget.userData['spokenLanguages'] ?? [],
    ).where(_spokenLanguageOptions.contains).toList();
    _loadProfessionItems();

    _workRadius = (widget.userData['workRadius'] ?? 25000.0).toDouble();
    if (widget.userData['workCenterLat'] != null &&
        widget.userData['workCenterLng'] != null) {
      _workCenter = LatLng(
        widget.userData['workCenterLat'],
        widget.userData['workCenterLng'],
      );
    } else if (widget.userData['lat'] != null &&
        widget.userData['lng'] != null) {
      _workCenter = LatLng(widget.userData['lat'], widget.userData['lng']);
    }
  }

  Future<void> _loadProfessionItems() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('metadata')
          .doc('professions')
          .get();
      final data = snapshot.data();
      final rawItems = data?['items'];
      if (rawItems is! List) return;

      final items =
          rawItems
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((item) => _professionCanonicalValue(item).isNotEmpty)
              .toList()
            ..sort((a, b) {
              final aId = (a['id'] as num?)?.toInt() ?? 1 << 30;
              final bId = (b['id'] as num?)?.toInt() ?? 1 << 30;
              if (aId != bId) return aId.compareTo(bId);
              return _professionCanonicalValue(
                a,
              ).compareTo(_professionCanonicalValue(b));
            });

      if (!mounted) return;
      setState(() {
        _professionItems = items;
        _selectedProfessions = _selectedProfessions
            .map(_normalizeStoredProfession)
            .where((profession) => profession.isNotEmpty)
            .toSet()
            .toList();
      });
    } catch (e) {
      debugPrint('Failed to load profession metadata: $e');
    }
  }

  String _professionCanonicalValue(Map<String, dynamic> item) {
    final english = item['en']?.toString().trim();
    if (english != null && english.isNotEmpty) return english;

    for (final key in const ['he', 'ar', 'ru', 'am']) {
      final value = item[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  Map<String, dynamic>? _findProfessionItem(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    for (final item in _professionItems) {
      for (final key in const ['en', 'he', 'ar', 'ru', 'am']) {
        final candidate = item[key]?.toString().trim().toLowerCase();
        if (candidate != null &&
            candidate.isNotEmpty &&
            candidate == normalized) {
          return item;
        }
      }
    }
    return null;
  }

  String _normalizeStoredProfession(String value) {
    final item = _findProfessionItem(value);
    if (item != null) {
      return _professionCanonicalValue(item);
    }
    return ProfessionLocalization.toCanonical(value);
  }

  String _professionLabel(Map<String, dynamic> item, String localeCode) {
    final localized = item[localeCode]?.toString().trim();
    if (localized != null && localized.isNotEmpty) return localized;
    return _professionCanonicalValue(item);
  }

  String _labelForStoredProfession(String profession, String localeCode) {
    final item = _findProfessionItem(profession);
    if (item != null) {
      return _professionLabel(item, localeCode);
    }
    return ProfessionLocalization.toLocalized(profession, localeCode);
  }

  @override
  void dispose() {
    _introController?.dispose();
    _backgroundController?.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _descriptionController.dispose();
    _townController.dispose();
    super.dispose();
  }

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

  Widget _buildReturnBackArrow() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const BackButtonIcon(),
        color: const Color(0xFF1976D2),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked != null) setState(() => _image = File(picked.path));
  }

  Future<void> _getCurrentLocation() async {
    final strings = _getLocalizedStrings();
    setState(() => _isLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw strings['location_services_disabled']!;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw strings['location_permissions_denied']!;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw strings['location_permissions_denied_forever']!;
      }

      Position position = await Geolocator.getCurrentPosition();
      LatLng loc = LatLng(position.latitude, position.longitude);
      setState(() {
        _workCenter = loc;
      });
      await _updateTownFromLocation(loc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateTownFromLocation(LatLng loc) async {
    try {
      await setLocaleIdentifier('he_IL');
      List<Placemark> placemarks = await placemarkFromCoordinates(
        loc.latitude,
        loc.longitude,
      );
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        String? town =
            placemark.locality ??
            placemark.subLocality ??
            placemark.subAdministrativeArea ??
            placemark.administrativeArea;
        if (town != null && town.isNotEmpty) {
          setState(() {
            _selectedTown = town;
            _townController.text = town;
          });
        }
      }
    } catch (e) {
      debugPrint("Reverse geocoding error: $e");
    }
  }

  Future<void> _saveProfile() async {
    final strings = _getLocalizedStrings();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      double? lat = _workCenter?.latitude;
      double? lng = _workCenter?.longitude;

      if (lat == null && _selectedTown != null && _selectedTown!.isNotEmpty) {
        try {
          List<Location> locations = await locationFromAddress(
            "$_selectedTown, Israel",
          );
          if (locations.isNotEmpty) {
            lat = locations.first.latitude;
            lng = locations.first.longitude;
          }
        } catch (e) {
          debugPrint("Geocoding error: $e");
        }
      }

      String? imageUrl;
      if (_image != null) {
        final ref = FirebaseStorage.instance.ref().child(
          'profile_pictures/${user.uid}.jpg',
        );
        await ref.putFile(_image!);
        imageUrl = await ref.getDownloadURL();
      }

      final updateData = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'town': _selectedTown,
        'lat': lat,
        'lng': lng,
        'workRadius': _workRadius,
        'workCenterLat': _workCenter?.latitude,
        'workCenterLng': _workCenter?.longitude,
        'optionalPhone': _altPhoneController.text.trim(),
        'description': _descriptionController.text.trim(),
        'professions': _selectedProfessions,
        'spokenLanguages': _selectedSpokenLanguages,
      };

      if (imageUrl != null) {
        updateData['profileImageUrl'] = imageUrl;
      }

      // Update in the unified 'users' collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update(updateData);
      await user.updateDisplayName(_nameController.text.trim());

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings['error_saving_profile']!.replaceFirst('{error}', '$e'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, String> _getLocalizedStrings() {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'עריכת פרופיל',
          'subtitle':
              'עדכן את הפרטים המקצועיים שלך כדי שהפרופיל ייראה ברור ומלא.',
          'access': 'עדכון פרופיל',
          'profile_card_title': 'עדכון פרטי הפרופיל',
          'profile_card_subtitle':
              'ערוך את המידע, השירותים והמיקום שלך במקום אחד.',
          'feature_profile_title': 'פרטים ברורים',
          'feature_profile_body': 'שם, אימייל וטלפון מעודכנים לפרופיל אמין.',
          'feature_location_title': 'מיקום מדויק',
          'feature_location_body':
              'עיר, מפה ורדיוס עבודה עוזרים ללקוחות למצוא אותך.',
          'feature_service_title': 'שירות מסודר',
          'feature_service_body':
              'מקצועות, שפות ותיאור שמסבירים בדיוק מה אתה מציע.',
          'basic_info': 'פרטים בסיסיים',
          'service_details': 'פרטי שירות',
          'about_you': 'עליך',
          'name': 'שם מלא',
          'email': 'אימייל',
          'phone': 'מספר טלפון',
          'town': 'עיר',
          'professions': 'בחר מקצועות',
          'spoken_languages': 'שפות מדוברות',
          'spoken_languages_required': 'יש לבחור לפחות שפה אחת',
          'alt_phone': 'טלפון נוסף (אופציונלי)',
          'desc': 'ספר על עצמך (אופציונלי)',
          'save': 'שמור שינויים',
          'req': 'שדה חובה',
          'search': 'חפש...',
          'work_radius': 'רדיוס עבודה',
          'select_radius': 'בחר רדיוס על המפה',
          'radius_val': 'רדיוס: {val} ק"מ',
          'current_loc': 'השתמש במיקום נוכחי',
          'pick_map': 'בחר מהמפה',
          'location_info': 'מיקום מדויק עוזר למצוא אותך בקלות',
          'location_services_disabled': 'שירותי המיקום כבויים.',
          'location_permissions_denied': 'הרשאות המיקום נדחו.',
          'location_permissions_denied_forever': 'הרשאות המיקום נדחו לצמיתות.',
          'error_saving_profile': 'שגיאה בשמירת הפרופיל: {error}',
        };
      case 'ar':
        return {
          'title': 'تعديل الملف الشخصي',
          'subtitle': 'حدّث تفاصيلك المهنية ليبدو ملفك واضحًا ومكتملًا.',
          'access': 'تحديث الملف الشخصي',
          'profile_card_title': 'تحديث تفاصيل الملف',
          'profile_card_subtitle':
              'عدّل المعلومات والخدمات والموقع في مكان واحد.',
          'feature_profile_title': 'تفاصيل واضحة',
          'feature_profile_body':
              'الاسم والبريد والهاتف المحدثة تجعل الملف أكثر موثوقية.',
          'feature_location_title': 'موقع دقيق',
          'feature_location_body':
              'المدينة والخريطة ونطاق العمل تساعد العملاء على العثور عليك.',
          'feature_service_title': 'خدمة مرتبة',
          'feature_service_body':
              'المهن واللغات والوصف تشرح بدقة ما الذي تقدمه.',
          'basic_info': 'المعلومات الأساسية',
          'service_details': 'تفاصيل الخدمة',
          'about_you': 'نبذة عنك',
          'name': 'الاسم الكامل',
          'email': 'البريد الإلكتروني',
          'phone': 'رقم الهاتف',
          'town': 'المدينة',
          'professions': 'اختر المهن',
          'spoken_languages': 'اللغات المحكية',
          'spoken_languages_required': 'اختر لغة واحدة على الأقل',
          'alt_phone': 'هاتف إضافي (اختياري)',
          'desc': 'الوصف (اختياري)',
          'save': 'حفظ التغييرات',
          'req': 'حقل مطلوب',
          'search': 'بحث...',
          'work_radius': 'نطاق العمل',
          'select_radius': 'اختر النطاق على الخريطة',
          'radius_val': 'النطاق: {val} كم',
          'current_loc': 'استخدام الموقع الحالي',
          'pick_map': 'اختيار من الخريطة',
          'location_info': 'الموقع الدقيق يساعد الآخرين في العثور عليك بسهولة',
          'location_services_disabled': 'خدمات الموقع معطلة.',
          'location_permissions_denied': 'تم رفض أذونات الموقع.',
          'location_permissions_denied_forever':
              'تم رفض أذونات الموقع بشكل دائم.',
          'error_saving_profile': 'حدث خطأ أثناء حفظ الملف الشخصي: {error}',
        };
      case 'am':
        return {
          'title': 'መገለጫ አርትዕ',
          'subtitle': 'መገለጫዎ ግልጽ እና የተሟላ እንዲታይ ሙያዊ ዝርዝሮችዎን ያዘምኑ።',
          'access': 'መገለጫ ማዘመን',
          'profile_card_title': 'የመገለጫ ዝርዝሮችን ያዘምኑ',
          'profile_card_subtitle': 'መረጃዎን እና አገልግሎቶችዎን እና አካባቢዎን በአንድ ቦታ ያርትዑ።',
          'feature_profile_title': 'ግልጽ ዝርዝሮች',
          'feature_profile_body': 'የተዘመኑ ስም፣ ኢሜይል እና ስልክ መገለጫዎን የታማኝ ያደርጋሉ።',
          'feature_location_title': 'ትክክለኛ አካባቢ',
          'feature_location_body': 'ከተማ፣ ካርታ እና የስራ ክልል ደንበኞች እንዲያገኙዎ ያግዛሉ።',
          'feature_service_title': 'የተደራጀ አገልግሎት',
          'feature_service_body': 'ሙያዎች፣ ቋንቋዎች እና መግለጫዎ የሚያቀርቡትን በግልጽ ያሳያሉ።',
          'basic_info': 'መሰረታዊ መረጃ',
          'service_details': 'የአገልግሎት ዝርዝሮች',
          'about_you': 'ስለ እርስዎ',
          'name': 'ሙሉ ስም',
          'email': 'ኢሜይል',
          'phone': 'የስልክ ቁጥር',
          'town': 'ከተማ',
          'professions': 'ሙያዎችን ይምረጡ',
          'spoken_languages': 'የሚነገሩ ቋንቋዎች',
          'spoken_languages_required': 'ቢያንስ አንድ ቋንቋ ይምረጡ',
          'alt_phone': 'ተጨማሪ ስልክ (አማራጭ)',
          'desc': 'መግለጫ (አማራጭ)',
          'save': 'ለውጦችን አስቀምጥ',
          'req': 'አስፈላጊ',
          'search': 'ፈልግ...',
          'work_radius': 'የስራ ክልል',
          'select_radius': 'ክልሉን በካርታ ላይ ይምረጡ',
          'radius_val': 'ክልል: {val} ኪ.ሜ',
          'current_loc': 'አሁን ያለውን አካባቢ ይጠቀሙ',
          'pick_map': 'ከካርታ ላይ ይምረጡ',
          'location_info': 'ትክክለኛ አካባቢ ሰዎች በቀላሉ እንዲያገኙዎ ያግዛል',
          'location_services_disabled': 'የአካባቢ አገልግሎቶች ጠፍተዋል።',
          'location_permissions_denied': 'የአካባቢ ፍቃዶች ተከልክለዋል።',
          'location_permissions_denied_forever': 'የአካባቢ ፍቃዶች ለዘላለም ተከልክለዋል።',
          'error_saving_profile': 'መገለጫን ሲያስቀምጡ ስህተት ተፈጥሯል: {error}',
        };
      case 'ru':
        return {
          'title': 'Редактировать профиль',
          'subtitle':
              'Обновите профессиональные данные, чтобы профиль выглядел полным и понятным.',
          'access': 'Обновление профиля',
          'profile_card_title': 'Обновление данных профиля',
          'profile_card_subtitle':
              'Измените информацию, услуги и местоположение в одном месте.',
          'feature_profile_title': 'Понятные данные',
          'feature_profile_body':
              'Актуальные имя, почта и телефон делают профиль надежнее.',
          'feature_location_title': 'Точное местоположение',
          'feature_location_body':
              'Город, карта и радиус работы помогают клиентам быстрее вас найти.',
          'feature_service_title': 'Структурированные услуги',
          'feature_service_body':
              'Профессии, языки и описание ясно показывают, что вы предлагаете.',
          'basic_info': 'Основная информация',
          'service_details': 'Детали услуги',
          'about_you': 'О вас',
          'name': 'Полное имя',
          'email': 'Эл. почта',
          'phone': 'Номер телефона',
          'town': 'Город',
          'professions': 'Выберите профессии',
          'spoken_languages': 'Разговорные языки',
          'spoken_languages_required': 'Выберите хотя бы один язык',
          'alt_phone': 'Доп. телефон (необязательно)',
          'desc': 'Описание (необязательно)',
          'save': 'Сохранить изменения',
          'req': 'Обязательное поле',
          'search': 'Поиск...',
          'work_radius': 'Радиус работы',
          'select_radius': 'Выбрать радиус на карте',
          'radius_val': 'Радиус: {val} км',
          'current_loc': 'Использовать текущее местоположение',
          'pick_map': 'Выбрать на карте',
          'location_info': 'Точное местоположение помогает быстрее вас найти',
          'location_services_disabled': 'Службы геолокации отключены.',
          'location_permissions_denied': 'Доступ к геолокации запрещен.',
          'location_permissions_denied_forever':
              'Доступ к геолокации запрещен навсегда.',
          'error_saving_profile': 'Ошибка при сохранении профиля: {error}',
        };
      default:
        return {
          'title': 'Edit Profile',
          'subtitle':
              'Update your professional details so your profile feels complete and easy to trust.',
          'access': 'Profile Update',
          'profile_card_title': 'Update Profile Details',
          'profile_card_subtitle':
              'Edit your information, services, and location in one place.',
          'feature_profile_title': 'Clear details',
          'feature_profile_body':
              'Updated name, email, and phone make your profile more trustworthy.',
          'feature_location_title': 'Precise location',
          'feature_location_body':
              'City, map, and work radius help clients find you faster.',
          'feature_service_title': 'Organized service info',
          'feature_service_body':
              'Professions, languages, and description explain exactly what you offer.',
          'basic_info': 'Basic Information',
          'service_details': 'Service Details',
          'about_you': 'About You',
          'name': 'Full Name',
          'email': 'Email',
          'phone': 'Phone Number',
          'town': 'City',
          'professions': 'Select Professions',
          'spoken_languages': 'Spoken Languages',
          'spoken_languages_required': 'Select at least one language',
          'alt_phone': 'Alt Phone (Optional)',
          'desc': 'Description (Optional)',
          'save': 'Save Changes',
          'req': 'Required',
          'search': 'Search...',
          'work_radius': 'Work Radius',
          'select_radius': 'Select radius on Map',
          'radius_val': 'Radius: {val} km',
          'current_loc': 'Use Current Location',
          'pick_map': 'Select on Map',
          'location_info': 'Precise location helps others find you easily',
          'location_services_disabled': 'Location services are disabled.',
          'location_permissions_denied': 'Location permissions are denied.',
          'location_permissions_denied_forever':
              'Location permissions are permanently denied.',
          'error_saving_profile': 'Error saving profile: {error}',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureAnimationControllers();
    final strings = _getLocalizedStrings();
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
            final verticalPadding = isWide ? 56.0 : 28.0;

            return Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: backgroundController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _EditProfileBackgroundPainter(
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: _buildReturnBackArrow(),
                            ),
                            const SizedBox(height: 10),
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1440,
                                ),
                                child: isWide
                                    ? _buildWideLayout(strings, isRtl)
                                    : _buildNarrowLayout(strings),
                              ),
                            ),
                          ],
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
      delay: 0.16,
      begin: isRtl ? const Offset(-0.06, 0) : const Offset(0.06, 0),
      child: _buildProfileFormCard(strings, compact: false),
    );
    const gap = SizedBox(width: 56);
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
          delay: 0.08,
          child: _buildIntroPanel(strings, compact: true),
        ),
        const SizedBox(height: 22),
        _buildAnimatedEntry(
          delay: 0.14,
          child: _buildProfileFormCard(strings, compact: true),
        ),
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
        SizedBox(height: compact ? 20 : 26),
        Text(
          strings['title'] ?? 'Edit Profile',
          textAlign: textAlign,
          style: TextStyle(
            color: const Color(0xFF070B18),
            fontSize: compact ? 38 : 54,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 540 : 620),
          child: Text(
            strings['subtitle'] ??
                'Update your professional details so your profile feels complete and easy to trust.',
            textAlign: textAlign,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 18,
              height: 1.45,
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 44),
          _buildFeatureHighlights(strings),
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
            (strings['access'] ?? 'Profile Update').toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF1976D2),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureHighlights(Map<String, String> strings) {
    final features = [
      _EditProfileFeature(
        icon: Icons.badge_outlined,
        title: strings['feature_profile_title']!,
        body: strings['feature_profile_body']!,
      ),
      _EditProfileFeature(
        icon: Icons.place_outlined,
        title: strings['feature_location_title']!,
        body: strings['feature_location_body']!,
      ),
      _EditProfileFeature(
        icon: Icons.work_outline_rounded,
        title: strings['feature_service_title']!,
        body: strings['feature_service_body']!,
      ),
    ];

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
              child: _buildFeatureCard(features[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildFeatureCard(_EditProfileFeature feature) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
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
      child: Column(
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

  Widget _buildProfileFormCard(
    Map<String, String> strings, {
    required bool compact,
  }) {
    return SizedBox(
      width: compact ? double.infinity : 560,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 24 : 38),
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
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildLogoMark(Icons.edit_note_rounded),
              const SizedBox(height: 24),
              Text(
                strings['profile_card_title'] ?? 'Update Profile Details',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF070B18),
                  fontSize: compact ? 31 : 36,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                strings['profile_card_subtitle'] ??
                    'Edit your information, services, and location in one place.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 16,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 28),
              _buildImagePicker(),
              const SizedBox(height: 24),
              _buildSectionCard(
                title: strings['basic_info']!,
                child: Column(
                  children: [
                    _buildStyledTextField(
                      controller: _nameController,
                      labelText: strings['name']!,
                      icon: Icons.person_outline,
                      validator: (v) => v!.isEmpty ? strings['req'] : null,
                    ),
                    const SizedBox(height: 16),
                    _buildStyledTextField(
                      controller: _emailController,
                      labelText: strings['email']!,
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    _buildLocationSection(strings),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (widget.userData['role'] == 'worker') ...[
                _buildSectionCard(
                  title: strings['service_details']!,
                  child: Column(
                    children: [
                      _buildWorkRadiusSelector(strings),
                      const SizedBox(height: 16),
                      _buildMultiSelectProfessions(strings),
                      const SizedBox(height: 16),
                      _buildStyledTextField(
                        controller: _altPhoneController,
                        labelText: strings['alt_phone']!,
                        icon: Icons.phone_android_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _buildSectionCard(
                title: strings['about_you']!,
                child: Column(
                  children: [
                    _buildStyledTextField(
                      controller: _phoneController,
                      labelText: strings['phone']!,
                      icon: Icons.phone_android_outlined,
                      keyboardType: TextInputType.phone,
                      enabled: false,
                    ),
                    const SizedBox(height: 16),
                    _buildSpokenLanguagesSelector(strings),
                    const SizedBox(height: 16),
                    _buildStyledTextField(
                      controller: _descriptionController,
                      labelText: strings['desc']!,
                      icon: Icons.description_outlined,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              _buildSaveButton(strings),
              if (_isLoading) ...[
                const SizedBox(height: 14),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationSection(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStyledTextField(
          controller: _townController,
          labelText: strings['town']!,
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
                label: Text(
                  strings['current_loc']!,
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Color(0xFF1976D2)),
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
                icon: const Icon(Icons.map_outlined, size: 18),
                label: Text(
                  strings['pick_map']!,
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Color(0xFF1976D2)),
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

  Widget _buildLogoMark(IconData icon) {
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
      child: Icon(icon, color: Colors.white, size: 34),
    );
  }

  Widget _buildSpokenLanguagesSelector(Map<String, String> strings) {
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;

    return FormField<List<String>>(
      initialValue: _selectedSpokenLanguages,
      validator: (_) => _selectedSpokenLanguages.isEmpty
          ? strings['spoken_languages_required']
          : null,
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.language_rounded,
                size: 20,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 10),
              Text(
                strings['spoken_languages']!,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Color(0xFF374151),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _spokenLanguageOptions.map((language) {
              final selected = _selectedSpokenLanguages.contains(language);
              return FilterChip(
                label: Text(_spokenLanguageLabel(language, localeCode)),
                selected: selected,
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _selectedSpokenLanguages.add(language);
                    } else {
                      _selectedSpokenLanguages.remove(language);
                    }
                  });
                  field.didChange(_selectedSpokenLanguages);
                },
                selectedColor: const Color(0xFF1976D2).withValues(alpha: 0.14),
                checkmarkColor: const Color(0xFF1976D2),
                backgroundColor: const Color(0xFFF8FAFC),
                side: BorderSide(
                  color: selected
                      ? const Color(0xFF1976D2)
                      : const Color(0xFFE2E8F0),
                ),
                labelStyle: TextStyle(
                  color: selected
                      ? const Color(0xFF0F4C9A)
                      : const Color(0xFF475569),
                  fontWeight: FontWeight.w700,
                ),
              );
            }).toList(),
          ),
          if (field.hasError) ...[
            const SizedBox(height: 8),
            Text(
              field.errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  String _spokenLanguageLabel(String language, String localeCode) {
    const labels = {
      'Hebrew': {
        'en': 'Hebrew',
        'he': 'עברית',
        'ar': 'العبرية',
        'ru': 'Иврит',
        'am': 'ዕብራይስጥ',
      },
      'Arabic': {
        'en': 'Arabic',
        'he': 'ערבית',
        'ar': 'العربية',
        'ru': 'Арабский',
        'am': 'አረብኛ',
      },
      'English': {
        'en': 'English',
        'he': 'אנגלית',
        'ar': 'الإنجليزية',
        'ru': 'Английский',
        'am': 'እንግሊዝኛ',
      },
      'Russian': {
        'en': 'Russian',
        'he': 'רוסית',
        'ar': 'الروسية',
        'ru': 'Русский',
        'am': 'ሩሲኛ',
      },
      'Amharic': {
        'en': 'Amharic',
        'he': 'אמהרית',
        'ar': 'الأمهرية',
        'ru': 'Амхарский',
        'am': 'አማርኛ',
      },
    };

    return labels[language]?[localeCode] ?? labels[language]?['en'] ?? language;
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map_outlined, color: Color(0xFF1976D2)),
              const SizedBox(width: 12),
              Text(
                strings['work_radius']!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final radiusText = Text(
                strings['radius_val']!.replaceFirst(
                  '{val}',
                  (_workRadius / 1000).toStringAsFixed(1),
                ),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              );

              final pickRadiusButton = ElevatedButton.icon(
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
                    if (_workCenter != null) {
                      _updateTownFromLocation(_workCenter!);
                    }
                  }
                },
                icon: const Icon(Icons.my_location, size: 18),
                label: Text(strings['select_radius']!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              );

              final isNarrow = constraints.maxWidth < 340;
              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    radiusText,
                    const SizedBox(height: 8),
                    pickRadiusButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: radiusText),
                  const SizedBox(width: 12),
                  pickRadiusButton,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF1976D2), Color(0xFF62D6E8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1976D2).withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 58,
              backgroundColor: const Color(0xFFF1F5F9),
              backgroundImage: _image != null
                  ? FileImage(_image!)
                  : (widget.userData['profileImageUrl'] != null &&
                                widget.userData['profileImageUrl'].isNotEmpty
                            ? NetworkImage(widget.userData['profileImageUrl'])
                            : null)
                        as ImageProvider?,
              child:
                  _image == null &&
                      (widget.userData['profileImageUrl'] == null ||
                          widget.userData['profileImageUrl'].isEmpty)
                  ? Icon(
                      Icons.person_rounded,
                      size: 56,
                      color: Colors.grey[400],
                    )
                  : null,
            ),
          ),
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1976D2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
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
    FocusNode? focusNode,
    String? hintText,
    bool enabled = true,
    bool readOnly = false,
    VoidCallback? onTap,
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
        prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF)),
        filled: true,
        fillColor: enabled
            ? Colors.white.withValues(alpha: 0.86)
            : const Color(0xFFE5E7EB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF1976D2), width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B2A41).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101827),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildMultiSelectProfessions(Map<String, String> strings) {
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;
    final options = _professionItems.isNotEmpty
        ? _professionItems
        : ProfessionLocalization.canonicalProfessions
              .map((profession) => <String, dynamic>{'en': profession})
              .toList();
    final localizedOptions = options
        .map((item) => _professionLabel(item, localeCode))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return localizedOptions;
              }
              return localizedOptions.where((String option) {
                return option.toLowerCase().contains(
                  textEditingValue.text.toLowerCase(),
                );
              });
            },
            onSelected: (String selection) {
              final matchedItem = _findProfessionItem(selection);
              final canonical = matchedItem != null
                  ? _professionCanonicalValue(matchedItem)
                  : ProfessionLocalization.toCanonical(selection);
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
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
                  _professionsSearchController = controller;
                  return _buildStyledTextField(
                    controller: controller,
                    labelText: strings['professions']!,
                    icon: Icons.work_outline,
                    focusNode: focusNode,
                    hintText: strings['search'],
                  );
                },
          ),
        ),
        if (_selectedProfessions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _selectedProfessions
                .map(
                  (prof) => Chip(
                    label: Text(_labelForStoredProfession(prof, localeCode)),
                    onDeleted: () {
                      setState(() {
                        _selectedProfessions.remove(prof);
                      });
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildSaveButton(Map<String, String> strings) {
    return Container(
      width: double.infinity,
      height: 58,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1976D2), Color(0xFF62D6E8)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.34),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          strings['save']!,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _EditProfileFeature {
  const _EditProfileFeature({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _EditProfileBackgroundPainter extends CustomPainter {
  const _EditProfileBackgroundPainter(this.progress);

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
  bool shouldRepaint(covariant _EditProfileBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
