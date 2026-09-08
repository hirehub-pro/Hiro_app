import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/utils/growth_recommendation.dart';

final now = DateTime(2026, 9, 12, 12);
Map<String, dynamic> ratings({
  int count = 20,
  double overall = 9.6,
  double price = 9.6,
  double service = 9.6,
  double timing = 9.6,
  double work = 9.6,
}) => {
  'reviewCount': count,
  'avgOverallRating': overall,
  'avgPriceRating': price,
  'avgServiceRating': service,
  'avgTimingRating': timing,
  'avgWorkQualityRating': work,
};
Map<String, dynamic> request({
  int days = 3,
  String status = 'accepted',
  String type = 'work_request',
}) => {
  'timestamp': now.subtract(Duration(days: days)),
  'status': status,
  'type': type,
  'profession': 'Plumbing',
};
GrowthRecommendation insight({
  String locale = 'en',
  int views = 42,
  int total = 200,
  Map<String, dynamic>? overall,
  Map<String, Map<String, dynamic>> perProfession = const {},
  Map<String, int> professionViews = const {},
  List<String> professions = const ['Plumbing', 'Painting'],
  List<Map<String, dynamic>>? requests,
  List<Map<String, dynamic>>? projects,
  List<Map<String, dynamic>>? reviews,
  Map<String, dynamic>? profile,
  Map<String, dynamic>? schedule,
  double? earnings,
}) => buildGrowthRecommendation(
  locale: locale,
  professions: professions,
  overallRatings: overall ?? ratings(),
  weeklyViews: views,
  totalViews: total,
  totalEarnings: earnings,
  professionRatings: perProfession,
  professionWeeklyViews: professionViews,
  profile: profile,
  projects: projects,
  requests: requests,
  schedule: schedule,
  recentReviews: reviews,
  now: now,
);
String visible(String text) => text.replaceAll(RegExp('[\u2068\u2069]'), '');

