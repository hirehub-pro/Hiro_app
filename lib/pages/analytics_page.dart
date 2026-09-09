import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/subscription_access_service.dart';
import 'package:untitled1/utils/top_skill_score.dart';
import 'package:untitled1/utils/growth_recommendation.dart';
import 'package:untitled1/pages/add_project.dart';
import 'package:untitled1/pages/edit_profile.dart';
import 'package:untitled1/pages/my_requests_page.dart';
import 'package:untitled1/pages/schedule.dart';
import 'package:untitled1/widgets/growth_recommendation_card.dart';

class AnalyticsPage extends StatefulWidget {
  final String userId;
  final Map<String, String> strings;

  const AnalyticsPage({super.key, required this.userId, required this.strings});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  static const String _allProfessionsKey = '__all_professions__';
  static const String _analyticsPeriodTotal = '__total__';
  static const String _analyticsPeriodCurrentYear = '__current_year__';
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
  int _viewsCount = 0;
  int _allTimeViewsAcrossProfessions = 0;
  double _totalPayments = 0.0;
  bool _hasPaymentTotalValue = false;
  double _allTimePayments = 0.0;
  bool _hasPaymentAnalytics = false;
  final Map<String, double> _paymentTotals = {};
  double _selectedVatAmount = 0.0;
  bool _hasVatAnalytics = false;
  final Map<String, double> _vatTotals = {};
  double _avgRating = 0.0;
  double _overallAvgRating = 0.0;

  double _avgPrice = 0.0;
  double _avgService = 0.0;
  double _avgTiming = 0.0;
  double _avgWorkQuality = 0.0;

  List<FlSpot> _earningsSpots = [];
  List<BarChartGroupData> _viewGroups = [];
  double _viewsChartMaxY = 1.0;

  Map<String, dynamic> _overallRatingStats = {};
  bool _analyticsAvailable = false;
  Map<String, dynamic> _workerData = {};
  DateTime? _accountCreatedAt;
  Map<String, dynamic>? _growthProfile;
  List<Map<String, dynamic>>? _growthProjects;
  List<Map<String, dynamic>>? _growthRequests;
  List<Map<String, dynamic>>? _growthReviews;
  Map<String, dynamic>? _growthSchedule;
  String _topServices = '';

