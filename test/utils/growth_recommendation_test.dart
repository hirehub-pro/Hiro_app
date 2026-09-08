import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/utils/growth_recommendation.dart';

void main() {
  GrowthRecommendation recommendation({
    String locale = 'en',
    List<String> professions = const ['Plumber', 'Electrician'],
    int reviews = 1,
    double rating = 10,
    Map<String, dynamic> metrics = const {},
    int weeklyViews = 4,
    double? earnings = 0,
  }) => buildGrowthRecommendation(
    locale: locale,
    professions: professions,
    overallRatings: {
      'reviewCount': reviews,
      'avgOverallRating': rating,
      ...metrics,
    },
    weeklyViews: weeklyViews,
    totalViews: 120,
    totalEarnings: earnings,
  );

  test('small perfect sample gets qualified context and one shared action', () {
    final tip = recommendation();
    expect(tip.scope, contains('(2)'));
    expect(tip.summary, contains('10.0/10'));
    expect(tip.summary, contains('sample is still small'));
    expect(tip.summary, contains('4 this week so far; 120 in total'));
    expect(tip.action, contains('each listed service'));
    expect(tip.summary, isNot(contains('excellent')));
    expect(tip.action, isNot(contains('20+')));
  });

  test('unavailable earnings are distinct from recorded zero', () {
    final missing = recommendation(earnings: null);
    final zero = recommendation(earnings: 0);
    expect(missing.summary, contains('not available'));
    expect(zero.summary, contains('total zero'));
    expect(missing.action, isNot(zero.action));
  });

  test('earnings and review coverage change the next step', () {
    final early = recommendation(earnings: 1500);
    final established = recommendation(earnings: 1500, reviews: 12);
    expect(early.summary, contains('₪1,500'));
    expect(early.action, contains('honest review'));
    expect(established.action, contains('past customer'));
  });

  test('quality issue takes priority over zero weekly views', () {
    final tip = recommendation(
      reviews: 12,
      rating: 8.5,
      weeklyViews: 0,
      metrics: {'avgTimingRating': 6, 'avgServiceRating': 9},
    );
    expect(tip.action, startsWith('Timing'));
    expect(tip.action, contains('realistic arrival'));
  });

  test('missing categories and ties do not invent a weakest area', () {
    expect(
      recommendation(reviews: 10, rating: 6).action,
      startsWith('Read recent feedback'),
    );
    expect(
      recommendation(
        reviews: 10,
        rating: 6,
        metrics: {'avgPriceRating': 6, 'avgServiceRating': 6},
      ).action,
      startsWith('Read recent feedback'),
    );
  });

  test('one low review does not trigger a broad quality judgment', () {
    final tip = recommendation(
      rating: 3,
      earnings: 100,
      metrics: {'avgTimingRating': 2},
    );
    expect(tip.summary, contains('sample is still small'));
    expect(tip.action, contains('honest review'));
  });

  test('no recent views suggests outreach without claiming a trend', () {
    final tip = recommendation(weeklyViews: 0, earnings: 100, reviews: 10);
    expect(tip.action, startsWith('Share your profile'));
    expect(tip.summary, isNot(contains('low')));
  });

  test('profession list controls setup and service clarity advice', () {
    expect(
      recommendation(professions: []).action,
      startsWith('Add the professions'),
    );
    final single = recommendation(professions: [' Plumber ', 'Plumber', '']);
    expect(single.scope, contains('(1)'));
    expect(single.action, contains('a recent work example'));
    expect(
      recommendation(professions: ['Electrician', 'Plumber']).action,
      recommendation().action,
    );
  });

  test('empty and invalid data never produces a rating or fake earnings', () {
    final tip = recommendation(
      reviews: 0,
      rating: double.nan,
      earnings: double.infinity,
    );
    expect(tip.summary, contains('no customer ratings'));
    expect(tip.summary, contains('not available'));
    expect(tip.summary, isNot(contains('NaN')));
  });

  test('all supported languages resolve every message branch', () {
    for (final locale in ['en', 'he', 'ar', 'ru', 'am']) {
      final scenarios = [
        recommendation(locale: locale),
        recommendation(locale: locale, professions: []),
        recommendation(locale: locale, reviews: 0, earnings: null),
        recommendation(locale: locale, weeklyViews: 0),
        recommendation(locale: locale, professions: ['Plumber']),
        recommendation(locale: locale, earnings: 100),
        recommendation(locale: locale, earnings: 100, reviews: 20),
        recommendation(locale: locale, reviews: 10, rating: 6),
        for (final metric in [
          'avgPriceRating',
          'avgServiceRating',
          'avgTimingRating',
          'avgWorkQualityRating',
        ])
          recommendation(locale: locale, reviews: 10, metrics: {metric: 6}),
      ];
      for (final tip in scenarios) {
        expect(tip.scope, isNotEmpty);
        expect(tip.actionLabel, isNotEmpty);
        expect(tip.action, isNotEmpty);
        expect(
          '${tip.summary} ${tip.scope} ${tip.action}',
          isNot(matches(RegExp(r'\{\w+\}'))),
        );
      }
    }
    expect(recommendation(locale: 'he').actionLabel, 'הצעד הבא שלך');
    expect(recommendation(locale: 'unsupported').actionLabel, 'Your next step');
  });
}