void main() {
  test('business-ready pending requests outrank quality and profile gaps', () {
    final tip = insight(
      requests: [request(status: 'pending')],
      overall: ratings(price: 5),
      projects: [],
      profile: {},
    );
    expect(tip.reason, 'pending');
    expect(tip.destination, GrowthDestination.requests);
    expect(visible(tip.summary), contains('1 in-app requests'));
    expect(tip.action, contains('today'));
  });

  test('expired appointment and future request do not trigger follow-up', () {
    final expired = {
      ...request(status: 'pending'),
      'date': '2026-09-10',
      'requestedTo': '15:00',
    };
    expect(
      insight(
        requests: [
          expired,
          request(days: -1, status: 'pending'),
        ],
      ).reason,
      'data_building',
    );
  });

  test('cancelled/declined work needs adequate sample and excludes quotes', () {
    final requests = List.generate(
      10,
      (i) => request(status: i < 3 ? 'declined' : 'accepted'),
    );
    expect(
      insight(requests: requests, overall: ratings(price: 5)).reason,
      'lost_requests',
    );
    expect(
      insight(requests: requests.take(3).toList()).reason,
      'data_building',
    );
    expect(
      insight(
        requests: requests.map((r) => {...r, 'type': 'quote_request'}).toList(),
      ).reason,
      'data_building',
    );
  });

  test(
    'compares categories within the same profession with sample evidence',
    () {
      final tip = insight(
        perProfession: {'Plumbing': ratings(count: 24, price: 6)},
      );
      expect(tip.reason, 'quality');
      expect(
        visible(tip.summary),
        contains('Plumbing: price averages 6.0/10 across 24 reviews'),
      );
      expect(tip.action, contains('clear quote'));
      expect(tip.action, isNot(contains('lower your price')));
    },
  );

  test(
    'one low review and equally strong categories do not trigger quality edits',
    () {
      expect(
        insight(
          perProfession: {'Plumbing': ratings(count: 1, price: 2)},
        ).reason,
        'data_building',
      );
      expect(insight(overall: ratings(price: 9)).reason, 'data_building');
    },
  );

  test('overall review document is not double-counted with professions', () {
    final tip = insight(
      overall: ratings(count: 30, price: 6),
      perProfession: {'Plumbing': ratings(count: 20, price: 6)},
    );
    expect(visible(tip.summary), contains('across 30 reviews'));
    expect(visible(tip.summary), isNot(contains('50 reviews')));
  });

  test('missing overall stats use a review-weighted fallback', () {
    final tip = insight(
      overall: {},
      perProfession: {
        'Plumbing': ratings(count: 10, price: 5),
        'Painting': ratings(count: 30, price: 7),
      },
    );
    expect(visible(tip.summary), contains('6.5/10 across 40 reviews'));
  });

  test(
    'portfolio conversion opportunity combines views, requests, ratings and projects',
    () {
      final tip = insight(
        requests: [request(), request()],
        projects: [
          {
            'imageUrls': ['photo'],
          },
        ],
      );
      expect(tip.reason, 'portfolio_conversion');
      expect(
        visible(tip.summary),
        contains('42 profile views and 2 in-app requests'),
      );
      expect(tip.summary, contains('could help'));
      expect(tip.action, contains('at least 3'));
      expect(tip.destination, GrowthDestination.portfolio);
      expect(tip.summary, isNot(contains('%')));
    },
  );

  test(
    'unavailable requests never become zero requests or a conversion rate',
    () {
      final tip = insight(requests: null, projects: []);
      expect(tip.reason, 'portfolio');
      expect(tip.summary, isNot(contains('in-app requests')));
    },
  );

  test(
    'successful empty portfolio is different from unavailable portfolio',
    () {
      expect(
        insight(projects: [], requests: []).reason,
        'portfolio_conversion',
      );
      expect(insight(projects: null, requests: []).reason, 'data_building');
    },
  );

  test(
    'ample portfolio does not trigger add-project advice from aggregate counts',
    () {
      final projects = List.generate(
        4,
        (_) => {
          'imageUrls': ['photo'],
        },
      );
      expect(insight(projects: projects, requests: []).reason, 'data_building');
    },
  );

  test('strongest skill combines review confidence and profession views', () {
    final tip = insight(
      perProfession: {
        'Plumbing': ratings(count: 50),
        'Painting': ratings(count: 1, overall: 10),
      },
      professionViews: {'Plumbing': 4, 'Painting': 38},
    );
    expect(tip.reason, 'strength_visibility');
    expect(visible(tip.summary), contains('Plumbing is your strongest'));
    expect(visible(tip.summary), contains('4 views this week'));
    expect(tip.action, contains('Plumbing'));
  });

  test('no unobserved profession views are silently converted to zero', () {
    expect(
      insight(
        perProfession: {'Plumbing': ratings(count: 50)},
        professionViews: {'Painting': 42},
      ).reason,
      'data_building',
    );
  });

  test('profession ordering does not change the shared recommendation', () {
    final byProfession = {
      'Plumbing': ratings(count: 50),
      'Painting': ratings(count: 1),
    };
    final views = {'Plumbing': 4, 'Painting': 38};
    expect(
      insight(perProfession: byProfession, professionViews: views).summary,
      insight(
        professions: ['Painting', 'Plumbing'],
        perProfession: byProfession,
        professionViews: views,
      ).summary,
    );
  });

  test(
    'calendar gap needs requests and respects hidden schedules and vacations',
    () {
      final requests = List.generate(3, (_) => request());
      expect(
        insight(requests: requests, schedule: {'availableDates': []}).reason,
        'availability',
      );
      expect(
        insight(
          requests: requests,
          schedule: {'availableDates': [], 'hideSchedule': true},
        ).reason,
        'data_building',
      );
      expect(
        insight(
          requests: requests,
          schedule: {
            'availableDates': [],
            'vacations': [
              {'start': '2026-9-12', 'end': '2026-9-18'},
            ],
          },
        ).reason,
        'data_building',
      );
      expect(
        insight(
          requests: requests,
          schedule: {
            'availableDates': ['2026-9-14'],
          },
        ).reason,
        'data_building',
      );
      expect(insight(schedule: {'availableDates': []}).reason, 'data_building');
    },
  );

  test(
    'historical review comparison uses two adequately sized dated groups',
    () {
      final reviews = [
        ...List.generate(
          5,
          (_) => {
            'timestamp': now.subtract(const Duration(days: 10)),
            'rating': 7,
          },
        ),
        ...List.generate(
          5,
          (_) => {
            'timestamp': now.subtract(const Duration(days: 40)),
            'rating': 9.5,
          },
        ),
      ];
      final tip = insight(reviews: reviews);
      expect(tip.reason, 'recent_quality');
      expect(visible(tip.summary), contains('5 dated reviews'));
      expect(
        insight(reviews: reviews.take(7).toList()).reason,
        'data_building',
      );
      expect(insight(reviews: null).reason, 'data_building');
    },
  );

  test('accepted quotes do not establish recent work for review advice', () {
    expect(
      insight(
        reviews: [],
        requests: List.generate(3, (_) => request(type: 'quote_request')),
      ).reason,
      'data_building',
    );
    expect(
      insight(reviews: [], requests: List.generate(3, (_) => request())).reason,
      'review_recency',
    );
  });

  test(
    'earnings support feedback building without claiming job volume or trend',
    () {
      final tip = insight(overall: ratings(count: 2), earnings: 1500);
      expect(tip.reason, 'earnings_feedback');
      expect(tip.summary, contains('does not prove job volume'));
      expect(
        insight(overall: ratings(count: 2), earnings: null).reason,
        'data_building',
      );
      expect(
        insight(overall: ratings(count: 2), earnings: double.nan).reason,
        'data_building',
      );
    },
  );

  test(
    'very small activity prioritizes evidence building with a checkpoint',
    () {
      final tip = insight(
        views: 4,
        total: 4,
        overall: ratings(count: 2),
        projects: [],
      );
      expect(tip.reason, 'small_sample');
      expect(tip.summary, contains('not enough evidence'));
      expect(tip.action, contains('checkpoint, not a forecast'));
    },
  );

  test('profile action identifies a verified specific missing field', () {
    final tip = insight(profile: {'profileImageUrl': 'photo', 'town': 'Haifa'});
    expect(tip.reason, 'profile_gap');
    expect(tip.summary, contains('a service description'));
    expect(tip.destination, GrowthDestination.profile);
    expect(insight(profile: null).reason, 'data_building');
  });

  test(
    'profession request evidence never borrows the overall request count',
    () {
      final tip = insight(
        projects: [],
        requests: [
          {...request(), 'profession': 'Plumbing'},
          ...List.generate(5, (_) => {...request(), 'profession': 'Painting'}),
        ],
        perProfession: {'Plumbing': ratings()},
        professionViews: {'Plumbing': 40, 'Painting': 2},
      );
      expect(tip.reason, 'profession_portfolio');
      expect(
        visible(tip.summary),
        contains('40 views and 1 profession-tagged'),
      );
      expect(tip.summary, contains('entire portfolio'));
    },
  );

  test(
    'stale portfolio requires complete dates and current inquiry evidence',
    () {
      final projects = List.generate(
        3,
        (_) => {
          'imageUrls': ['photo'],
          'timestamp': now.subtract(const Duration(days: 200)),
        },
      );
      expect(insight(projects: projects, requests: []).reason, 'old_portfolio');
      expect(
        insight(projects: projects, requests: null).reason,
        'data_building',
      );
      expect(
        insight(
          projects: [
            ...projects,
            {
              'imageUrls': ['photo'],
            },
          ],
          requests: [],
        ).reason,
        'data_building',
      );
    },
  );

  test('requests outside the observed 60-day window are excluded', () {
    final tip = insight(
      requests: [
        request(days: 70, status: 'pending'),
        for (final id in ['a', 'a', 'b', 'b'])
          {...request(days: 70), 'fromId': id},
      ],
    );
    expect(tip.reason, 'data_building');
  });

  test('repeat request senders are not described as completed repeat jobs', () {
    final tip = insight(
      requests: [
        for (final id in ['a', 'a', 'b', 'b']) {...request(), 'fromId': id},
      ],
    );
    expect(tip.reason, 'repeat_interest');
    expect(tip.summary, contains('does not confirm repeat completed jobs'));
    expect(tip.destination, GrowthDestination.requests);
  });

  test(
    'all languages resolve every decision and action without placeholders',
    () {
      for (final locale in ['en', 'he', 'ar', 'ru', 'am', 'unknown']) {
        final scenarios = [
          insight(
            locale: locale,
            projects: [],
            requests: [],
            perProfession: {'Plumbing': ratings()},
            professionViews: {'Plumbing': 40},
          ),
          insight(
            locale: locale,
            projects: List.generate(
              3,
              (_) => {
                'imageUrls': ['photo'],
                'timestamp': now.subtract(const Duration(days: 200)),
              },
            ),
            requests: [],
          ),
          insight(
            locale: locale,
            requests: [
              for (final id in ['a', 'a', 'b', 'b'])
                {...request(), 'fromId': id},
            ],
          ),
          insight(locale: locale),
          insight(
            locale: locale,
            requests: [request(status: 'pending')],
          ),
          insight(
            locale: locale,
            requests: List.generate(10, (_) => request(status: 'declined')),
          ),
          insight(locale: locale, projects: [], requests: []),
          insight(locale: locale, projects: []),
          insight(
            locale: locale,
            views: 4,
            total: 4,
            overall: ratings(count: 1),
          ),
          insight(
            locale: locale,
            views: 4,
            total: 4,
            overall: ratings(count: 1),
            projects: [],
          ),
          insight(locale: locale, overall: ratings(count: 1), earnings: 100),
          insight(
            locale: locale,
            reviews: [],
            requests: List.generate(3, (_) => request()),
          ),
          insight(
            locale: locale,
            schedule: {'availableDates': []},
            requests: List.generate(3, (_) => request()),
          ),
          insight(
            locale: locale,
            perProfession: {'Plumbing': ratings(count: 50)},
            professionViews: {'Plumbing': 1, 'Painting': 41},
          ),
          insight(locale: locale, overall: ratings(price: 5)),
          insight(locale: locale, overall: ratings(service: 5)),
          insight(locale: locale, overall: ratings(timing: 5)),
          insight(locale: locale, overall: ratings(work: 5)),
          insight(locale: locale, professions: [], profile: {}),
          insight(locale: locale, profile: {}),
          insight(locale: locale, profile: {'description': 'hello'}),
          insight(
            locale: locale,
            profile: {'description': 'hello', 'profileImageUrl': 'photo'},
          ),
          insight(
            locale: locale,
            reviews: [
              ...List.generate(
                5,
                (_) => {
                  'timestamp': now.subtract(const Duration(days: 10)),
                  'rating': 6,
                },
              ),
              ...List.generate(
                5,
                (_) => {
                  'timestamp': now.subtract(const Duration(days: 40)),
                  'rating': 9,
                },
              ),
            ],
          ),
        ];
        for (final tip in scenarios) {
          expect(tip.summary, isNotEmpty);
          expect(tip.action, isNotEmpty);
          expect(
            '${tip.summary} ${tip.action}',
            isNot(matches(RegExp(r'\{\w+\}'))),
          );
          expect(tip.ctaLabel != null, tip.destination != null);
        }
      }
    },
  );
}