  List<String> _professionOptions = [];
  List<String> _userProfessions = [];
  String _selectedProfession = _allProfessionsKey;
  Map<String, Map<String, dynamic>> _professionRatingStats = {};
  Map<String, Map<String, int>> _professionWeeklyViews = {};
  List<int> _weeklyViewCounts = List.filled(7, 0);
  int _weeklyViewsTotalValue = 0;
  late String _selectedAnalyticsPeriod;
  late final Future<SubscriptionAccessState> _accessFuture;

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
          'total_earnings': 'תקבולים',
          'vat_amount': 'סכום מע״מ',
          'no_earning_yet': 'אין הכנסות עדיין',
          'rating': 'דירוג',
          'views': 'צפיות',
          'total_views': 'סך הצפיות',
          'total': 'כל הזמנים',
          'current_year': 'השנה הנוכחית',
          'views_this_week': 'צפיות השבוע',
          'top_skill': 'מיומנות מובילה',
          'earnings_trend': 'מגמת הכנסות (7 ימים אחרונים)',
          'profile_reach': 'חשיפה לפרופיל',
          'service_quality_breakdown': 'פירוט איכות השירות',
          'price': 'מחיר',
          'service': 'שירות',
          'timing': 'עמידה בזמנים',
          'work_quality': 'איכות עבודה',
          'growth_recommendation': 'המלצת צמיחה',
          'growth_unavailable': 'לא ניתן לטעון כעת את נתוני המלצת הצמיחה.',
          'growth_retry': 'נסה שוב',
          'no_data': 'אין נתונים',
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
          'total_earnings': 'المدفوعات',
          'vat_amount': 'مبلغ ضريبة القيمة المضافة',
          'no_earning_yet': 'لا توجد أرباح حتى الآن',
          'rating': 'التقييم',
          'views': 'المشاهدات',
          'total_views': 'إجمالي المشاهدات',
          'total': 'كل الوقت',
          'current_year': 'السنة الحالية',
          'views_this_week': 'مشاهدات هذا الأسبوع',
          'top_skill': 'المهارة الأقوى',
          'earnings_trend': 'اتجاه الأرباح (آخر 7 أيام)',
          'profile_reach': 'وصول الملف الشخصي',
          'service_quality_breakdown': 'تفصيل جودة الخدمة',
          'price': 'السعر',
          'service': 'الخدمة',
          'timing': 'الالتزام بالوقت',
          'work_quality': 'جودة العمل',
          'growth_recommendation': 'توصية للنمو',
          'growth_unavailable': 'تعذر تحميل بيانات توصية النمو حالياً.',
          'growth_retry': 'حاول مجدداً',
          'no_data': 'لا توجد بيانات',
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
          'total_earnings': 'Платежи',
          'vat_amount': 'Сумма НДС',
          'no_earning_yet': 'Пока нет дохода',
          'rating': 'Рейтинг',
          'views': 'Просмотры',
          'total_views': 'Всего просмотров',
          'total': 'За всё время',
          'current_year': 'Текущий год',
          'views_this_week': 'Просмотры за неделю',
          'top_skill': 'Лучший навык',
          'earnings_trend': 'Динамика дохода (последние 7 дней)',
          'profile_reach': 'Охват профиля',
          'service_quality_breakdown': 'Показатели качества сервиса',
          'price': 'Цена',
          'service': 'Сервис',
          'timing': 'Сроки',
          'work_quality': 'Качество работы',
          'growth_recommendation': 'Рекомендация по росту',
          'growth_unavailable': 'Не удалось загрузить данные рекомендации.',
          'growth_retry': 'Повторить',
          'no_data': 'Нет данных',
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
          'total_earnings': 'ክፍያዎች',
          'vat_amount': 'የተ.እ.ታ. መጠን',
          'no_earning_yet': 'እስካሁን ምንም ገቢ የለም',
          'rating': 'ደረጃ',
          'views': 'እይታዎች',
          'total_views': 'ጠቅላላ እይታዎች',
          'total': 'ለሁሉም ጊዜ',
          'current_year': 'የአሁኑ ዓመት',
          'views_this_week': 'የዚህ ሳምንት እይታዎች',
          'top_skill': 'ከፍተኛ ችሎታ',
          'earnings_trend': 'የገቢ አቅጣጫ (የመጨረሻ 7 ቀናት)',
          'profile_reach': 'የፕሮፋይል ድርሻ',
          'service_quality_breakdown': 'የአገልግሎት ጥራት ዝርዝር',
          'price': 'ዋጋ',
          'service': 'አገልግሎት',
          'timing': 'ሰዓት',
          'work_quality': 'የስራ ጥራት',
          'growth_recommendation': 'የእድገት ምክር',
          'growth_unavailable': 'የእድገት ምክር መረጃ መጫን አልተቻለም።',
          'growth_retry': 'እንደገና ሞክር',
          'no_data': 'መረጃ የለም',
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
          'total_earnings': 'Payments',
          'vat_amount': 'VAT amount',
          'no_earning_yet': 'No earning yet',
          'rating': 'Rating',
          'views': 'Views',
          'total_views': 'Total Views',
          'total': 'All time',
          'current_year': 'Current year',
          'views_this_week': 'Views This Week',
          'top_skill': 'Top Skill',
          'earnings_trend': 'Earnings Trend (Last 7 Days)',
          'profile_reach': 'Profile Reach',
          'service_quality_breakdown': 'Service Quality Breakdown',
          'price': 'Price',
          'service': 'Service',
          'timing': 'Timing',
          'work_quality': 'Work Quality',
          'growth_recommendation': 'Growth Recommendation',
          'growth_unavailable':
              'Growth insights could not be loaded right now.',
          'growth_retry': 'Try again',
          'no_data': 'No data',
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

  @override
  void initState() {
    super.initState();
    _selectedAnalyticsPeriod = _monthPeriod(DateTime.now().month);
    _accessFuture = SubscriptionAccessService.getCurrentUserState();
    _fetchAnalyticsWhenAuthorized();
  }

  @override
  void reassemble() {
    super.reassemble();
    // New analytics state also needs fetching after a development hot reload.
    _fetchAnalyticsWhenAuthorized();
  }

