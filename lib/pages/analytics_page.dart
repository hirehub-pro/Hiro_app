import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/subscription_access_service.dart';

class AnalyticsPage extends StatefulWidget {
  final String userId;
  final Map<String, String> strings;

  const AnalyticsPage({super.key, required this.userId, required this.strings});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  static const String _allProfessionsKey = '__all_professions__';
  static const String _vpdDocId = 'currentWeek';
  static const List<String> _weekDayKeys = [
    'sunday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
  ];

  bool _isLoading = true;
  int _totalJobs = 0;
  int _viewsCount = 0;
  double _totalEarnings = 0.0;
  double _avgRating = 0.0;
  double _overallAvgRating = 0.0;

  double _avgPrice = 0.0;
  double _avgService = 0.0;
  double _avgTiming = 0.0;
  double _avgWorkQuality = 0.0;

  List<FlSpot> _earningsSpots = [];
  List<BarChartGroupData> _viewGroups = [];

  String _performanceOverview = '';
  String _topServices = '';
  double _conversionRate = 0.0;

  List<String> _professionOptions = [];
  String _selectedProfession = _allProfessionsKey;
  Map<String, Map<String, dynamic>> _professionRatingStats = {};
  Map<String, Map<String, int>> _professionWeeklyViews = {};
  List<int> _weeklyViewCounts = List.filled(7, 0);
  late final Future<SubscriptionAccessState> _accessFuture;

  int get _weeklyViewsTotal => _sumWeekCounts(_weeklyViewCounts);

  String _normalizeLocaleCode(String code) {
    final normalized = code.toLowerCase();
    if (normalized.startsWith('he') || normalized == 'iw') return 'he';
    if (normalized.startsWith('ar')) return 'ar';
    if (normalized.startsWith('ru')) return 'ru';
    if (normalized.startsWith('am')) return 'am';
    return 'en';
  }

  String get _localeCode {
    final code = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    return _normalizeLocaleCode(code);
  }

