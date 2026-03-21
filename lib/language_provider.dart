import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  Locale _locale = const Locale('he');

  LanguageProvider() {
    _loadLocale();
  }

  Locale get locale => _locale;

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final String? languageCode = prefs.getString('language_code');
    if (languageCode != null) {
      _locale = Locale(languageCode);
      notifyListeners();
    }
  }
  
  /// Sets the locale using a language code (e.g., 'en', 'he', 'ar')
  Future<void> setLocale(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    _locale = Locale(languageCode);
    await prefs.setString('language_code', languageCode);
    notifyListeners();
  }

  Map<String, String> getLocalizedStrings() {
    switch (_locale.languageCode) {
      case 'he':
        return {
          'projects': 'פרויקטים',
          'reviews': 'ביקורות',
          'ratings': 'דירוגים',
          'about': 'אודות',
          'schedule': 'לוח זמנים',
          'analytics': 'אנליטיקה',
          'biography': 'ביוגרפיה',
          'no_bio': 'אין ביוגרפיה',
          'professions': 'מקצועות',
          'verification_status': 'סטטוס אימות',
          'id_verified': 'תעודת זהות מאומתת',
          'business_verified': 'עסק מאומת',
          'insured': 'מבוטח',
          'get_verified': 'קבל אימות',
          'no_reviews': 'אין ביקורות עדיין',
          'message': 'הודעה',
          'write_review': 'כתוב ביקורת',
          'comment_hint': 'כתוב את התגובה שלך כאן...',
          'cancel': 'ביטול',
          'submit': 'שלח',
          'please_login': 'אנא התחבר כדי לצפות בפרופיל',
          'login': 'התחברות',
          'select_radius': 'בחר רדיוס עבודה',
          'radius_val': 'רדיוס: {val} ק"מ',
        };
      case 'ar':
        return {
          'projects': 'مشاريع',
          'reviews': 'تقييمات',
          'ratings': 'تقييمات',
          'about': 'حول',
          'schedule': 'جدول المواعيد',
          'analytics': 'التحليلات',
          'biography': 'سيرة شخصية',
          'no_bio': 'لا توجد سيرة شخصية',
          'professions': 'المهن',
          'verification_status': 'حالة التحقق',
          'id_verified': 'تم التحقق من الهوية',
          'business_verified': 'عمل تم التحقق منه',
          'insured': 'مؤمن عليه',
          'get_verified': 'احصل على التحقق',
          'no_reviews': 'لا توجد تقييمات بعد',
          'message': 'رسالة',
          'write_review': 'اكتب تقييمًا',
          'comment_hint': 'اكتب تعليقك هنا...',
          'cancel': 'إلغاء',
          'submit': 'إرسال',
          'please_login': 'يرجى تسجيل الدخول لعرض الملف الشخصי',
          'login': 'تسجيل الدخول',
          'select_radius': 'اختر نصف قطر العمل',
          'radius_val': 'نصف القطر: {val} كم',
        };
      default:
        return {
          'projects': 'Projects',
          'reviews': 'Reviews',
          'ratings': 'Ratings',
          'about': 'About',
          'schedule': 'Schedule',
          'analytics': 'Analytics',
          'biography': 'Biography',
          'no_bio': 'No biography provided',
          'professions': 'Professions',
          'verification_status': 'Verification Status',
          'id_verified': 'ID Verified',
          'business_verified': 'Business Verified',
          'insured': 'Insured',
          'get_verified': 'Get Verified',
          'no_reviews': 'No reviews yet',
          'message': 'Message',
          'write_review': 'Write a Review',
          'comment_hint': 'Write your comment here...',
          'cancel': 'Cancel',
          'submit': 'Submit',
          'please_login': 'Please login to view profile',
          'login': 'Login',
          'select_radius': 'Select Work Radius',
          'radius_val': 'Radius: {val} km',
        };
    }
  }
}
