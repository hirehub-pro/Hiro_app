import 'package:intl/intl.dart';
import 'package:untitled1/utils/request_expiration.dart';
import 'package:untitled1/utils/top_skill_score.dart';

enum GrowthDestination { profile, portfolio, availability, requests }

class GrowthRecommendation {
  final String scope;
  final String summary;
  final String actionLabel;
  final String action;
  final String reason;
  final GrowthDestination? destination;
  final String? ctaLabel;

  const GrowthRecommendation({
    required this.scope,
    required this.summary,
    required this.actionLabel,
    required this.action,
    required this.reason,
    this.destination,
    this.ctaLabel,
  });
}

class _Opportunity {
  final String reason;
  final int priority;
  final Map<String, String> evidence;
  final String actionKey;
  final GrowthDestination? destination;
  const _Opportunity(
    this.reason,
    this.priority,
    this.evidence,
    this.actionKey, [
    this.destination,
  ]);
}

/// Uses known signals only. Null optional sources mean unavailable, not zero.
/// Overall totals are never added to their profession breakdowns.
/// Requests are in-app request records, not all leads or completed jobs.
GrowthRecommendation buildGrowthRecommendation({
  required String locale,
  required List<String> professions,
  required Map<String, dynamic> overallRatings,
  required int weeklyViews,
  required int totalViews,
  required double? totalPayments,
  Map<String, Map<String, dynamic>> professionRatings = const {},
  Map<String, int> professionWeeklyViews = const {},
  Map<String, dynamic>? profile,
  List<Map<String, dynamic>>? projects,
  List<Map<String, dynamic>>? requests,
  List<Map<String, dynamic>>? recentReviews,
  Map<String, dynamic>? schedule,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final copy = _decisionCopy[locale] ?? _decisionCopy['en']!;
  final legacy = _copy[locale] ?? _copy['en']!;
  String t(String key, [Map<String, String> params = const {}]) {
    var result = copy[key] ?? legacy[key]!;
    params.forEach((key, value) => result = result.replaceAll('{$key}', value));
    return result;
  }

  String numeric(num n) => '\u2068${NumberFormat('#,##0.#').format(n)}\u2069';
  String ratingText(double n) => '\u2068${n.toStringAsFixed(1)}/10\u2069';
  final listed = professions
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toSet();
  if (overallRatings.isEmpty && professionRatings.isNotEmpty) {
    // Fallback only when the overall document is absent. Never add both scopes.
    final validStats = professionRatings.values
        .where(
          (stats) =>
              _number(stats['reviewCount']) > 0 &&
              _rating(stats['avgOverallRating']) != null,
        )
        .toList();
    final total = validStats.fold<double>(
      0,
      (v, stats) => v + _number(stats['reviewCount']),
    );
    if (total > 0) {
      overallRatings = {
        'reviewCount': total,
        for (final key in [
          'avgOverallRating',
          'avgPriceRating',
          'avgServiceRating',
          'avgTimingRating',
          'avgWorkQualityRating',
        ])
          key: validStats.every((stats) => _rating(stats[key]) != null)
              ? validStats.fold<double>(
                      0,
                      (v, stats) =>
                          v +
                          _number(stats[key]) * _number(stats['reviewCount']),
                    ) /
                    total
              : null,
      };
    }
  }
  final count = _number(overallRatings['reviewCount']).toInt();
  final overall = _rating(overallRatings['avgOverallRating']);
  final opportunities = <_Opportunity>[];
  void add(
    String reason,
    int priority,
    Map<String, String> evidence,
    String action, [
    GrowthDestination? destination,
  ]) {
    opportunities.add(
      _Opportunity(reason, priority, evidence, action, destination),
    );
  }

  final day = DateTime(clock.year, clock.month, clock.day);
  final weekStart = day.subtract(Duration(days: day.weekday % 7));
  final monthStart = clock.subtract(const Duration(days: 30));
  final knownRequests = requests?.where((r) {
    final date = _date(r['timestamp']);
    return ['work_request', 'quote_request'].contains(r['type']) &&
        date != null &&
        !date.isBefore(clock.subtract(const Duration(days: 60))) &&
        !date.isAfter(clock);
  }).toList();
  final weeklyRequests = knownRequests
      ?.where((r) => !_date(r['timestamp'])!.isBefore(weekStart))
      .toList();
  final monthRequests = knownRequests
      ?.where((r) => !_date(r['timestamp'])!.isBefore(monthStart))
      .toList();
  final waiting = knownRequests
      ?.where(
        (r) =>
            ['pending', 'waiting_for_approval'].contains(r['status']) &&
            clock.difference(_date(r['timestamp'])!).inHours >= 48 &&
            !isPendingRequestExpired(r, now: clock),
      )
      .toList();
  if (waiting != null && waiting.isNotEmpty) {
    add(
      'pending',
      100,
      {'count': numeric(waiting.length)},
      'pending_action',
      GrowthDestination.requests,
    );
  }

  // An accepted quote is a quote sent, not a booking. Examine work requests only.
  final matureWork = monthRequests
      ?.where(
        (r) =>
            r['type'] == 'work_request' &&
            clock.difference(_date(r['timestamp'])!).inDays >= 2,
      )
      .toList();
  final lostWork = matureWork
      ?.where(
        (r) => ['declined', 'rejected', 'cancelled'].contains(r['status']),
      )
      .length;
  if (matureWork != null &&
      matureWork.length >= 10 &&
      lostWork! >= 3 &&
      lostWork / matureWork.length >= .3) {
    add(
      'lost_requests',
      94,
      {'lost': numeric(lostWork), 'count': numeric(matureWork.length)},
      'lost_action',
      GrowthDestination.requests,
    );
  }

  // Compare the worker's own category scores; these are editorial evidence
  // thresholds, not market benchmarks. Never diagnose from one perfect review.
  void considerQuality(Map<String, dynamic> stats, String scope, int priority) {
    final n = _number(stats['reviewCount']).toInt();
    if (n < 5) return;
    final metrics =
        <String, double?>{
            'price': _rating(stats['avgPriceRating']),
            'service': _rating(stats['avgServiceRating']),
            'timing': _rating(stats['avgTimingRating']),
            'work': _rating(stats['avgWorkQualityRating']),
          }.entries.where((e) => e.value != null).toList()
          ..sort((a, b) => a.value!.compareTo(b.value!));
    if (metrics.length < 2) return;
    final low = metrics.first;
    final peers =
        metrics.skip(1).fold<double>(0, (v, e) => v + e.value!) /
        (metrics.length - 1);
    if (low.value! > 8 || peers - low.value! < 1) return;
    add('quality', priority, {
      'scope': scope,
      'metric': t('metric_${low.key}'),
      'rating': ratingText(low.value!),
      'other': ratingText(peers),
      'count': numeric(n),
    }, 'improve_${low.key}');
  }

  considerQuality(overallRatings, t('business'), 90);
  final rated = professionRatings.entries
      .where(
        (e) =>
            listed.contains(e.key) &&
            _number(e.value['reviewCount']) > 0 &&
            _rating(e.value['avgOverallRating']) != null,
      )
      .toList();
  for (final entry in rated) {
    considerQuality(entry.value, entry.key, 89);
  }
  rated.sort((a, b) {
    double score(Map<String, dynamic> s) => calculateTopSkillScore(
      averageRating: _rating(s['avgOverallRating'])!,
      reviewCount: _number(s['reviewCount']).toInt(),
    );
    final comparison = score(b.value).compareTo(score(a.value));
    return comparison != 0 ? comparison : a.key.compareTo(b.key);
  });
  final strongest = rated.isEmpty ? null : rated.first;

  // Dated review cohorts are not historical snapshots of the overall rating.
  if (recentReviews != null) {
    final recent = <double>[];
    final previous = <double>[];
    for (final review in recentReviews) {
      final date = _date(review['timestamp']);
      final rating = _rating(review['rating']);
      if (date == null || rating == null || date.isAfter(clock)) continue;
      final age = clock.difference(date).inDays;
      if (age < 30) {
        recent.add(rating);
      } else if (age < 60) {
        previous.add(rating);
      }
    }
    double average(List<double> values) =>
        values.reduce((a, b) => a + b) / values.length;
    if (recent.length >= 5 &&
        previous.length >= 5 &&
        average(previous) - average(recent) >= 1) {
      add('recent_quality', 91, {
        'recent': ratingText(average(recent)),
        'previous': ratingText(average(previous)),
        'count': numeric(recent.length),
        'previousCount': numeric(previous.length),
      }, 'improve_overall');
    }
  }

  // A small portfolio is known only after a successful project read. Projects
  // have no profession tags: never invent a per-profession project count.
  final projectCount = projects
      ?.where(
        (p) =>
            (p['imageUrls'] is List && (p['imageUrls'] as List).isNotEmpty) ||
            (p['imageUrl'] is String &&
                (p['imageUrl'] as String).trim().isNotEmpty),
      )
      .length;
  final strongOverall = count >= 5 && overall != null && overall >= 9;
  if (projectCount != null &&
      projectCount < 3 &&
      weeklyViews >= 30 &&
      weeklyRequests != null &&
      weeklyRequests.length <= 2 &&
      strongOverall) {
    add(
      'portfolio_conversion',
      85,
      {
        'views': numeric(weeklyViews),
        'requests': numeric(weeklyRequests.length),
        'rating': ratingText(overall),
        'projects': numeric(projectCount),
      },
      'portfolio_action',
      GrowthDestination.portfolio,
    );
  }

  if (projectCount != null && projectCount < 3 && weeklyRequests != null) {
    for (final profession in rated) {
      final views = professionWeeklyViews[profession.key];
      final n = _number(profession.value['reviewCount']).toInt();
      final rating = _rating(profession.value['avgOverallRating'])!;
      final inquiries = weeklyRequests
          .where((r) => r['profession'] == profession.key)
          .length;
      if (views != null &&
          views >= 30 &&
          inquiries <= 2 &&
          n >= 5 &&
          rating >= 9) {
        add(
          'profession_portfolio',
          86,
          {
            'profession': profession.key,
            'views': numeric(views),
            'requests': numeric(inquiries),
            'rating': ratingText(rating),
            'count': numeric(n),
            'projects': numeric(projectCount),
          },
          'profession_portfolio_action',
          GrowthDestination.portfolio,
        );
      }
    }
  }
  if (projects != null &&
      projectCount != null &&
      projectCount >= 3 &&
      weeklyViews >= 30 &&
      weeklyRequests != null &&
      weeklyRequests.length <= 2) {
    final dates = projects
        .map((p) => _date(p['timestamp']))
        .whereType<DateTime>()
        .toList();
    if (dates.length == projects.length &&
        dates.every(
          (d) => d.isBefore(clock.subtract(const Duration(days: 180))),
        )) {
      add(
        'old_portfolio',
        82,
        {
          'views': numeric(weeklyViews),
          'requests': numeric(weeklyRequests.length),
        },
        'old_portfolio_action',
        GrowthDestination.portfolio,
      );
    }
  }

  // Explicit calendar dates follow SchedulePage; do not equate dates with slots.
  // Respect deliberate hidden schedules, vacations and disabled days.
  final availableDays = _availableDays(schedule, clock);
  if (availableDays == 0 &&
      schedule?['hideSchedule'] != true &&
      (monthRequests?.length ?? 0) >= 3 &&
      !_hasUpcomingVacation(schedule, clock)) {
    add(
      'availability',
      84,
      {'count': numeric(monthRequests!.length)},
      'availability_action',
      GrowthDestination.availability,
    );
  }

  if (strongest != null &&
      weeklyViews >= 20 &&
      _number(strongest.value['reviewCount']) >= 10 &&
      _rating(strongest.value['avgOverallRating'])! >= 9 &&
      professionWeeklyViews.containsKey(strongest.key)) {
    final topViews = professionWeeklyViews[strongest.key]!;
    final otherViews = professionWeeklyViews.entries
        .where((e) => e.key != strongest.key && listed.contains(e.key))
        .fold<int>(0, (v, e) => v + e.value);
    if (topViews * 3 < otherViews) {
      add(
        'strength_visibility',
        72,
        {
          'profession': strongest.key,
          'rating': ratingText(_rating(strongest.value['avgOverallRating'])!),
          'count': numeric(_number(strongest.value['reviewCount']).toInt()),
          'views': numeric(topViews),
          'otherViews': numeric(otherViews),
        },
        'strength_action',
        GrowthDestination.portfolio,
      );
    }
  }

  // At very low observed activity, build evidence rather than diagnosing a
  // conversion problem. Targets are checkpoints, not promised view counts.
  if (totalViews < 20 && count < 5) {
    add(
      'small_sample',
      75,
      {'views': numeric(totalViews), 'count': numeric(count)},
      projectCount != null && projectCount == 0
          ? 'sample_portfolio_action'
          : 'sample_action',
      projectCount != null && projectCount == 0
          ? GrowthDestination.portfolio
          : null,
    );
  }
  if (projectCount != null && projectCount < 3 && weeklyViews >= 10) {
    add(
      'portfolio',
      62,
      {'projects': numeric(projectCount), 'views': numeric(weeklyViews)},
      'portfolio_action',
      GrowthDestination.portfolio,
    );
  }

  if (profile != null) {
    final gaps = <String, String>{
      if (listed.isEmpty) 'professions': 'add_professions',
      if ((profile['description'] ?? '').toString().trim().isEmpty)
        'description': 'description_action',
      if ((profile['profileImageUrl'] ?? '').toString().trim().isEmpty)
        'photo': 'photo_action',
      if ((profile['town'] ?? '').toString().trim().isEmpty)
        'location': 'location_action',
    };
    if (gaps.isNotEmpty) {
      final gap = gaps.entries.first;
      add(
        'profile_gap',
        listed.isEmpty ? 80 : 50,
        {'field': t('field_${gap.key}')},
        gap.value,
        GrowthDestination.profile,
      );
    }
  }

  // Payment totals cannot establish current revenue or job volume.
  // Use recorded payments only as context for building customer feedback.
  if (totalPayments != null &&
      totalPayments.isFinite &&
      totalPayments > 0 &&
      count < 5) {
    add('earnings_feedback', 60, {
      'amount': numeric(totalPayments),
      'count': numeric(count),
    }, 'feedback_action');
  }
  if (recentReviews != null &&
      count >= 5 &&
      (monthRequests
                  ?.where(
                    (r) =>
                        r['type'] == 'work_request' &&
                        r['status'] == 'accepted',
                  )
                  .length ??
              0) >=
          3 &&
      !recentReviews.any(
        (r) =>
            _date(r['timestamp']) != null &&
            !_date(r['timestamp'])!.isBefore(monthStart) &&
            !_date(r['timestamp'])!.isAfter(clock),
      )) {
    add('review_recency', 61, {}, 'feedback_action');
  }

  // Show a positive fallback only when every source needed for the claim was
  // loaded and each key business area has enough evidence. This describes
  // agreement between current signals, not a historical growth trend.
  final overallCategories = [
    _rating(overallRatings['avgPriceRating']),
    _rating(overallRatings['avgServiceRating']),
    _rating(overallRatings['avgTimingRating']),
    _rating(overallRatings['avgWorkQualityRating']),
  ];
  final professionEvidenceIsHealthy =
      listed.isNotEmpty &&
      listed.every((profession) {
        final stats = professionRatings[profession];
        return stats != null &&
            _number(stats['reviewCount']) >= 5 &&
            (_rating(stats['avgOverallRating']) ?? 0) >= 8.5;
      });
  final hasRecentProject =
      projects != null &&
      projects.any((project) {
        final timestamp = _date(project['timestamp']);
        return timestamp != null &&
            !timestamp.isAfter(clock) &&
            !timestamp.isBefore(clock.subtract(const Duration(days: 180)));
      });
  final recentWorkRequests = monthRequests
      ?.where((request) => request['type'] == 'work_request')
      .toList();
  final acceptedWorkRequests = recentWorkRequests
      ?.where((request) => request['status'] == 'accepted')
      .length;
  final lostRecentWorkRequests = recentWorkRequests
      ?.where(
        (request) =>
            ['declined', 'rejected', 'cancelled'].contains(request['status']),
      )
      .length;
  final requestsAreHealthy =
      recentWorkRequests != null &&
      recentWorkRequests.length >= 5 &&
      (acceptedWorkRequests ?? 0) >= 3 &&
      (lostRecentWorkRequests ?? 0) / recentWorkRequests.length <= 0.2 &&
      waiting != null &&
      waiting.isEmpty;
  final allCoreSignalsAreHealthy =
      count >= 10 &&
      (overall ?? 0) >= 9 &&
      overallCategories.every((rating) => rating != null && rating >= 8.5) &&
      professionEvidenceIsHealthy &&
      projectCount != null &&
      projectCount >= 3 &&
      hasRecentProject &&
      availableDays != null &&
      availableDays >= 2 &&
      requestsAreHealthy;
  if (allCoreSignalsAreHealthy) {
    add(
      'healthy_performance',
      1,
      {
        'rating': ratingText(overall!),
        'count': numeric(count),
        'projects': numeric(projectCount),
        'availability': numeric(availableDays),
        'accepted': numeric(acceptedWorkRequests!),
        'requests': numeric(recentWorkRequests.length),
      },
      'healthy_action',
      GrowthDestination.requests,
    );
  }

  // Repeat senders indicate recurring inquiry interest, not completed repeat jobs.
  if (knownRequests != null && strongOverall) {
    final senderCounts = <String, int>{};
    for (final request in knownRequests) {
      final id = (request['fromId'] ?? '').toString().trim();
      if (id.isNotEmpty) senderCounts[id] = (senderCounts[id] ?? 0) + 1;
    }
    final repeated = senderCounts.values.where((n) => n >= 2).length;
    if (repeated >= 2) {
      add(
        'repeat_interest',
        35,
        {'count': numeric(repeated)},
        'repeat_action',
        GrowthDestination.requests,
      );
    }
  }

  add('data_building', 0, {}, 'data_action');
  opportunities.sort((a, b) {
    final priority = b.priority.compareTo(a.priority);
    return priority != 0 ? priority : a.reason.compareTo(b.reason);
  });
  final chosen = opportunities.first;
  return GrowthRecommendation(
    scope: t('all_business'),
    summary: t(chosen.reason, chosen.evidence),
    actionLabel: t('next_step'),
    action: t(chosen.actionKey, chosen.evidence),
    reason: chosen.reason,
    destination: chosen.destination,
    ctaLabel: chosen.destination == null
        ? null
        : t('cta_${chosen.destination!.name}'),
  );
}

double _number(dynamic value) =>
    value is num && value.isFinite ? value.toDouble() : 0;
double? _rating(dynamic value) {
  final n = _number(value);
  return n >= 1 && n <= 10 ? n : null;
}

DateTime? _date(dynamic value) {
  if (value is DateTime) return value;
  if (value is! String) return null;
  // Calendar uses unpadded YYYY-M-D strings.
  final parts = value.split('-');
  if (parts.length == 3 && parts.every((p) => int.tryParse(p) != null)) {
    final y = int.parse(parts[0]),
        m = int.parse(parts[1]),
        d = int.parse(parts[2]);
    final date = DateTime(y, m, d);
    return date.year == y && date.month == m && date.day == d ? date : null;
  }
  return DateTime.tryParse(value);
}

bool _hasUpcomingVacation(Map<String, dynamic>? schedule, DateTime now) {
  final vacations = schedule?['vacations'];
  if (vacations is! List) return false;
  return vacations.whereType<Map>().any((v) {
    final start = _date(v['start']), end = _date(v['end']);
    return start != null &&
        end != null &&
        !end.isBefore(DateTime(now.year, now.month, now.day)) &&
        start.isBefore(now.add(const Duration(days: 14)));
  });
}

int? _availableDays(Map<String, dynamic>? schedule, DateTime now) {
  if (schedule == null || schedule['availableDates'] is! List) return null;
  final today = DateTime(now.year, now.month, now.day);
  final disabled = schedule['disabledDays'] is List
      ? schedule['disabledDays'] as List
      : const [];
  return (schedule['availableDates'] as List)
      .map(_date)
      .whereType<DateTime>()
      .toSet()
      .where(
        (d) =>
            !d.isBefore(today) &&
            d.isBefore(today.add(const Duration(days: 14))) &&
            !disabled.contains(d.weekday % 7 + 1),
      )
      .length;
}

const _copy = <String, Map<String, String>>{
  'en': {
    'next_step': 'Your next step',
    'add_professions':
        'Add the professions you currently offer and explain what customers can book.',
    'improve_price':
        'Price is your lowest-rated area. Before the next job, agree on a clear quote and explain what it includes.',
    'improve_service':
        'Service is your lowest-rated area. For the next job, confirm the customer’s expectations and keep them updated.',
    'improve_timing':
        'Timing is your lowest-rated area. Agree on a realistic arrival and completion time, and communicate any changes early.',
    'improve_work':
        'Work quality is your lowest-rated area. Check the finished work with the customer and address any concerns before closing the job.',
    'improve_overall':
        'Read recent feedback and choose one recurring issue to address on your next job.',
  },
  'he': {
    'next_step': 'הצעד הבא שלך',
    'add_professions':
        'הוסף את המקצועות שבהם אתה מציע שירות והסבר מה ניתן להזמין.',
    'improve_price':
        'המחיר הוא התחום עם הדירוג הנמוך ביותר שלך. לפני העבודה הבאה, סכם הצעת מחיר ברורה והסבר מה היא כוללת.',
    'improve_service':
        'השירות הוא התחום עם הדירוג הנמוך ביותר שלך. בעבודה הבאה, תאם ציפיות עם הלקוח ועדכן אותו לאורך הדרך.',
    'improve_timing':
        'עמידה בזמנים היא התחום עם הדירוג הנמוך ביותר שלך. סכם זמני הגעה וסיום מציאותיים ועדכן מראש על שינויים.',
    'improve_work':
        'איכות העבודה היא התחום עם הדירוג הנמוך ביותר שלך. בדוק את התוצאה עם הלקוח וטפל בהערות לפני סיום העבודה.',
    'improve_overall':
        'קרא את המשוב האחרון ובחר נושא חוזר אחד לשיפור בעבודה הבאה.',
  },
  'ar': {
    'next_step': 'خطوتك التالية',
    'add_professions':
        'أضف المهن التي تقدمها حالياً ووضّح الخدمات التي يمكن حجزها.',
    'improve_price':
        'السعر هو الجانب الأقل تقييماً لديك. اتفق على عرض سعر واضح قبل العمل القادم واشرح ما يشمله.',
    'improve_service':
        'الخدمة هي الجانب الأقل تقييماً لديك. اتفق مع العميل على توقعاته وأطلعه على المستجدات.',
    'improve_timing':
        'الالتزام بالمواعيد هو الجانب الأقل تقييماً لديك. حدّد أوقات وصول وإنجاز واقعية وأبلغ العميل مبكراً بأي تغيير.',
    'improve_work':
        'جودة العمل هي الجانب الأقل تقييماً لديك. راجع النتيجة مع العميل وعالج ملاحظاته قبل إنهاء العمل.',
    'improve_overall':
        'اقرأ الملاحظات الأخيرة واختر مشكلة متكررة واحدة لمعالجتها في العمل القادم.',
  },
  'ru': {
    'next_step': 'Следующий шаг',
    'add_professions':
        'Добавьте профессии, по которым сейчас работаете, и объясните, какие услуги можно заказать.',
    'improve_price':
        'Цена получила самую низкую оценку. До следующей работы согласуйте понятную смету и объясните, что в неё входит.',
    'improve_service':
        'Сервис получил самую низкую оценку. Уточните ожидания клиента и сообщайте о ходе следующей работы.',
    'improve_timing':
        'Соблюдение сроков получило самую низкую оценку. Согласуйте реалистичное время прибытия и завершения и заранее сообщайте об изменениях.',
    'improve_work':
        'Качество работы получило самую низкую оценку. Проверьте результат вместе с клиентом и устраните замечания до завершения работы.',
    'improve_overall':
        'Прочитайте последние отзывы и выберите одну повторяющуюся проблему для решения в следующей работе.',
  },
  'am': {
    'next_step': 'ቀጣዩ እርምጃዎ',
    'add_professions': 'አሁን የሚሰሩባቸውን ሙያዎች ያክሉ እና ደንበኞች ምን ማዘዝ እንደሚችሉ ያብራሩ።',
    'improve_price':
        'ዋጋ ዝቅተኛውን ደረጃ አግኝቷል። ከቀጣዩ ስራ በፊት ግልጽ የዋጋ ስምምነት ያድርጉ እና ምን እንደሚያካትት ያብራሩ።',
    'improve_service':
        'አገልግሎት ዝቅተኛውን ደረጃ አግኝቷል። በቀጣዩ ስራ የደንበኛውን ግምት ያረጋግጡ እና ስለ ሂደቱ ያሳውቁ።',
    'improve_timing':
        'ሰዓት ማክበር ዝቅተኛውን ደረጃ አግኝቷል። ተጨባጭ የመድረሻና የማጠናቀቂያ ጊዜ ይስማሙ እና ለውጦችን ቀድመው ያሳውቁ።',
    'improve_work':
        'የስራ ጥራት ዝቅተኛውን ደረጃ አግኝቷል። ውጤቱን ከደንበኛው ጋር ይፈትሹ እና ከመጨረስ በፊት ችግሮችን ያስተካክሉ።',
    'improve_overall':
        'የቅርብ ጊዜ አስተያየቶችን ያንብቡ እና በቀጣዩ ስራ ለማሻሻል አንድ ተደጋጋሚ ጉዳይ ይምረጡ።',
  },
};

const _decisionCopy = <String, Map<String, String>>{
  'en': {
    'profession_portfolio':
        '{profession} received {views} views and {requests} profession-tagged in-app requests this week. Its {rating} rating has {count} reviews, while your entire portfolio has only {projects} projects with media. Relevant work examples could help visitors assess this service.',
    'profession_portfolio_action':
        'Add recent {profession} examples until your portfolio shows at least 3 useful projects overall. Name the service and explain the result alongside clear photos.',
    'old_portfolio':
        'This week, {views} profile views and {requests} in-app requests are recorded. All dated portfolio projects are over 180 days old. A recent example could help visitors judge your current work.',
    'old_portfolio_action':
        'Add one recent, representative project with clear photos and a short explanation of the result. Recheck new requests after a full week.',
    'repeat_interest':
        '{count} different senders have each submitted multiple in-app requests in the last 60 days. Together with your strong overall reviews, this suggests an opportunity to understand recurring needs; it does not confirm repeat completed jobs.',
    'repeat_action':
        'Review those repeat inquiries and identify the service customers ask about again. Clarify that offer when responding to the next relevant request.',
    'all_business': 'One priority across your business',
    'business': 'Across your business',
    'pending':
        '{count} in-app requests have been pending for at least 48 hours. These customers have already expressed interest, so reviewing them is your most direct opportunity.',
    'pending_action':
        'Review each pending request today. Confirm whether you can help and send a clear next step or quote.',
    'lost_requests':
        '{lost} of {count} work requests received in the last 30 days and at least two days old are cancelled or declined. The records do not explain why, but this is worth investigating before seeking more traffic.',
    'lost_action':
        'Review those requests and identify one recurring reason. Address it in your booking details or customer communication before the next request.',
    'quality':
        '{scope}: {metric} averages {rating} across {count} reviews, compared with {other} for the other rated categories. This gap suggests a focused improvement opportunity.',
    'metric_price': 'price',
    'metric_service': 'service',
    'metric_timing': 'punctuality',
    'metric_work': 'work quality',
    'recent_quality':
        'The {count} dated reviews from the last 30 days average {recent}; the preceding 30-day group has {previousCount} reviews averaging {previous}. These review groups suggest a recent service issue worth checking.',
    'portfolio_conversion':
        'This week so far, {views} profile views and {requests} in-app requests are recorded. Your overall rating is {rating}, but your portfolio has only {projects} projects with media. More work examples could help visitors assess your service.',
    'portfolio_action':
        'Add enough recent projects to show at least 3 useful work examples. Include clear photos and explain the job and result in each.',
    'availability':
        'You received {count} in-app requests in the last 30 days, but no available work dates are listed for the next 14 days. Interested customers may struggle to find a suitable time.',
    'availability_action':
        'If you are taking work, publish the dates you can actually offer for the next two weeks. Otherwise, keep your calendar accurate.',
    'strength_visibility':
        '{profession} is your strongest reviewed service: {rating} across {count} reviews. It received {views} views this week, compared with {otherViews} across your other listed services. Its track record may deserve more exposure.',
    'strength_action':
        'Feature one recent {profession} project with clear photos and a description naming the service. Recheck that profession’s views after a full week.',
    'small_sample':
        'With {views} lifetime profile views and {count} reviews, there is not enough evidence yet to identify a reliable performance problem.',
    'sample_portfolio_action':
        'Add your first work example, then share your Hiro profile with relevant recent customers. Recheck after around 20–30 total views; this is a checkpoint, not a forecast.',
    'sample_action':
        'Share your Hiro profile with relevant recent customers and invite honest feedback after completed work. Recheck after around 20–30 total views.',
    'portfolio':
        'Your profile received {views} views this week, but the portfolio contains only {projects} projects with media. Visitors have few examples to assess your work.',
    'profile_gap':
        'Your profile is missing {field}. This leaves customers without information they may need before contacting you.',
    'field_professions': 'your professions',
    'field_description': 'a service description',
    'field_photo': 'a profile photo',
    'field_location': 'your town',
    'description_action':
        'Write a short description explaining the services you offer, what each includes, and the kinds of jobs you take.',
    'photo_action':
        'Add a clear, recent profile photo so customers can recognize who they are contacting.',
    'location_action':
        'Add your town and check the service area so customers can tell whether you cover their location.',
    'earnings_feedback':
        'Your recorded earnings total ₪{amount}, but you have only {count} reviews. The earnings total does not prove job volume; more customer feedback would make your service reputation easier to assess.',
    'feedback_action':
        'After your next completed job, ask the customer for one honest review about the work, service, timing and price.',
    'review_recency':
        'You have accepted work requests from the last 30 days, but no reviews dated in that period. Accepted requests do not confirm completed work; feedback after completion could strengthen your recent track record.',
    'healthy_performance':
        'Your key business signals are performing consistently: your overall rating is {rating} across {count} reviews, your portfolio has {projects} projects with media, {availability} work dates are available in the next 14 days, and {accepted} of {requests} recent work requests were accepted.',
    'healthy_action':
        'Keep your portfolio and availability current, continue reviewing new requests promptly, and maintain your service standard. Review this insight again after your next 5 work requests.',
    'data_building':
        'The available evidence does not identify a clear performance problem. It is too early to justify changing prices or a service that may already work well.',
    'data_action':
        'Use Hiro requests to track your next inquiries and their outcomes. Review the pattern after 5 new requests to identify where customers need more help.',
    'cta_profile': 'Update profile',
    'cta_portfolio': 'Add project',
    'cta_availability': 'Update availability',
    'cta_requests': 'Review requests',
  },
  'he': {
    'profession_portfolio':
        '{profession} קיבל {views} צפיות ו-{requests} בקשות באפליקציה המשויכות לתחום השבוע. הדירוג שלו הוא {rating} על בסיס {count} ביקורות, אך בכל תיק העבודות יש רק {projects} פרויקטים עם מדיה. דוגמאות רלוונטיות עשויות לעזור למבקרים להעריך את השירות.',
    'profession_portfolio_action':
        'הוסף דוגמאות עדכניות בתחום {profession} עד שבתיק העבודות יהיו לפחות 3 פרויקטים שימושיים בסך הכול. ציין את השירות והסבר את התוצאה לצד תמונות ברורות.',
    'old_portfolio':
        'השבוע נרשמו {views} צפיות בפרופיל ו-{requests} בקשות באפליקציה. כל הפרויקטים המתוארכים בתיק העבודות נוספו לפני יותר מ-180 ימים. דוגמה עדכנית עשויה לעזור למבקרים להעריך את העבודה שלך כיום.',
    'old_portfolio_action':
        'הוסף פרויקט מייצג אחרון עם תמונות ברורות והסבר קצר על התוצאה. בדוק שוב בקשות חדשות אחרי שבוע מלא.',
    'repeat_interest':
        '{count} פונים שונים שלחו כל אחד כמה בקשות באפליקציה ב-60 הימים האחרונים. יחד עם הביקורות הכלליות הטובות, זה מצביע על הזדמנות להבין צרכים חוזרים; אין בכך אישור לעבודות חוזרות שהושלמו.',
    'repeat_action':
        'בדוק את הפניות החוזרות וזהה איזה שירות מבקשים שוב. הבהר את ההצעה הזו בתשובה לבקשה הרלוונטית הבאה.',
    'all_business': 'עדיפות אחת לכל העסק',
    'business': 'בכל העסק',
    'pending':
        '{count} בקשות באפליקציה ממתינות לפחות 48 שעות. הלקוחות כבר הביעו עניין, ולכן טיפול בבקשות הוא ההזדמנות הישירה ביותר שלך כרגע.',
    'pending_action':
        'עבור היום על כל בקשה ממתינה. אשר אם תוכל לעזור ושלח צעד הבא ברור או הצעת מחיר.',
    'lost_requests':
        'מתוך {count} בקשות עבודה שהתקבלו ב-30 הימים האחרונים ולפני יומיים לפחות, {lost} בוטלו או נדחו. הנתונים לא מסבירים מדוע, אך כדאי לבדוק זאת לפני שמנסים למשוך עוד צפיות.',
    'lost_action':
        'בדוק את הבקשות האלה וחפש סיבה חוזרת אחת. טפל בה בפרטי ההזמנה או בתקשורת עם הלקוח לפני הבקשה הבאה.',
    'quality':
        '{scope}: הדירוג של {metric} הוא {rating} על בסיס {count} ביקורות, לעומת {other} בממוצע בשאר המדדים שדורגו. הפער מצביע על הזדמנות לשיפור ממוקד.',
    'metric_price': 'מחיר',
    'metric_service': 'שירות',
    'metric_timing': 'עמידה בזמנים',
    'metric_work': 'איכות העבודה',
    'recent_quality':
        '{count} הביקורות המתוארכות ב-30 הימים האחרונים קיבלו בממוצע {recent}, לעומת {previous} ב-{previousCount} ביקורות מהתקופה הקודמת של 30 ימים. ההבדל בין הקבוצות מצדיק בדיקה של המשוב האחרון.',
    'portfolio_conversion':
        'מתחילת השבוע נרשמו {views} צפיות בפרופיל ו-{requests} בקשות באפליקציה. הדירוג הכללי שלך הוא {rating}, אך בתיק העבודות יש רק {projects} פרויקטים עם תמונות או וידאו. דוגמאות נוספות עשויות לעזור למבקרים להעריך את השירות.',
    'portfolio_action':
        'הוסף פרויקטים אחרונים עד שיהיו לפחות 3 דוגמאות עבודה שימושיות. בכל פרויקט הצג תמונות ברורות והסבר מה נעשה ומה התוצאה.',
    'availability':
        'קיבלת {count} בקשות באפליקציה ב-30 הימים האחרונים, אך לא מופיעים ימי עבודה זמינים ב-14 הימים הקרובים. ללקוחות מעוניינים עלול להיות קשה למצוא זמן מתאים.',
    'availability_action':
        'אם אתה מקבל עבודות, פרסם את הימים שבהם אתה באמת פנוי בשבועיים הקרובים. אחרת, הקפד שהיומן ישקף את הזמינות שלך.',
    'strength_visibility':
        '{profession} הוא השירות החזק ביותר שלך לפי הביקורות: {rating} על בסיס {count} ביקורות. הוא קיבל {views} צפיות השבוע, לעומת {otherViews} בשאר השירותים הרשומים. ייתכן שכדאי לתת לניסיון המוכח הזה יותר חשיפה.',
    'strength_action':
        'הצג פרויקט אחרון בתחום {profession} עם תמונות ברורות ותיאור שמציין את השירות. בדוק שוב את הצפיות בתחום אחרי שבוע מלא.',
    'small_sample':
        'עם {views} צפיות מצטברות בפרופיל ו-{count} ביקורות, עדיין אין מספיק מידע לזיהוי בעיית ביצועים אמינה.',
    'sample_portfolio_action':
        'הוסף דוגמת עבודה ראשונה ושתף את פרופיל Hiro עם לקוחות אחרונים רלוונטיים. בדוק שוב בסביבות 20–30 צפיות מצטברות; זו נקודת בדיקה, לא תחזית.',
    'sample_action':
        'שתף את פרופיל Hiro עם לקוחות אחרונים רלוונטיים והזמן משוב כנה אחרי עבודה שהושלמה. בדוק שוב בסביבות 20–30 צפיות מצטברות.',
    'portfolio':
        'הפרופיל קיבל {views} צפיות השבוע, אך בתיק העבודות יש רק {projects} פרויקטים עם תמונות או וידאו. למבקרים יש מעט דוגמאות להערכת העבודה שלך.',
    'profile_gap':
        'בפרופיל שלך חסר {field}. ללקוחות עשוי לחסר מידע נחוץ לפני יצירת קשר.',
    'field_professions': 'פירוט מקצועות',
    'field_description': 'תיאור שירות',
    'field_photo': 'צילום פרופיל',
    'field_location': 'שם היישוב',
    'description_action':
        'כתוב תיאור קצר שמסביר אילו שירותים אתה מציע, מה הם כוללים ואילו עבודות אתה מקבל.',
    'photo_action':
        'הוסף צילום פרופיל ברור ועדכני כדי שלקוחות יוכלו לזהות למי הם פונים.',
    'location_action':
        'הוסף את היישוב שלך ובדוק את אזור השירות, כדי שלקוחות ידעו אם אתה מגיע אליהם.',
    'earnings_feedback':
        'סך ההכנסות המתועדות שלך הוא ₪{amount}, אך יש לך רק {count} ביקורות. הסכום אינו מעיד על מספר העבודות; משוב נוסף יעזור ללקוחות להעריך את השירות שלך.',
    'feedback_action':
        'אחרי העבודה הבאה שתשלים, בקש מהלקוח ביקורת כנה אחת על העבודה, השירות, הזמנים והמחיר.',
    'review_recency':
        'יש לך בקשות עבודה שהתקבלו ואושרו ב-30 הימים האחרונים, אך אין ביקורות המתוארכות לתקופה הזו. אישור בקשה אינו אישור לסיום עבודה; משוב לאחר הסיום יכול לחזק את הניסיון העדכני שלך.',
    'healthy_performance':
        'המדדים המרכזיים של העסק שלך מציגים ביצועים עקביים: הדירוג הכללי הוא {rating} על בסיס {count} ביקורות, בתיק העבודות יש {projects} פרויקטים עם מדיה, יש {availability} ימי עבודה זמינים ב-14 הימים הקרובים, ו-{accepted} מתוך {requests} בקשות העבודה האחרונות אושרו.',
    'healthy_action':
        'המשך לעדכן את תיק העבודות והזמינות ושמור על אותה רמת מענה ושירות. בדוק שוב את ההמלצה לאחר 5 בקשות העבודה הבאות.',
    'data_building':
        'הנתונים הזמינים אינם מצביעים על בעיית ביצועים ברורה. עדיין אין בסיס לשינוי מחירים או שירות שעשוי כבר לעבוד היטב.',
    'data_action':
        'השתמש בבקשות Hiro כדי לתעד את הפניות הבאות ואת תוצאותיהן. בדוק את הדפוס אחרי 5 בקשות חדשות כדי לזהות היכן לקוחות צריכים יותר עזרה.',
    'cta_profile': 'עדכן פרופיל',
    'cta_portfolio': 'הוסף פרויקט',
    'cta_availability': 'עדכן זמינות',
    'cta_requests': 'צפה בבקשות',
  },
  'ar': {
    'profession_portfolio':
        'حصلت خدمة {profession} على {views} مشاهدات و{requests} طلبات مرتبطة بالمهنة داخل التطبيق هذا الأسبوع. تقييمها {rating} من {count} مراجعات، بينما يحتوي معرضك كله على {projects} مشاريع مع وسائط فقط. أمثلة مناسبة قد تساعد الزوار على تقييم الخدمة.',
    'profession_portfolio_action':
        'أضف أمثلة حديثة في {profession} حتى يحتوي معرضك على 3 مشاريع مفيدة على الأقل إجمالاً. سمِّ الخدمة واشرح النتيجة مع صور واضحة.',
    'old_portfolio':
        'هذا الأسبوع سُجلت {views} مشاهدات و{requests} طلبات داخل التطبيق. جميع مشاريع المعرض المؤرخة أُضيفت منذ أكثر من 180 يوماً. مثال حديث قد يساعد الزوار على تقييم عملك الحالي.',
    'old_portfolio_action':
        'أضف مشروعاً حديثاً ممثلاً لعملك مع صور واضحة وشرح قصير للنتيجة. راجع الطلبات الجديدة بعد أسبوع كامل.',
    'repeat_interest':
        'أرسل {count} أشخاص مختلفين عدة طلبات لكل منهم داخل التطبيق خلال آخر 60 يوماً. مع مراجعاتك العامة القوية، قد تكون هذه فرصة لفهم الاحتياجات المتكررة؛ لكنها لا تثبت إنجاز أعمال متكررة.',
    'repeat_action':
        'راجع الاستفسارات المتكررة وحدد الخدمة المطلوبة مجدداً. وضّح هذا العرض عند الرد على الطلب المناسب القادم.',
    'all_business': 'أولوية واحدة لكل أعمالك',
    'business': 'في جميع أعمالك',
    'pending':
        '{count} طلبات داخل التطبيق تنتظر منذ 48 ساعة على الأقل. هؤلاء العملاء أبدوا اهتماماً بالفعل، لذا مراجعتها هي فرصتك الأقرب الآن.',
    'pending_action':
        'راجع كل طلب معلّق اليوم. أكّد إن كنت تستطيع المساعدة وأرسل خطوة تالية واضحة أو عرض سعر.',
    'lost_requests':
        'من أصل {count} طلبات عمل وردت خلال آخر 30 يوماً ومضى عليها يومان على الأقل، أُلغي أو رُفض {lost}. السجلات لا توضح السبب، لكن الأمر يستحق المراجعة قبل جذب مزيد من الزيارات.',
    'lost_action':
        'راجع هذه الطلبات وابحث عن سبب متكرر واحد. عالجه في تفاصيل الحجز أو التواصل مع العميل قبل الطلب القادم.',
    'quality':
        '{scope}: متوسط {metric} هو {rating} بناءً على {count} مراجعات، مقابل {other} لبقية الجوانب المقيّمة. هذا الفرق يشير إلى فرصة تحسين محددة.',
    'metric_price': 'السعر',
    'metric_service': 'الخدمة',
    'metric_timing': 'الالتزام بالمواعيد',
    'metric_work': 'جودة العمل',
    'recent_quality':
        'متوسط {count} مراجعات مؤرخة في آخر 30 يوماً هو {recent}، مقابل {previous} في {previousCount} مراجعات من الثلاثين يوماً السابقة. الفرق بين المجموعتين يستحق مراجعة الملاحظات الأخيرة.',
    'portfolio_conversion':
        'منذ بداية الأسبوع سُجلت {views} مشاهدات للملف و{requests} طلبات داخل التطبيق. تقييمك العام {rating}، لكن معرضك يحتوي على {projects} مشاريع فقط مع وسائط. أمثلة إضافية قد تساعد الزوار على تقييم خدمتك.',
    'portfolio_action':
        'أضف مشاريع حديثة حتى تعرض 3 أمثلة عمل مفيدة على الأقل. أرفق صوراً واضحة واشرح العمل والنتيجة في كل مثال.',
    'availability':
        'تلقيت {count} طلبات داخل التطبيق في آخر 30 يوماً، لكن لا توجد أيام عمل متاحة مدرجة للأيام الـ14 القادمة. قد يصعب على العملاء إيجاد وقت مناسب.',
    'availability_action':
        'إذا كنت تقبل أعمالاً، انشر الأيام المتاحة فعلاً خلال الأسبوعين القادمين. وإلا فحافظ على دقة تقويمك.',
    'strength_visibility':
        '{profession} هي أقوى خدماتك بحسب المراجعات: {rating} من {count} مراجعات. حصلت على {views} مشاهدات هذا الأسبوع مقابل {otherViews} لبقية خدماتك المدرجة. قد يستحق هذا السجل مزيداً من الظهور.',
    'strength_action':
        'اعرض مشروعاً حديثاً في {profession} مع صور واضحة ووصف يسمّي الخدمة. راجع مشاهدات هذه المهنة بعد أسبوع كامل.',
    'small_sample':
        'مع {views} مشاهدات إجمالية للملف و{count} مراجعات، لا توجد أدلة كافية لتحديد مشكلة أداء موثوقة.',
    'sample_portfolio_action':
        'أضف أول مثال لعملك وشارك ملف Hiro مع عملاء سابقين مناسبين. راجع النتائج عند نحو 20–30 مشاهدة إجمالية؛ هذه نقطة مراجعة وليست توقعاً.',
    'sample_action':
        'شارك ملف Hiro مع عملاء سابقين مناسبين واطلب ملاحظات صادقة بعد إنجاز العمل. راجع النتائج عند نحو 20–30 مشاهدة إجمالية.',
    'portfolio':
        'حصل ملفك على {views} مشاهدات هذا الأسبوع، لكن المعرض يحتوي على {projects} مشاريع فقط مع وسائط. لدى الزوار أمثلة قليلة لتقييم عملك.',
    'profile_gap':
        'يفتقد ملفك {field}. قد يحتاج العملاء هذه المعلومات قبل التواصل معك.',
    'field_professions': 'قائمة المهن',
    'field_description': 'وصف الخدمة',
    'field_photo': 'صورة الملف',
    'field_location': 'اسم البلدة',
    'description_action':
        'اكتب وصفاً قصيراً للخدمات التي تقدمها وما تشمل وأنواع الأعمال التي تقبلها.',
    'photo_action': 'أضف صورة ملف واضحة وحديثة ليعرف العملاء من يتواصلون معه.',
    'location_action':
        'أضف بلدتك وراجع نطاق الخدمة ليعرف العملاء إن كنت تغطي موقعهم.',
    'earnings_feedback':
        'إجمالي أرباحك المسجلة ₪{amount}، لكن لديك {count} مراجعات فقط. المبلغ لا يثبت عدد الأعمال؛ المزيد من الملاحظات يساعد على تقييم خدمتك.',
    'feedback_action':
        'بعد العمل القادم الذي تنجزه، اطلب من العميل مراجعة صادقة واحدة عن العمل والخدمة والمواعيد والسعر.',
    'review_recency':
        'لديك طلبات عمل واردة ومقبولة خلال آخر 30 يوماً، لكن لا توجد مراجعات مؤرخة في هذه الفترة. قبول الطلب لا يثبت إنجاز العمل؛ الملاحظات بعد الإنجاز قد تعزز سجلك الحديث.',
    'healthy_performance':
        'تُظهر مؤشرات أعمالك الرئيسية أداءً ثابتاً: تقييمك العام {rating} من {count} مراجعات، ويضم معرضك {projects} مشاريع مع وسائط، ولديك {availability} أيام عمل متاحة خلال 14 يوماً، وتم قبول {accepted} من أصل {requests} طلبات عمل حديثة.',
    'healthy_action':
        'حافظ على تحديث معرضك وتوفرك وعلى مستوى الاستجابة والخدمة نفسه. راجع هذه التوصية بعد طلبات العمل الخمسة القادمة.',
    'data_building':
        'الأدلة المتاحة لا تحدد مشكلة أداء واضحة. لا يوجد أساس كافٍ لتغيير الأسعار أو خدمة قد تعمل جيداً بالفعل.',
    'data_action':
        'استخدم طلبات Hiro لتتبع الاستفسارات القادمة ونتائجها. راجع النمط بعد 5 طلبات جديدة لتحديد أين يحتاج العملاء مساعدة إضافية.',
    'cta_profile': 'تحديث الملف',
    'cta_portfolio': 'إضافة مشروع',
    'cta_availability': 'تحديث التوفر',
    'cta_requests': 'مراجعة الطلبات',
  },
  'ru': {
    'profession_portfolio':
        'Услуга «{profession}» получила {views} просмотров и {requests} заявок с указанием профессии за неделю. Оценка — {rating} по {count} отзывам, а во всём портфолио лишь {projects} проектов с медиа. Подходящие примеры могут помочь оценить услугу.',
    'profession_portfolio_action':
        'Добавьте свежие примеры по услуге «{profession}», чтобы в портфолио было хотя бы 3 полезных проекта всего. Назовите услугу, приложите чёткие фото и объясните результат.',
    'old_portfolio':
        'За неделю зарегистрированы {views} просмотров и {requests} заявок в приложении. Все датированные проекты портфолио добавлены более 180 дней назад. Свежий пример может помочь оценить вашу работу сейчас.',
    'old_portfolio_action':
        'Добавьте один свежий показательный проект с чёткими фото и кратким описанием результата. Проверьте новые заявки через полную неделю.',
    'repeat_interest':
        '{count} разных отправителей подали по несколько заявок в приложении за последние 60 дней. Вместе с высокими общими оценками это даёт возможность изучить повторяющиеся потребности, но не подтверждает завершённые повторные работы.',
    'repeat_action':
        'Просмотрите повторные обращения и определите услугу, о которой спрашивают снова. Чётко объясните это предложение при ответе на следующую подходящую заявку.',
    'all_business': 'Один приоритет для всего бизнеса',
    'business': 'По всему бизнесу',
    'pending':
        '{count} заявок в приложении ожидают не менее 48 часов. Эти клиенты уже проявили интерес, поэтому рассмотрение заявок — ближайшая возможность для вас.',
    'pending_action':
        'Сегодня рассмотрите каждую ожидающую заявку. Подтвердите, можете ли помочь, и предложите понятный следующий шаг или смету.',
    'lost_requests':
        'Из {count} заявок на работу за последние 30 дней, которым не менее двух дней, {lost} отменены или отклонены. Причины в записях не указаны, но это стоит проверить до привлечения новых посетителей.',
    'lost_action':
        'Просмотрите эти заявки и найдите одну повторяющуюся причину. Учтите её в условиях заказа или общении с клиентами до следующей заявки.',
    'quality':
        '{scope}: показатель «{metric}» — {rating} по {count} отзывам, против {other} в среднем по остальным оценённым категориям. Этот разрыв указывает на конкретную возможность улучшения.',
    'metric_price': 'цена',
    'metric_service': 'сервис',
    'metric_timing': 'пунктуальность',
    'metric_work': 'качество работы',
    'recent_quality':
        'Средняя оценка {count} датированных отзывов за последние 30 дней — {recent}; в предыдущей группе за 30 дней — {previous} по {previousCount} отзывам. Разница между группами заслуживает проверки последних замечаний.',
    'portfolio_conversion':
        'С начала недели зарегистрированы {views} просмотров профиля и {requests} заявок в приложении. Общая оценка — {rating}, но в портфолио лишь {projects} проектов с медиа. Дополнительные примеры могут помочь посетителям оценить услугу.',
    'portfolio_action':
        'Добавьте свежие проекты, чтобы показать хотя бы 3 полезных примера работ. Для каждого приложите чёткие фото и опишите задачу и результат.',
    'availability':
        'За последние 30 дней вы получили {count} заявок в приложении, но на ближайшие 14 дней не указаны доступные рабочие даты. Клиентам может быть трудно подобрать время.',
    'availability_action':
        'Если вы принимаете заказы, укажите реальные доступные даты на ближайшие две недели. Иначе поддерживайте календарь актуальным.',
    'strength_visibility':
        '{profession} — ваша сильнейшая услуга по отзывам: {rating} по {count} отзывам. За неделю она получила {views} просмотров, а остальные указанные услуги — {otherViews}. Этот опыт, возможно, заслуживает большей видимости.',
    'strength_action':
        'Покажите свежий проект по услуге «{profession}» с чёткими фото и названием услуги в описании. Проверьте просмотры этой профессии через полную неделю.',
    'small_sample':
        'При {views} просмотрах профиля за всё время и {count} отзывах данных пока недостаточно для надёжного вывода о проблеме.',
    'sample_portfolio_action':
        'Добавьте первый пример работы и поделитесь профилем Hiro с подходящими прежними клиентами. Проверьте результаты при примерно 20–30 общих просмотрах; это контрольная точка, а не прогноз.',
    'sample_action':
        'Поделитесь профилем Hiro с подходящими прежними клиентами и попросите честный отзыв после выполненной работы. Проверьте результаты при примерно 20–30 общих просмотрах.',
    'portfolio':
        'За неделю профиль получил {views} просмотров, но в портфолио лишь {projects} проектов с медиа. У посетителей мало примеров для оценки работы.',
    'profile_gap':
        'В профиле отсутствует {field}. Клиентам может не хватать этой информации перед обращением.',
    'field_professions': 'список профессий',
    'field_description': 'описание услуг',
    'field_photo': 'фото профиля',
    'field_location': 'название населённого пункта',
    'description_action':
        'Кратко опишите услуги, что в них входит и какие задачи вы принимаете.',
    'photo_action':
        'Добавьте чёткое свежее фото профиля, чтобы клиенты понимали, к кому обращаются.',
    'location_action':
        'Добавьте населённый пункт и проверьте зону обслуживания, чтобы клиенты знали, работаете ли вы у них.',
    'earnings_feedback':
        'Общий учтённый доход — ₪{amount}, но отзывов лишь {count}. Сумма не доказывает число работ; дополнительные отзывы помогут оценить ваш сервис.',
    'feedback_action':
        'После следующей выполненной работы попросите клиента оставить один честный отзыв о работе, сервисе, сроках и цене.',
    'review_recency':
        'У вас есть поступившие и принятые заявки на работу за последние 30 дней, но нет отзывов с датой этого периода. Принятая заявка не подтверждает завершение работы; отзыв после завершения может укрепить свежий послужной список.',
    'healthy_performance':
        'Основные показатели бизнеса демонстрируют стабильные результаты: общая оценка — {rating} по {count} отзывам, в портфолио {projects} проектов с медиа, на ближайшие 14 дней доступны {availability} рабочих дня, а из {requests} недавних заявок на работу принято {accepted}.',
    'healthy_action':
        'Поддерживайте портфолио и доступность в актуальном состоянии и сохраняйте тот же уровень ответа и сервиса. Вернитесь к рекомендации после следующих 5 заявок на работу.',
    'data_building':
        'Доступные данные не указывают на явную проблему. Пока нет оснований менять цены или услугу, которая, возможно, уже работает хорошо.',
    'data_action':
        'Используйте заявки Hiro для учёта следующих обращений и их результатов. Проверьте закономерности после 5 новых заявок, чтобы понять, где клиентам нужна помощь.',
    'cta_profile': 'Обновить профиль',
    'cta_portfolio': 'Добавить проект',
    'cta_availability': 'Обновить доступность',
    'cta_requests': 'Посмотреть заявки',
  },
  'am': {
    'profession_portfolio':
        '{profession} በዚህ ሳምንት {views} እይታዎችና {requests} በሙያው የተመዘገቡ የመተግበሪያ ጥያቄዎች አግኝቷል። ደረጃው {rating} ነው ከ{count} ግምገማዎች፣ ግን በሙሉ ፖርትፎሊዮዎ ሚዲያ ያላቸው {projects} ፕሮጀክቶች ብቻ አሉ። ተዛማጅ ምሳሌዎች ጎብኚዎችን ሊረዱ ይችላሉ።',
    'profession_portfolio_action':
        'በፖርትፎሊዮዎ በአጠቃላይ ቢያንስ 3 ጠቃሚ ፕሮጀክቶች እስኪኖሩ ድረስ በ{profession} አዲስ ምሳሌዎች ያክሉ። አገልግሎቱን ይጥቀሱ እና ውጤቱን በግልጽ ፎቶዎች ያሳዩ።',
    'old_portfolio':
        'በዚህ ሳምንት {views} እይታዎችና {requests} ጥያቄዎች ተመዝግበዋል። ሁሉም ቀን ያላቸው ፕሮጀክቶች ከ180 ቀናት በፊት ተጨምረዋል። አዲስ ምሳሌ የአሁኑን ስራዎን ለመገምገም ሊረዳ ይችላል።',
    'old_portfolio_action':
        'አንድ የቅርብ ጊዜ ተወካይ ፕሮጀክት በግልጽ ፎቶዎችና በአጭር የውጤት መግለጫ ያክሉ። ከሙሉ ሳምንት በኋላ አዲስ ጥያቄዎችን ይፈትሹ።',
    'repeat_interest':
        'ባለፉት 60 ቀናት {count} የተለያዩ ላኪዎች እያንዳንዳቸው ብዙ ጥያቄዎችን ልከዋል። ከጥሩ አጠቃላይ ግምገማዎችዎ ጋር ተደጋጋሚ ፍላጎትን ለመረዳት እድል ሊሆን ይችላል፤ የተጠናቀቁ ተደጋጋሚ ስራዎችን አያረጋግጥም።',
    'repeat_action':
        'ተደጋጋሚ ጥያቄዎቹን ይመልከቱ እና ደጋግመው የሚጠይቁትን አገልግሎት ይለዩ። ለቀጣዩ ተዛማጅ ጥያቄ ሲመልሱ አቅርቦቱን ያብራሩ።',
    'all_business': 'ለሁሉም ንግድዎ አንድ ቅድሚያ',
    'business': 'በሁሉም ንግድዎ',
    'pending':
        '{count} የመተግበሪያ ጥያቄዎች ቢያንስ 48 ሰዓት እየጠበቁ ነው። ደንበኞቹ ፍላጎት አሳይተዋል፤ ጥያቄዎቹን መመልከት ቅርብ እድልዎ ነው።',
    'pending_action':
        'ዛሬ እያንዳንዱን ጥያቄ ይመልከቱ። መርዳት እንደሚችሉ ያረጋግጡ እና ግልጽ ቀጣይ እርምጃ ወይም የዋጋ ሀሳብ ይላኩ።',
    'lost_requests':
        'ባለፉት 30 ቀናት ከመጡ እና ቢያንስ ሁለት ቀን ከቆዩ {count} የስራ ጥያቄዎች፣ {lost} ተሰርዘዋል ወይም ተከልክለዋል። ምክንያቱ አልተመዘገበም፣ ግን ተጨማሪ እይታ ከመፈለግ በፊት መመርመር ይገባል።',
    'lost_action':
        'ጥያቄዎቹን ይመልከቱ እና አንድ ተደጋጋሚ ምክንያት ይፈልጉ። ከቀጣዩ ጥያቄ በፊት በቦታ ማስያዣ ዝርዝር ወይም በደንበኛ ግንኙነት ያስተካክሉት።',
    'quality':
        '{scope}፦ የ{metric} አማካይ {rating} ነው በ{count} ግምገማዎች፣ የሌሎች የተመዘኑ ክፍሎች አማካይ {other} ሲሆን። ልዩነቱ ለተወሰነ ማሻሻያ እድል ያመለክታል።',
    'metric_price': 'ዋጋ',
    'metric_service': 'አገልግሎት',
    'metric_timing': 'ሰዓት አክባሪነት',
    'metric_work': 'የስራ ጥራት',
    'recent_quality':
        'ባለፉት 30 ቀናት የተመዘገቡ {count} ግምገማዎች አማካይ {recent} ነው፤ ከዚያ በፊት ባሉት 30 ቀናት {previousCount} ግምገማዎች አማካይ {previous} ነበር። የቡድኖቹ ልዩነት የቅርብ ጊዜ አስተያየቶችን ለመፈተሽ ምክንያት ነው።',
    'portfolio_conversion':
        'ከሳምንቱ መጀመሪያ {views} የፕሮፋይል እይታዎችና {requests} የመተግበሪያ ጥያቄዎች ተመዝግበዋል። አጠቃላይ ደረጃዎ {rating} ነው፣ ግን ሚዲያ ያላቸው {projects} ፕሮጀክቶች ብቻ አሉ። ተጨማሪ ምሳሌዎች ጎብኚዎችን ሊረዱ ይችላሉ።',
    'portfolio_action':
        'ቢያንስ 3 ጠቃሚ የስራ ምሳሌዎች እስኪኖሩ ድረስ የቅርብ ጊዜ ፕሮጀክቶችን ያክሉ። ግልጽ ፎቶዎችን ያስገቡ እና ስራውንና ውጤቱን ያብራሩ።',
    'availability':
        'ባለፉት 30 ቀናት {count} ጥያቄዎችን ተቀብለዋል፣ ግን ለሚቀጥሉት 14 ቀናት ክፍት የስራ ቀኖች አልተዘረዘሩም። ደንበኞች ተስማሚ ጊዜ ለማግኘት ሊቸገሩ ይችላሉ።',
    'availability_action':
        'ስራ የሚቀበሉ ከሆነ፣ በሚቀጥሉት ሁለት ሳምንታት በእርግጥ ክፍት የሆኑባቸውን ቀኖች ያሳዩ። ካልሆነ የቀን መቁጠሪያዎን ትክክለኛ ያድርጉ።',
    'strength_visibility':
        '{profession} በግምገማዎች መሠረት ጠንካራው አገልግሎትዎ ነው፦ {rating} ከ{count} ግምገማዎች። በዚህ ሳምንት {views} እይታዎች አግኝቷል፣ ሌሎቹ የተዘረዘሩ አገልግሎቶች {otherViews} ሲያገኙ። ይህ ልምድ ተጨማሪ ታይነት ሊገባው ይችላል።',
    'strength_action':
        'በ{profession} የቅርብ ጊዜ ፕሮጀክት በግልጽ ፎቶዎችና አገልግሎቱን በሚጠቅስ መግለጫ ያሳዩ። ከሙሉ ሳምንት በኋላ የሙያውን እይታዎች ይፈትሹ።',
    'small_sample':
        'በ{views} ጠቅላላ የፕሮፋይል እይታዎችና {count} ግምገማዎች፣ አስተማማኝ የአፈጻጸም ችግር ለመለየት መረጃው አይበቃም።',
    'sample_portfolio_action':
        'የመጀመሪያ የስራ ምሳሌዎን ያክሉ እና የHiro ፕሮፋይልዎን ለተዛማጅ የቅርብ ጊዜ ደንበኞች ያጋሩ። ወደ 20–30 ጠቅላላ እይታዎች ሲደርሱ ይፈትሹ፤ ይህ የመፈተሻ ነጥብ እንጂ ትንበያ አይደለም።',
    'sample_action':
        'የHiro ፕሮፋይልዎን ለተዛማጅ የቅርብ ጊዜ ደንበኞች ያጋሩ እና ከተጠናቀቀ ስራ በኋላ ቅን አስተያየት ይጠይቁ። ወደ 20–30 ጠቅላላ እይታዎች ሲደርሱ ይፈትሹ።',
    'portfolio':
        'ፕሮፋይልዎ በዚህ ሳምንት {views} እይታዎች አግኝቷል፣ ግን ሚዲያ ያላቸው {projects} ፕሮጀክቶች ብቻ አሉ። ጎብኚዎች ስራዎን ለመገምገም ጥቂት ምሳሌዎች አሏቸው።',
    'profile_gap':
        'በፕሮፋይልዎ {field} ይጎድላል። ደንበኞች ከማነጋገርዎ በፊት ይህን መረጃ ሊፈልጉ ይችላሉ።',
    'field_professions': 'የሙያ ዝርዝር',
    'field_description': 'የአገልግሎት መግለጫ',
    'field_photo': 'የፕሮፋይል ፎቶ',
    'field_location': 'የከተማ ስም',
    'description_action':
        'የሚሰጡትን አገልግሎት፣ ምን እንደሚያካትት እና የሚቀበሉትን የስራ አይነት በአጭሩ ይግለጹ።',
    'photo_action': 'ደንበኞች ማንን እንደሚያነጋግሩ እንዲያውቁ ግልጽና የቅርብ ጊዜ የፕሮፋይል ፎቶ ያክሉ።',
    'location_action': 'የከተማዎን ስም ያክሉ እና የአገልግሎት ክልሉን ይፈትሹ።',
    'earnings_feedback':
        'ጠቅላላ የተመዘገበው ገቢዎ ₪{amount} ነው፣ ግን {count} ግምገማዎች ብቻ አሉ። ገንዘቡ የስራ ብዛትን አያረጋግጥም፤ ተጨማሪ አስተያየት አገልግሎትዎን ለመገምገም ይረዳል።',
    'feedback_action':
        'ከቀጣዩ የተጠናቀቀ ስራ በኋላ ስለ ስራው፣ አገልግሎቱ፣ ሰዓቱና ዋጋው አንድ ቅን ግምገማ ይጠይቁ።',
    'review_recency':
        'ባለፉት 30 ቀናት የመጡና የተቀበሉ የስራ ጥያቄዎች አሉዎት፣ ግን በዚያ ጊዜ የተመዘገቡ ግምገማዎች የሉም። ተቀባይነት ስራ መጠናቀቅን አያረጋግጥም፤ ከማጠናቀቅ በኋላ አስተያየት ይረዳል።',
    'healthy_performance':
        'ዋና የንግድ መለኪያዎችዎ የተረጋጋ አፈጻጸም ያሳያሉ፦ አጠቃላይ ደረጃዎ {rating} ነው ከ{count} ግምገማዎች፣ ፖርትፎሊዮዎ {projects} ሚዲያ ያላቸው ፕሮጀክቶች አሉት፣ በሚቀጥሉት 14 ቀናት {availability} የስራ ቀናት ክፍት ናቸው፣ እና ከ{requests} የቅርብ ጊዜ ጥያቄዎች {accepted} ተቀብለዋል።',
    'healthy_action':
        'ፖርትፎሊዮዎንና ዝግጁነትዎን ወቅታዊ ያድርጉ እና ተመሳሳይ የምላሽና የአገልግሎት ደረጃ ይጠብቁ። ከቀጣዮቹ 5 የስራ ጥያቄዎች በኋላ ምክሩን እንደገና ይመልከቱ።',
    'data_building':
        'ያለው መረጃ ግልጽ የአፈጻጸም ችግር አያሳይም። ዋጋ ወይም በጥሩ ሁኔታ የሚሰራ አገልግሎት ለመቀየር ገና መሠረት የለም።',
    'data_action':
        'ቀጣዮቹን ጥያቄዎችና ውጤቶቻቸውን በHiro ይከታተሉ። ከ5 አዲስ ጥያቄዎች በኋላ ደንበኞች የት ተጨማሪ እርዳታ እንደሚፈልጉ ይመርምሩ።',
    'cta_profile': 'ፕሮፋይል አዘምን',
    'cta_portfolio': 'ፕሮጀክት አክል',
    'cta_availability': 'ዝግጁነት አዘምን',
    'cta_requests': 'ጥያቄዎችን ተመልከት',
  },
};