  Map<String, String> _localStrings(String locale) {
    switch (locale) {
      case 'he':
        return {
          'analytics_title': 'לוח בקרה עסקי',
          'all_professions': 'כל המקצועות',
          'total_earnings': 'הכנסות משוערות',
          'total_jobs': 'עבודות',
          'rating': 'דירוג',
          'views': 'צפיות',
          'views_this_week': 'צפיות השבוע',
          'conversion': 'המרה',
          'top_skill': 'מיומנות מובילה',
          'conversion_help':
              'המרה היא אחוז הצופים בפרופיל שהפכו לעבודות. נוסחה: עבודות חלקי צפיות כפול 100.',
          'earnings_trend': 'מגמת הכנסות (7 ימים אחרונים)',
          'profile_reach': 'חשיפה לפרופיל',
          'service_quality_breakdown': 'פירוט איכות השירות',
          'price': 'מחיר',
          'service': 'שירות',
          'timing': 'עמידה בזמנים',
          'work_quality': 'איכות עבודה',
          'growth_recommendation': 'המלצת צמיחה',
          'no_data': 'אין נתונים',
          'growth_scope_all': 'בכל המקצועות',
          'growth_scope_for': 'עבור',
          'growth_getting_started':
              'אתה רק בתחילת הדרך. השלם את העבודות הראשונות ובקש מלקוחות ביקורות כדי לפתוח תובנות מדויקות יותר.',
          'growth_low_visibility':
              'החשיפה שלך עדיין נמוכה {scope}. עדכן תמונת פרופיל, כותרת ותיאור שירות כדי למשוך יותר צפיות.',
          'growth_low_conversion':
              'אתה מקבל צפיות אבל מעט סגירות {scope}. שפר כותרת פרופיל, הוסף מחירים ברורים והדגש תוצאות אחרונות.',
          'growth_high_conversion':
              'המרה מצוינת {scope}. שמור על זמן תגובה מהיר והמשך לבקש ביקורות מלקוחות מרוצים.',
          'growth_excellent_rating':
              'הדירוג שלך מצוין. השתמש בזה כהוכחה חברתית בראש הפרופיל כדי לזכות ביותר עבודות.',
          'growth_improve_rating':
              'אפשר לשפר את הדירוג. התמקד בשיפור {metric} בעבודות הבאות ובקש משוב מפורט מלקוחות.',
          'growth_top_service':
              'המקצוע החזק ביותר שלך הוא {service}. הצג אותו ראשון בפרופיל ובפורטפוליו.',
          'growth_stable':
              'הביצועים יציבים {scope}. המשך להשלים עבודות באופן עקבי ואסוף יותר ביקורות כדי לצמוח מהר יותר.',
          'day_sun': 'א',
          'day_mon': 'ב',
          'day_tue': 'ג',
          'day_wed': 'ד',
          'day_thu': 'ה',
          'day_fri': 'ו',
          'day_sat': 'ש',
        };
      case 'ar':
        return {
          'analytics_title': 'لوحة تحكم الأعمال',
          'all_professions': 'كل المهن',
          'total_earnings': 'الأرباح التقديرية',
          'total_jobs': 'الأعمال',
          'rating': 'التقييم',
          'views': 'المشاهدات',
          'views_this_week': 'مشاهدات هذا الأسبوع',
          'conversion': 'التحويل',
          'top_skill': 'المهارة الأقوى',
          'conversion_help':
              'التحويل هو نسبة مشاهدي الملف الذين أصبحوا أعمالاً. المعادلة: الأعمال ÷ المشاهدات × 100.',
          'earnings_trend': 'اتجاه الأرباح (آخر 7 أيام)',
          'profile_reach': 'وصول الملف الشخصي',
          'service_quality_breakdown': 'تفصيل جودة الخدمة',
          'price': 'السعر',
          'service': 'الخدمة',
          'timing': 'الالتزام بالوقت',
          'work_quality': 'جودة العمل',
          'growth_recommendation': 'توصية للنمو',
          'no_data': 'لا توجد بيانات',
          'growth_scope_all': 'عبر جميع المهن',
          'growth_scope_for': 'لـ',
          'growth_getting_started':
              'أنت في البداية. أكمل أعمالك الأولى واطلب تقييمات من العملاء للحصول على رؤى أفضل.',
          'growth_low_visibility':
              'ظهورك ما زال منخفضاً {scope}. حدّث صورة الملف والعنوان ووصف الخدمة لجذب المزيد من المشاهدات.',
          'growth_low_conversion':
              'تحصل على مشاهدات لكن حجوزات قليلة {scope}. حسّن عنوان ملفك وأضف أسعاراً واضحة وأبرز نتائجك الأخيرة.',
          'growth_high_conversion':
              'معدل التحويل ممتاز {scope}. حافظ على سرعة الرد واستمر بطلب التقييمات من العملاء الراضين.',
          'growth_excellent_rating':
              'تقييمك ممتاز. استخدم ذلك كدليل اجتماعي في أعلى ملفك للفوز بمزيد من الأعمال.',
          'growth_improve_rating':
              'يمكن تحسين تقييمك. ركّز على تحسين {metric} في أعمالك القادمة واطلب ملاحظات تفصيلية من العملاء.',
          'growth_top_service':
              'أقوى خدمة لديك هي {service}. اعرضها أولاً في ملفك ومعرض أعمالك.',
          'growth_stable':
              'الأداء مستقر {scope}. استمر في إنجاز الأعمال بانتظام واجمع مزيداً من التقييمات للنمو أسرع.',
          'day_sun': 'ح',
          'day_mon': 'ن',
          'day_tue': 'ث',
          'day_wed': 'ر',
          'day_thu': 'خ',
          'day_fri': 'ج',
          'day_sat': 'س',
        };
      case 'ru':
        return {
          'analytics_title': 'Бизнес-аналитика',
          'all_professions': 'Все профессии',
          'total_earnings': 'Оценочный доход',
          'total_jobs': 'Заказы',
          'rating': 'Рейтинг',
          'views': 'Просмотры',
          'views_this_week': 'Просмотры за неделю',
          'conversion': 'Конверсия',
          'top_skill': 'Лучший навык',
          'conversion_help':
              'Конверсия — это процент просмотров профиля, которые стали заказами. Формула: заказы ÷ просмотры × 100.',
          'earnings_trend': 'Динамика дохода (последние 7 дней)',
          'profile_reach': 'Охват профиля',
          'service_quality_breakdown': 'Показатели качества сервиса',
          'price': 'Цена',
          'service': 'Сервис',
          'timing': 'Сроки',
          'work_quality': 'Качество работы',
          'growth_recommendation': 'Рекомендация по росту',
          'no_data': 'Нет данных',
          'growth_scope_all': 'по всем профессиям',
          'growth_scope_for': 'для',
          'growth_getting_started':
              'Вы только начинаете. Выполните первые заказы и попросите клиентов оставить отзывы, чтобы получить более точную аналитику.',
          'growth_low_visibility':
              'Ваша видимость пока низкая {scope}. Обновите фото профиля, заголовок и описание услуг, чтобы привлечь больше просмотров.',
          'growth_low_conversion':
              'У вас есть просмотры, но мало заказов {scope}. Улучшите заголовок профиля, добавьте понятные цены и покажите последние результаты.',
          'growth_high_conversion':
              'Отличная конверсия {scope}. Отвечайте быстро и продолжайте просить довольных клиентов оставлять отзывы.',
          'growth_excellent_rating':
              'Ваш рейтинг отличный. Используйте это как социальное доказательство вверху профиля, чтобы получать больше заказов.',
          'growth_improve_rating':
              'Рейтинг можно улучшить. Сфокусируйтесь на улучшении показателя {metric} в следующих заказах и просите подробную обратную связь.',
          'growth_top_service':
              'Ваша самая сильная услуга — {service}. Покажите её первой в профиле и портфолио.',
          'growth_stable':
              'Показатели стабильны {scope}. Продолжайте регулярно выполнять заказы и собирайте больше отзывов для ускоренного роста.',
          'day_sun': 'Вс',
          'day_mon': 'Пн',
          'day_tue': 'Вт',
          'day_wed': 'Ср',
          'day_thu': 'Чт',
          'day_fri': 'Пт',
          'day_sat': 'Сб',
        };
      case 'am':
        return {
          'analytics_title': 'የንግድ ትንታኔ',
          'all_professions': 'ሁሉም ሙያዎች',
          'total_earnings': 'የተገመተ ገቢ',
          'total_jobs': 'ስራዎች',
          'rating': 'ደረጃ',
          'views': 'እይታዎች',
          'views_this_week': 'የዚህ ሳምንት እይታዎች',
          'conversion': 'መቀየር',
          'top_skill': 'ከፍተኛ ችሎታ',
          'conversion_help':
              'መቀየር ማለት ፕሮፋይል እይታዎች ወደ ስራ የተቀየሩበት መጠን ነው። ፎርሙላ: ስራዎች ÷ እይታዎች × 100.',
          'earnings_trend': 'የገቢ አቅጣጫ (የመጨረሻ 7 ቀናት)',
          'profile_reach': 'የፕሮፋይል ድርሻ',
          'service_quality_breakdown': 'የአገልግሎት ጥራት ዝርዝር',
          'price': 'ዋጋ',
          'service': 'አገልግሎት',
          'timing': 'ሰዓት',
          'work_quality': 'የስራ ጥራት',
          'growth_recommendation': 'የእድገት ምክር',
          'no_data': 'መረጃ የለም',
          'growth_scope_all': 'በሁሉም ሙያዎች',
          'growth_scope_for': 'ለ',
          'growth_getting_started':
              'አሁን ብቻ ጀምረዋል። የመጀመሪያ ስራዎችዎን ያጠናቀቁ እና የተሻለ ትንታኔ ለማግኘት ከደንበኞች ግምገማ ይጠይቁ።',
          'growth_low_visibility':
              'የእርስዎ ታይነት አሁንም ዝቅተኛ ነው {scope}። የፕሮፋይል ፎቶ፣ ርዕስ እና የአገልግሎት መግለጫ ያዘምኑ።',
          'growth_low_conversion':
              'እይታ አለዎት ነገር ግን ቦኪንግ ዝቅተኛ ነው {scope}። የፕሮፋይል ርዕስ ያሻሽሉ፣ ግልፅ ዋጋ ያክሉ እና የቅርብ ውጤቶችን ያሳዩ።',
          'growth_high_conversion':
              'በጣም ጥሩ መቀየር {scope}። ፈጣን ምላሽ ይቀጥሉ እና ከደስተኛ ደንበኞች ግምገማ መጠየቅ ይቀጥሉ።',
          'growth_excellent_rating':
              'ደረጃዎ በጣም ጥሩ ነው። ተጨማሪ ስራ ለማግኘት በፕሮፋይል ላይ እንደ ማስረጃ ያሳዩት።',
          'growth_improve_rating':
              'ደረጃዎን ማሻሻል ይቻላል። በሚቀጥሉት ስራዎች {metric} ላይ ትኩረት ያድርጉ እና ዝርዝር አስተያየት ይጠይቁ።',
          'growth_top_service':
              'ከፍተኛ ጠንካራ አገልግሎትዎ {service} ነው። በፕሮፋይልና በፖርትፎሊዮ መጀመሪያ ያሳዩ።',
          'growth_stable':
              'አፈፃፀሙ የተረጋጋ ነው {scope}። ስራ በመደበኛ ሁኔታ ይቀጥሉ እና ተጨማሪ ግምገማዎች ይሰብስቡ።',
          'day_sun': 'እሑድ',
          'day_mon': 'ሰኞ',
          'day_tue': 'ማክ',
          'day_wed': 'ረቡዕ',
          'day_thu': 'ሐሙስ',
          'day_fri': 'አርብ',
          'day_sat': 'ቅዳ',
        };
      default:
        return {
          'analytics_title': 'Business Dashboard',
          'all_professions': 'All professions',
          'total_earnings': 'Estimated Earnings',
          'total_jobs': 'Jobs',
          'rating': 'Rating',
          'views': 'Views',
          'views_this_week': 'Views This Week',
          'conversion': 'Conversion',
          'top_skill': 'Top Skill',
          'conversion_help':
              'Conversion is the percentage of profile viewers who became jobs. Formula: jobs ÷ views × 100.',
          'earnings_trend': 'Earnings Trend (Last 7 Days)',
          'profile_reach': 'Profile Reach',
          'service_quality_breakdown': 'Service Quality Breakdown',
          'price': 'Price',
          'service': 'Service',
          'timing': 'Timing',
          'work_quality': 'Work Quality',
          'growth_recommendation': 'Growth Recommendation',
          'no_data': 'No data',
          'growth_scope_all': 'across all professions',
          'growth_scope_for': 'for',
          'growth_getting_started':
              'You are just getting started. Complete your first jobs and ask clients for reviews to unlock better insights.',
          'growth_low_visibility':
              'Your visibility is still low {scope}. Update your profile photo, title, and service description to attract more views.',
          'growth_low_conversion':
              'You are getting views but few bookings {scope}. Improve your profile headline, add clear prices, and highlight recent results.',
          'growth_high_conversion':
              'Great conversion {scope}. Keep response time fast and continue asking happy clients for new reviews.',
          'growth_excellent_rating':
              'Your rating is excellent. Use this as social proof near the top of your profile to win more jobs.',
          'growth_improve_rating':
              'Your rating can improve. Focus on better {metric} in your next jobs and ask clients for detailed feedback.',
          'growth_top_service':
              'Your strongest profession is {service}. Feature it first in your profile and portfolio.',
          'growth_stable':
              'Performance looks stable {scope}. Keep completing jobs consistently and collect more reviews to grow faster.',
          'day_sun': 'Sun',
          'day_mon': 'Mon',
          'day_tue': 'Tue',
          'day_wed': 'Wed',
          'day_thu': 'Thu',
          'day_fri': 'Fri',
          'day_sat': 'Sat',
        };
    }
  }