  Future<void> _fetchAnalyticsWhenAuthorized() async {
    try {
      final access = await _accessFuture;
      if (!access.isUnsubscribedWorker) {
        await _fetchAnalytics();
      }
    } catch (_) {
      // Do not query paid data unless authorization was established.
    }
  }

  double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return fallback;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return fallback;
  }

  DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
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
    };
  }

  List<int> _extractWeekCounts(Map<String, int> map) {
    return _weekDayKeys.map((day) => map[day] ?? 0).toList();
  }

  int _sumWeekCounts(List<int> counts) {
    return counts.fold<int>(0, (sum, value) => sum + value);
  }

  int _weekTotalFromMap(Map<String, int> map) {
    return _sumWeekCounts(_extractWeekCounts(map));
  }

  Map<String, int> _normalizeWeekData(Map<String, dynamic> data) {
    final normalized = _emptyWeekMap();

    final isCurrent =
        data['weekKey'] == _weekKey(DateTime.now()) ||
        _isCurrentWeek(data['weekStart']);
    if (isCurrent) {
      for (final day in _weekDayKeys) {
        normalized[day] = _asInt(data[day]);
      }
    }

    return normalized;
  }

  Map<String, Map<String, int>> _buildProfessionWeeklyViews(
    QuerySnapshot<Map<String, dynamic>> viewsSnapshot,
  ) {
    final result = <String, Map<String, int>>{};

    for (final viewDoc in viewsSnapshot.docs) {
      final data = viewDoc.data();
      if (data['active'] == false) continue;
      final profession = (data['profession'] ?? viewDoc.id).toString();
      result[profession] = _normalizeWeekData(data);
    }

    return result;
  }

  GrowthRecommendation _buildGrowthRecommendation() {
    return buildGrowthRecommendation(
      locale: _localeCode,
      professions: _userProfessions,
      professionRatings: _professionRatingStats,
      professionWeeklyViews: _professionWeeklyViews.map(
        (profession, week) => MapEntry(profession, _weekTotalFromMap(week)),
      ),
      profile: _growthProfile,
      projects: _growthProjects,
      requests: _growthRequests,
      recentReviews: _growthReviews,
      schedule: _growthSchedule,
      overallRatings: _overallRatingStats,
      weeklyViews: _professionWeeklyViews.values.fold<int>(
        0,
        (total, week) => total + _weekTotalFromMap(week),
      ),
      totalViews: _allTimeViewsAcrossProfessions,
      totalPayments: _hasPaymentAnalytics ? _allTimePayments : null,
    );
  }

  // Failed or truncated reads remain unknown; never turn them into zero activity.
  Future<List<Map<String, dynamic>>?> _readGrowthCollection(
    Query<Map<String, dynamic>> query,
    int limit,
  ) async {
    try {
      final snapshot = await query.limit(limit + 1).get();
      if (snapshot.docs.length > limit) return null;
      return snapshot.docs
          .map(
            (doc) => doc.data().map(
              (key, value) =>
                  MapEntry(key, value is Timestamp ? value.toDate() : value),
            ),
          )
          .toList();
    } catch (error) {
      debugPrint('Optional growth signal unavailable: $error');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readGrowthDocument(
    DocumentReference<Map<String, dynamic>> reference,
  ) async {
    try {
      return (await reference.get()).data() ?? <String, dynamic>{};
    } catch (error) {
      debugPrint('Optional growth signal unavailable: $error');
      return null;
    }
  }

  Future<void> _fetchAnalytics() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _analyticsAvailable = false;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final workerRef = firestore.collection('users').doc(widget.userId);
      final publicWorkerRef = firestore
          .collection('publicWorkerProfiles')
          .doc(widget.userId);

      final results = await Future.wait([
        workerRef.get(),
        publicWorkerRef.get(),
      ]);
      final userDoc = results[0];
      final publicWorkerDoc = results[1];
      _workerData = userDoc.data() ?? {};
      _accountCreatedAt = _asDateTime(_workerData['createdAt']);
      _growthProfile = publicWorkerDoc.data();
      if (userDoc.exists) {
        final publicData = publicWorkerDoc.data() ?? <String, dynamic>{};
        _viewsCount = 0;
        _totalPayments = 0;
        _hasPaymentTotalValue = false;
        _overallAvgRating = 0;
        _avgRating = 0;
        if (publicData['professions'] is List) {
          _userProfessions = List<String>.from(
            (publicData['professions'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty),
          );
        } else {
          final single = (publicData['profession'] ?? '').toString().trim();
          _userProfessions = single.isEmpty ? [] : [single];
        }
      }

      final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 60)),
      );
      // Independent reads share the existing authorized fetch, without new indexes.
      await Future.wait<void>([
        () async {
          var snapshot = await workerRef.collection('paymentAnalytics').get();
          final currentYear = DateTime.now().year;
          final hasCurrentYear = snapshot.docs.any(
            (doc) =>
                doc.id == 'current_year' &&
                doc.data()['year'] == currentYear &&
                doc.data()['totalVat'] is num,
          );
          final hasAllTime = snapshot.docs.any(
            (doc) => doc.id == 'all_time' && doc.data()['totalVat'] is num,
          );
          if (!hasCurrentYear || !hasAllTime) {
            try {
              await FirebaseFunctions.instanceFor(
                region: 'me-west1',
              ).httpsCallable('initializePaymentAnalytics').call<void>();
              snapshot = await workerRef.collection('paymentAnalytics').get();
            } catch (error) {
              debugPrint('Payment analytics initialization failed: $error');
            }
          }
          _paymentTotals.clear();
          _vatTotals.clear();
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final periodType = data['periodType'];
            final belongsToCurrentYear =
                periodType == 'all_time' || data['year'] == currentYear;
            if (belongsToCurrentYear && data['totalPayments'] is num) {
              _paymentTotals[doc.id] = (data['totalPayments'] as num)
                  .toDouble();
            }
            if (belongsToCurrentYear && data['totalVat'] is num) {
              _vatTotals[doc.id] = (data['totalVat'] as num).toDouble();
            }
          }
          _hasPaymentAnalytics = snapshot.docs.isNotEmpty;
          _allTimePayments = _paymentTotals['all_time'] ?? 0;
        }(),
        () async {
          _growthProjects = await _readGrowthCollection(
            publicWorkerRef.collection('projects'),
            100,
          );
        }(),
        () async {
          _growthRequests = await _readGrowthCollection(
            workerRef
                .collection('RequestToMe')
                .where('timestamp', isGreaterThanOrEqualTo: cutoff),
            500,
          );
        }(),
        () async {
          _growthReviews = await _readGrowthCollection(
            publicWorkerRef
                .collection('reviews')
                .where('timestamp', isGreaterThanOrEqualTo: cutoff),
            500,
          );
        }(),
        () async {
          _growthSchedule = await _readGrowthDocument(
            publicWorkerRef.collection('Schedule').doc('info'),
          );
        }(),
      ]);

      _applyPaymentPeriodSelection();

      final reviewStatsSnapshot = await publicWorkerRef
          .collection('ReviewStats')
          .get();
      final viewsSnapshot = await publicWorkerRef.collection('Views').get();

      _overallRatingStats = {};
      for (final statsDoc in reviewStatsSnapshot.docs) {
        if (statsDoc.id != 'overall') continue;
        final overallStats = statsDoc.data();
        _overallRatingStats = overallStats;
        _overallAvgRating = _asDouble(overallStats['avgOverallRating']);
        _avgRating = _overallAvgRating;
        break;
      }

      _professionRatingStats = _buildProfessionStats(reviewStatsSnapshot);
      _allTimeViewsAcrossProfessions = 0;
      for (final viewDoc in viewsSnapshot.docs) {
        final data = viewDoc.data();
        _allTimeViewsAcrossProfessions += _asInt(data['totalViews']);
        if (data['active'] == false) continue;
        final profession = (data['profession'] ?? viewDoc.id).toString().trim();
        if (profession.isEmpty) continue;
        final stats = _professionRatingStats.putIfAbsent(profession, () {
          return {
            'totalViews': 0,
            'reviewCount': 0,
            'avgOverallRating': 0.0,
            'avgPriceRating': 0.0,
            'avgServiceRating': 0.0,
            'avgTimingRating': 0.0,
            'avgWorkQualityRating': 0.0,
          };
        });
        stats['totalViews'] = _asInt(data['totalViews']);
      }

      final optionSet = <String>{
        ..._professionRatingStats.keys
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
        ..._userProfessions.map((e) => e.trim()).where((e) => e.isNotEmpty),
      };
      _professionOptions = optionSet.toList()..sort();

      for (final profession in _professionOptions) {
        _professionRatingStats.putIfAbsent(profession, () {
          return {
            'totalViews': 0,
            'reviewCount': 0,
            'avgOverallRating': 0.0,
            'avgPriceRating': 0.0,
            'avgServiceRating': 0.0,
            'avgTimingRating': 0.0,
            'avgWorkQualityRating': 0.0,
          };
        });
      }
      if (_professionOptions.isEmpty) {
        _selectedProfession = _allProfessionsKey;
      } else if (_selectedProfession != _allProfessionsKey &&
          !_professionOptions.contains(_selectedProfession)) {
        _selectedProfession = _allProfessionsKey;
      }

      _professionWeeklyViews = _buildProfessionWeeklyViews(viewsSnapshot);

      _applyProfessionSelection();

      _analyticsAvailable = true;

      _generateChartData();
    } catch (e) {
      debugPrint('Analytics Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, Map<String, dynamic>> _buildProfessionStats(
    QuerySnapshot<Map<String, dynamic>> reviewStatsSnapshot,
  ) {
    final result = <String, Map<String, dynamic>>{};

    for (final doc in reviewStatsSnapshot.docs) {
      final data = doc.data();
      if (doc.id == 'overall' || data['scope'] != 'profession') continue;
      final profession = (data['profession'] ?? '').toString().trim();
      if (profession.isEmpty) continue;
      result[profession] = {
        'totalViews': 0,
        'reviewCount': _asInt(data['reviewCount']),
        'avgOverallRating': _asDouble(data['avgOverallRating']),
        'avgPriceRating': _asDouble(data['avgPriceRating']),
        'avgServiceRating': _asDouble(data['avgServiceRating']),
        'avgTimingRating': _asDouble(data['avgTimingRating']),
        'avgWorkQualityRating': _asDouble(data['avgWorkQualityRating']),
      };
    }

    return result;
  }

  void _applyProfessionSelection() {
    _weeklyViewCounts = List.filled(7, 0);
    _weeklyViewsTotalValue = 0;

    if (_selectedProfession != _allProfessionsKey &&
        _professionWeeklyViews.containsKey(_selectedProfession)) {
      final selectedViews = _professionWeeklyViews[_selectedProfession]!;
      _weeklyViewCounts = _extractWeekCounts(selectedViews);
      _weeklyViewsTotalValue = _weekTotalFromMap(selectedViews);
    } else if (_professionWeeklyViews.isNotEmpty) {
      for (final map in _professionWeeklyViews.values) {
        final dayCounts = _extractWeekCounts(map);
        for (int i = 0; i < _weeklyViewCounts.length; i++) {
          _weeklyViewCounts[i] += dayCounts[i];
        }
        _weeklyViewsTotalValue += _weekTotalFromMap(map);
      }
    }

    if (_selectedProfession != _allProfessionsKey &&
        _professionRatingStats.containsKey(_selectedProfession)) {
      final selected = _professionRatingStats[_selectedProfession]!;
      _viewsCount = _asInt(selected['totalViews']);
    } else {
      _viewsCount = _allTimeViewsAcrossProfessions;
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
    } else {
      _avgRating = 0;
      _avgPrice = 0;
      _avgService = 0;
      _avgTiming = 0;
      _avgWorkQuality = 0;
      _topServices = _t('no_data');
    }
  }

  String _getHighestRatedProfession() {
    if (_professionRatingStats.isEmpty) {
      return widget.strings['no_reviews'] ?? 'No data';
    }

    String bestProfession = '';
    double bestScore = -1.0;
    int bestCount = -1;

    _professionRatingStats.forEach((profession, stats) {
      final rating = _asDouble(stats['avgOverallRating']);
      final count = (stats['reviewCount'] ?? 0) as int;
      if (count <= 0) return;

      final score = calculateTopSkillScore(
        averageRating: rating,
        reviewCount: count,
      );

      final isBetterScore = score > bestScore;
      final isTieButMoreReviews = score == bestScore && count > bestCount;

      if (isBetterScore || isTieButMoreReviews) {
        bestScore = score;
        bestCount = count;
        bestProfession = profession;
      }
    });

    return bestProfession.isEmpty ? _t('no_data') : bestProfession;
  }

  void _generateChartData() {
    final chartTotal = _totalPayments.abs();
    final base = chartTotal / 7;
    final maxY = chartTotal <= 0 ? 1.0 : chartTotal * 1.5;
    _earningsSpots = List.generate(7, (i) {
      final y = (base * (i + 0.5) * (0.8 + (i % 3) * 0.1)).clamp(0.0, maxY);
      return FlSpot(i.toDouble(), y.toDouble());
    });

    final highestViewCount = _weeklyViewCounts.fold<int>(
      0,
      (highest, viewCount) => viewCount > highest ? viewCount : highest,
    );
    _viewsChartMaxY = highestViewCount > 0 ? highestViewCount * 1.1 : 1.0;
    final zeroViewLineHeight = _viewsChartMaxY * 0.035;

    _viewGroups = List.generate(7, (i) {
      final viewCount = _weeklyViewCounts[i];
      final toY = viewCount == 0 ? zeroViewLineHeight : viewCount.toDouble();
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

        if (_isLoading) {
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
            onRefresh: _fetchAnalyticsWhenAuthorized,
            color: const Color(0xFF1976D2),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMainBalanceCard(),
                  const SizedBox(height: 24),
                  _buildMetricsGrid(),
                  const SizedBox(height: 24),
                  _buildProfessionSelector(),
                  const SizedBox(height: 16),
                  _buildViewsAndRatingCard(),
                  const SizedBox(height: 32),
                  _buildChartCard(_t('profile_reach'), _buildViewsChart()),
                  const SizedBox(height: 32),
                  _buildSectionHeader(_t('service_quality_breakdown')),
                  const SizedBox(height: 16),
                  _buildRatingsSection(),
                  const SizedBox(height: 32),
                  _buildGrowthTipCard(),
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
              _generateChartData();
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
            _hasPaymentTotalValue
                ? '₪${intl.NumberFormat('#,###').format(_totalPayments)}'
                : _t('no_earning_yet'),
            style: TextStyle(
              color: Colors.white,
              fontSize: _hasPaymentTotalValue ? 38 : 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _t('vat_amount'),
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₪${intl.NumberFormat('#,##0.##').format(_selectedVatAmount)}',
            style: TextStyle(
              color: _hasVatAnalytics ? Colors.white : Colors.white54,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          _buildAnalyticsMonthSelector(),
        ],
      ),
    );
  }

  Widget _buildViewsAndRatingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _buildQuickStat(
              _t('total_views'),
              _viewsCount.toString(),
              Icons.bar_chart_rounded,
            ),
          ),
          Expanded(
            child: _buildQuickStat(
              _t('views_this_week'),
              _weeklyViewsTotalValue.toString(),
              Icons.visibility_rounded,
            ),
          ),
          Expanded(
            child: _buildQuickStat(
              _t('rating'),
              _avgRating.toStringAsFixed(1),
              Icons.star_border_rounded,
            ),
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
            Flexible(
              child: Text(
                label,
                softWrap: true,
                overflow: TextOverflow.visible,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
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

  Widget _buildAnalyticsMonthSelector() {
    final now = DateTime.now();
    final joinedThisYear = _accountCreatedAt?.year == now.year;
    final firstVisibleMonth = joinedThisYear
        ? _accountCreatedAt!.month.clamp(1, now.month)
        : 1;
    final months = List<int>.generate(
      now.month - firstVisibleMonth + 1,
      (index) => firstVisibleMonth + index,
    );
    final periods = <DropdownMenuItem<String>>[
      DropdownMenuItem(value: _analyticsPeriodTotal, child: Text(_t('total'))),
      DropdownMenuItem(
        value: _analyticsPeriodCurrentYear,
        child: Text(_t('current_year')),
      ),
      ...months.map(
        (month) => DropdownMenuItem<String>(
          value: _monthPeriod(month),
          child: Text(_monthName(month)),
        ),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.calendar_month_outlined,
            color: Colors.white70,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedAnalyticsPeriod,
                isExpanded: true,
                dropdownColor: const Color(0xFF1E293B),
                iconEnabledColor: Colors.white70,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                items: periods,
                onChanged: (period) {
                  if (period == null) return;
                  setState(() {
                    _selectedAnalyticsPeriod = period;
                    _applyPaymentPeriodSelection();
                    _generateChartData();
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _monthPeriod(int month) => 'month_$month';

  String _paymentAnalyticsDocumentId(String period) {
    if (period == _analyticsPeriodTotal) return 'all_time';
    if (period == _analyticsPeriodCurrentYear) return 'current_year';
    final month = int.tryParse(period.replaceFirst('month_', ''));
    if (month == null || month < 1 || month > 12) return 'all_time';
    return 'month_${month.toString().padLeft(2, '0')}';
  }

  void _applyPaymentPeriodSelection() {
    final documentId = _paymentAnalyticsDocumentId(_selectedAnalyticsPeriod);
    _selectedVatAmount = _vatTotals[documentId] ?? 0;
    _hasVatAnalytics = _vatTotals.containsKey(documentId);
    if (!_hasPaymentAnalytics) return;
    _totalPayments = _paymentTotals[documentId] ?? 0;
    _hasPaymentTotalValue = _paymentTotals.containsKey(documentId);
  }

  String _monthName(int month) {
    const monthNames = {
      'he': [
        'ינואר',
        'פברואר',
        'מרץ',
        'אפריל',
        'מאי',
        'יוני',
        'יולי',
        'אוגוסט',
        'ספטמבר',
        'אוקטובר',
        'נובמבר',
        'דצמבר',
      ],
      'ar': [
        'يناير',
        'فبراير',
        'مارس',
        'أبريل',
        'مايو',
        'يونيو',
        'يوليو',
        'أغسطس',
        'سبتمبر',
        'أكتوبر',
        'نوفمبر',
        'ديسمبر',
      ],
      'ru': [
        'Январь',
        'Февраль',
        'Март',
        'Апрель',
        'Май',
        'Июнь',
        'Июль',
        'Август',
        'Сентябрь',
        'Октябрь',
        'Ноябрь',
        'Декабрь',
      ],
      'am': [
        'ጃንዩወሪ',
        'ፌብሩወሪ',
        'ማርች',
        'ኤፕሪል',
        'ሜይ',
        'ጁን',
        'ጁላይ',
        'ኦገስት',
        'ሴፕቴምበር',
        'ኦክቶበር',
        'ኖቬምበር',
        'ዲሴምበር',
      ],
      'en': [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ],
    };
    return (monthNames[_localeCode] ?? monthNames['en']!)[month - 1];
  }

  Widget _buildMetricsGrid() {
    return _buildInfoTile(
      _t('top_skill'),
      _topServices,
      Icons.auto_graph_rounded,
      Colors.indigo,
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
            value: (value / 10.0).clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Future<void> _openGrowthAction(GrowthDestination destination) async {
    final Widget page = switch (destination) {
      GrowthDestination.profile => EditProfilePage(userData: _workerData),
      GrowthDestination.portfolio => const AddProjectPage(),
      GrowthDestination.availability => SchedulePage(
        workerId: widget.userId,
        workerName: (_workerData['name'] ?? '').toString(),
      ),
      GrowthDestination.requests => const MyRequestsPage(initialTab: 1),
    };
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _fetchAnalyticsWhenAuthorized();
  }

  Widget _buildGrowthTipCard() {
    if (!_analyticsAvailable) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('growth_recommendation'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_t('growth_unavailable')),
              TextButton(
                onPressed: _fetchAnalyticsWhenAuthorized,
                child: Text(_t('growth_retry')),
              ),
            ],
          ),
        ),
      );
    }
    final tip = _buildGrowthRecommendation();
    return GrowthRecommendationCard(
      title: _t('growth_recommendation'),
      recommendation: tip,
      isRtl: _localeCode == 'he' || _localeCode == 'ar',
      onAction: tip.destination == null
          ? null
          : () => _openGrowthAction(tip.destination!),
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
        maxY: _viewsChartMaxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final dayIndex = group.x;
              final actualViews =
                  dayIndex >= 0 && dayIndex < _weeklyViewCounts.length
                  ? _weeklyViewCounts[dayIndex]
                  : 0;
              return BarTooltipItem(
                actualViews.toString(),
                const TextStyle(
                  color: Color(0xFFF59E0B),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              );
            },
          ),
        ),
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