  String _t(String key) {
    final localized = _localStrings(_localeCode)[key];
    if (localized != null && localized.isNotEmpty) return localized;

    final fromParent = widget.strings[key];
    if (fromParent != null && fromParent.isNotEmpty) return fromParent;

    return _localStrings('en')[key] ?? key;
  }

  String _tp(String key, Map<String, String> params) {
    String value = _t(key);
    params.forEach((param, replacement) {
      value = value.replaceAll('{$param}', replacement);
    });
    return value;
  }

  @override
  void initState() {
    super.initState();
    _accessFuture = SubscriptionAccessService.getCurrentUserState();
    _fetchAnalytics();
  }

  double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return fallback;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return fallback;
  }

  String _weekKey(DateTime date) {
    final start = _startOfWeek(date);
    return '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
  }

  DateTime _startOfWeek(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final offsetToSunday = dayStart.weekday % 7;
    return dayStart.subtract(Duration(days: offsetToSunday));
  }

  bool _isCurrentWeek(dynamic rawWeekStart) {
    DateTime? saved;
    if (rawWeekStart is Timestamp) {
      saved = rawWeekStart.toDate();
    } else if (rawWeekStart is String) {
      saved = DateTime.tryParse(rawWeekStart);
    }

    if (saved == null) return false;

    final currentWeek = _startOfWeek(DateTime.now());
    final savedWeek = _startOfWeek(saved);
    return savedWeek.isAtSameMomentAs(currentWeek);
  }

  Map<String, int> _emptyWeekMap() {
    return {
      'sunday': 0,
      'monday': 0,
      'tuesday': 0,
      'wednesday': 0,
      'thursday': 0,
      'friday': 0,
      'saturday': 0,
      'TVTW': 0,
    };
  }

  List<int> _extractWeekCounts(Map<String, int> map) {
    return _weekDayKeys.map((day) => map[day] ?? 0).toList();
  }

  int _sumWeekCounts(List<int> counts) {
    return counts.fold<int>(0, (sum, value) => sum + value);
  }

  Map<String, int> _normalizeWeekData(Map<String, dynamic> data) {
    final normalized = _emptyWeekMap();

    if (_isCurrentWeek(data['weekStart'])) {
      for (final day in _weekDayKeys) {
        normalized[day] = _asInt(data[day]);
      }
      normalized['TVTW'] = _asInt(data['TVTW']);
      if (normalized['TVTW'] == 0) {
        normalized['TVTW'] = _sumWeekCounts(_extractWeekCounts(normalized));
      }
    }

    return normalized;
  }

  Future<Map<String, int>> _readVpdWeekFromShards(
    DocumentReference<Map<String, dynamic>> proRatingRef,
  ) async {
    final legacyDoc = await proRatingRef.collection('VPD').doc(_vpdDocId).get();

    final shards = await proRatingRef
        .collection('VPD')
        .doc(_vpdDocId)
        .collection('shards')
        .get();

    if (shards.docs.isEmpty) {
      if (!legacyDoc.exists) return _emptyWeekMap();
      return _normalizeWeekData(legacyDoc.data() ?? {});
    }

    final currentWeekKey = _weekKey(DateTime.now());
    final summed = _emptyWeekMap();

    for (final doc in shards.docs) {
      final data = doc.data();
      final weekKey = data['weekKey']?.toString();

      if (weekKey != null && weekKey != currentWeekKey) continue;
      if (weekKey == null && !_isCurrentWeek(data['weekStart'])) continue;

      for (final day in _weekDayKeys) {
        summed[day] = (summed[day] ?? 0) + _asInt(data[day]);
      }
      summed['TVTW'] = (summed['TVTW'] ?? 0) + _asInt(data['TVTW']);
    }

    if ((summed['TVTW'] ?? 0) == 0) {
      summed['TVTW'] = _sumWeekCounts(_extractWeekCounts(summed));
    }

    return summed;
  }

  Future<Map<String, Map<String, int>>> _fetchProfessionWeeklyViews(
    QuerySnapshot<Map<String, dynamic>> proRatingSnapshot,
  ) async {
    final result = <String, Map<String, int>>{};

    for (final proDoc in proRatingSnapshot.docs) {
      final data = proDoc.data();
      final profession = (data['profession'] ?? proDoc.id).toString();
      result[profession] = await _readVpdWeekFromShards(proDoc.reference);
    }

    return result;
  }

  String _buildGrowthRecommendation() {
    final noData = _t('no_data');

    if (_viewsCount == 0 && _totalJobs == 0) {
      return _t('growth_getting_started');
    }

    final parts = <String>[];
    final scope = _selectedProfession == _allProfessionsKey
        ? _t('growth_scope_all')
        : '${_t('growth_scope_for')} $_selectedProfession';

    if (_viewsCount < 20) {
      parts.add(_tp('growth_low_visibility', {'scope': scope}));
    } else if (_conversionRate < 5) {
      parts.add(_tp('growth_low_conversion', {'scope': scope}));
    } else if (_conversionRate >= 20) {
      parts.add(_tp('growth_high_conversion', {'scope': scope}));
    }

    if (_avgRating >= 4.5) {
      parts.add(_t('growth_excellent_rating'));
    } else if (_avgRating > 0 && _avgRating < 4.0) {
      final weakestMetric = _getWeakestMetricLabel();
      parts.add(_tp('growth_improve_rating', {'metric': weakestMetric}));
    }

    if (_topServices.isNotEmpty && _topServices != noData) {
      parts.add(_tp('growth_top_service', {'service': _topServices}));
    }

    if (parts.isEmpty) {
      return _tp('growth_stable', {'scope': scope});
    }

    return parts.join(' ');
  }

  String _getWeakestMetricLabel() {
    final metrics = <MapEntry<String, double>>[
      MapEntry(_t('price'), _avgPrice),
      MapEntry(_t('service'), _avgService),
      MapEntry(_t('timing'), _avgTiming),
      MapEntry(_t('work_quality'), _avgWorkQuality),
    ];

    metrics.sort((a, b) => a.value.compareTo(b.value));
    return metrics.first.key;
  }

  Future<void> _fetchAnalytics() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final workerRef = firestore.collection('users').doc(widget.userId);

      final userDoc = await workerRef.get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        _totalJobs = data['totalJobs'] ?? 0;
        _viewsCount = 0;
        _totalEarnings = _asDouble(data['totalEarnings']);
        _overallAvgRating = _asDouble(data['avgRating']);
        _avgRating = _overallAvgRating;
      }

      final reviewsSnapshot = await workerRef.collection('reviews').get();
      final proRatingSnapshot = await workerRef.collection('ProRating').get();

      if (_totalJobs == 0) {
        _totalJobs = reviewsSnapshot.docs.length;
      }

      _professionRatingStats = _buildProfessionStats(
        proRatingSnapshot,
        reviewsSnapshot,
      );

      _professionOptions = _professionRatingStats.keys.toList()..sort();
      if (_professionOptions.isEmpty) {
        _selectedProfession = _allProfessionsKey;
      } else if (_selectedProfession != _allProfessionsKey &&
          !_professionOptions.contains(_selectedProfession)) {
        _selectedProfession = _allProfessionsKey;
      }

      _professionWeeklyViews = await _fetchProfessionWeeklyViews(
        proRatingSnapshot,
      );

      _applyProfessionSelection();

      _conversionRate = _viewsCount > 0
          ? (_totalJobs / _viewsCount) * 100
          : 0.0;

      _performanceOverview = _buildGrowthRecommendation();

      _generateChartData();
    } catch (e) {
      debugPrint('Analytics Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, Map<String, dynamic>> _buildProfessionStats(
    QuerySnapshot<Map<String, dynamic>> proRatingSnapshot,
    QuerySnapshot<Map<String, dynamic>> reviewsSnapshot,
  ) {
    final result = <String, Map<String, dynamic>>{};

    if (proRatingSnapshot.docs.isNotEmpty) {
      for (final doc in proRatingSnapshot.docs) {
        final data = doc.data();
        final profession = (data['profession'] ?? doc.id).toString();
        result[profession] = {
          'totalViews': _asInt(data['totalViews']),
          'reviewCount': data['reviewCount'] ?? 0,
          'avgOverallRating': _asDouble(data['avgOverallRating']),
          'avgPriceRating': _asDouble(data['avgPriceRating']),
          'avgServiceRating': _asDouble(data['avgServiceRating']),
          'avgTimingRating': _asDouble(data['avgTimingRating']),
          'avgWorkQualityRating': _asDouble(data['avgWorkQualityRating']),
        };
      }
      return result;
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final doc in reviewsSnapshot.docs) {
      final data = doc.data();
      final profession = (data['profession'] ?? '').toString().trim();
      if (profession.isEmpty) continue;
      grouped.putIfAbsent(profession, () => []).add(data);
    }

    grouped.forEach((profession, reviews) {
      double overallSum = 0;
      double priceSum = 0;
      double serviceSum = 0;
      double timingSum = 0;
      double workQualitySum = 0;

      for (final review in reviews) {
        final overall = _asDouble(review['rating']);
        final price = _asDouble(
          review['priceRating'] ?? review['starsPrice'],
          fallback: overall,
        );
        final service = _asDouble(
          review['serviceRating'] ??
              review['professionalismRating'] ??
              review['starsService'],
          fallback: overall,
        );
        final timing = _asDouble(
          review['timingRating'] ?? review['starsTiming'],
          fallback: overall,
        );
        final workQuality = _asDouble(
          review['workQualityRating'] ?? review['workRating'],
          fallback: overall,
        );

        overallSum += overall;
        priceSum += price;
        serviceSum += service;
        timingSum += timing;
        workQualitySum += workQuality;
      }

      final count = reviews.length;
      if (count == 0) return;

      result[profession] = {
        'totalViews': 0,
        'reviewCount': count,
        'avgOverallRating': overallSum / count,
        'avgPriceRating': priceSum / count,
        'avgServiceRating': serviceSum / count,
        'avgTimingRating': timingSum / count,
        'avgWorkQualityRating': workQualitySum / count,
      };
    });

    return result;
  }

  void _applyProfessionSelection() {
    _weeklyViewCounts = List.filled(7, 0);

    if (_selectedProfession != _allProfessionsKey &&
        _professionWeeklyViews.containsKey(_selectedProfession)) {
      final selectedViews = _professionWeeklyViews[_selectedProfession]!;
      _weeklyViewCounts = _extractWeekCounts(selectedViews);
    } else if (_professionWeeklyViews.isNotEmpty) {
      for (final map in _professionWeeklyViews.values) {
        final dayCounts = _extractWeekCounts(map);
        for (int i = 0; i < _weeklyViewCounts.length; i++) {
          _weeklyViewCounts[i] += dayCounts[i];
        }
      }
    }

    if (_selectedProfession != _allProfessionsKey &&
        _professionRatingStats.containsKey(_selectedProfession)) {
      final selected = _professionRatingStats[_selectedProfession]!;
      _viewsCount = _asInt(selected['totalViews']);
    } else if (_professionRatingStats.isNotEmpty) {
      _viewsCount = _professionRatingStats.values.fold<int>(
        0,
        (sum, stats) => sum + _asInt(stats['totalViews']),
      );
    } else {
      _viewsCount = 0;
    }

    if (_professionRatingStats.isEmpty) {
      _avgRating = _overallAvgRating;
      _avgPrice = 0.0;
      _avgService = 0.0;
      _avgTiming = 0.0;
      _avgWorkQuality = 0.0;
      _topServices = _t('no_data');
      return;
    }

    if (_selectedProfession != _allProfessionsKey &&
        _professionRatingStats.containsKey(_selectedProfession)) {
      final selected = _professionRatingStats[_selectedProfession]!;
      _avgRating = _asDouble(selected['avgOverallRating']);
      _avgPrice = _asDouble(selected['avgPriceRating']);
      _avgService = _asDouble(selected['avgServiceRating']);
      _avgTiming = _asDouble(selected['avgTimingRating']);
      _avgWorkQuality = _asDouble(selected['avgWorkQualityRating']);
      _topServices = _getHighestRatedProfession();
      return;
    }

    int totalCount = 0;
    double overallWeighted = 0.0;
    double priceWeighted = 0.0;
    double serviceWeighted = 0.0;
    double timingWeighted = 0.0;
    double workQualityWeighted = 0.0;

    _professionRatingStats.forEach((profession, stats) {
      final count = (stats['reviewCount'] ?? 0) as int;
      totalCount += count;
      overallWeighted += _asDouble(stats['avgOverallRating']) * count;
      priceWeighted += _asDouble(stats['avgPriceRating']) * count;
      serviceWeighted += _asDouble(stats['avgServiceRating']) * count;
      timingWeighted += _asDouble(stats['avgTimingRating']) * count;
      workQualityWeighted += _asDouble(stats['avgWorkQualityRating']) * count;
    });

    if (totalCount > 0) {
      _avgRating = overallWeighted / totalCount;
      _avgPrice = priceWeighted / totalCount;
      _avgService = serviceWeighted / totalCount;
      _avgTiming = timingWeighted / totalCount;
      _avgWorkQuality = workQualityWeighted / totalCount;
      _topServices = _getHighestRatedProfession();
    }
  }

  String _getHighestRatedProfession() {
    if (_professionRatingStats.isEmpty) {
      return widget.strings['no_reviews'] ?? 'No data';
    }

    String bestProfession = '';
    double bestRating = -1.0;
    int bestCount = -1;

    _professionRatingStats.forEach((profession, stats) {
      final rating = _asDouble(stats['avgOverallRating']);
      final count = (stats['reviewCount'] ?? 0) as int;

      final isBetterRating = rating > bestRating;
      final isTieButMoreReviews = rating == bestRating && count > bestCount;

      if (isBetterRating || isTieButMoreReviews) {
        bestRating = rating;
        bestCount = count;
        bestProfession = profession;
      }
    });

    return bestProfession.isEmpty ? _t('no_data') : bestProfession;
  }

  void _generateChartData() {
    final base = _totalEarnings / 7;
    _earningsSpots = List.generate(7, (i) {
      final y = (base * (i + 0.5) * (0.8 + (i % 3) * 0.1)).clamp(
        0,
        _totalEarnings * 1.5,
      );
      return FlSpot(i.toDouble(), y.toDouble());
    });

    _viewGroups = List.generate(7, (i) {
      final toY = _weeklyViewCounts[i].toDouble();
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: toY,
            gradient: const LinearGradient(
              colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
            ),
            width: 14,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild this page when app language changes from settings.
    Provider.of<LanguageProvider>(context);

    final isRtl = _localeCode == 'he' || _localeCode == 'ar';

    return FutureBuilder<SubscriptionAccessState>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data?.isUnsubscribedWorker == true) {
          return Directionality(
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            child: SubscriptionAccessService.buildLockedScaffold(
              title: _t('analytics_title'),
              message: isRtl
                  ? 'עמוד האנליטיקה זמין רק לבעלי מנוי Pro פעיל.'
                  : 'Analytics is available only with an active Pro subscription.',
            ),
          );
        }

        if (_isLoading && _totalJobs == 0) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            title: Text(
              _t('analytics_title'),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            foregroundColor: const Color(0xFF0F172A),
          ),
          body: RefreshIndicator(
            onRefresh: _fetchAnalytics,
            color: const Color(0xFF1976D2),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMainBalanceCard(),
                  const SizedBox(height: 24),
                  _buildProfessionSelector(),
                  const SizedBox(height: 24),
                  _buildMetricsGrid(),
                  const SizedBox(height: 32),
                  _buildChartCard(_t('earnings_trend'), _buildEarningsChart()),
                  const SizedBox(height: 24),
                  _buildChartCard(_t('profile_reach'), _buildViewsChart()),
                  const SizedBox(height: 32),
                  _buildSectionHeader(_t('service_quality_breakdown')),
                  const SizedBox(height: 16),
                  _buildRatingsSection(),
                  const SizedBox(height: 32),
                  _buildAITipCard(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfessionSelector() {
    if (_professionOptions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _selectedProfession,
          items: [
            DropdownMenuItem(
              value: _allProfessionsKey,
              child: Text(_t('all_professions')),
            ),
            ..._professionOptions.map(
              (p) => DropdownMenuItem(value: p, child: Text(p)),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedProfession = value;
              _applyProfessionSelection();
              _performanceOverview = _buildGrowthRecommendation();
            });
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1E293B),
      ),
    );
  }

  Widget _buildMainBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _t('total_earnings'),
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: Colors.white30,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '₪${intl.NumberFormat('#,###').format(_totalEarnings)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.visibility_rounded,
                color: Colors.white70,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                '${_t('views_this_week')}: $_weeklyViewsTotal',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white10),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildQuickStat(
                _t('total_jobs'),
                _totalJobs.toString(),
                Icons.check_circle_outline,
              ),
              _buildQuickStat(
                _t('rating'),
                _avgRating.toStringAsFixed(1),
                Icons.star_border_rounded,
              ),
              _buildQuickStat(
                _t('views'),
                _viewsCount.toString(),
                Icons.bar_chart_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStat(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.blueAccent, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildInfoTile(
            _t('conversion'),
            '${_conversionRate.toStringAsFixed(1)}%',
            Icons.swap_calls_rounded,
            Colors.teal,
            helpText: _t('conversion_help'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildInfoTile(
            _t('top_skill'),
            _topServices,
            Icons.auto_graph_rounded,
            Colors.indigo,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTile(
    String title,
    String value,
    IconData icon,
    Color color, {
    String? helpText,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (helpText != null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: helpText,
                  triggerMode: TooltipTriggerMode.tap,
                  waitDuration: Duration.zero,
                  child: Icon(
                    Icons.help_outline_rounded,
                    size: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(String title, Widget chart) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(height: 180, child: chart),
        ],
      ),
    );
  }

  Widget _buildRatingsSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          _buildRatingProgress(_t('price'), _avgPrice, Colors.amber),
          const SizedBox(height: 20),
          _buildRatingProgress(_t('service'), _avgService, Colors.blueAccent),
          const SizedBox(height: 20),
          _buildRatingProgress(_t('timing'), _avgTiming, Colors.greenAccent),
          const SizedBox(height: 20),
          _buildRatingProgress(
            _t('work_quality'),
            _avgWorkQuality,
            Colors.deepPurpleAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildRatingProgress(String label, double value, Color color) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            Text(
              value.toStringAsFixed(1),
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: (value / 5.0).clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildAITipCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.tips_and_updates_rounded,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('growth_recommendation'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _performanceOverview,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsChart() {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: _earningsSpots,
            isCurved: true,
            gradient: const LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
            ),
            barWidth: 6,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF3B82F6).withOpacity(0.3),
                  const Color(0xFF3B82F6).withOpacity(0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dayLabel(int index) {
    final labels = [
      _t('day_sun'),
      _t('day_mon'),
      _t('day_tue'),
      _t('day_wed'),
      _t('day_thu'),
      _t('day_fri'),
      _t('day_sat'),
    ];
    if (index < 0 || index >= labels.length) return '';
    return labels[index];
  }

  Widget _buildViewsChart() {
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _dayLabel(index),
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: _viewGroups,
      ),
    );
  }
}
