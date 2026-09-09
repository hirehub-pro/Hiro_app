import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/utils/growth_recommendation.dart';
import 'package:untitled1/widgets/growth_recommendation_card.dart';

void main() {
  testWidgets(
    'Hebrew card fits a narrow screen with enlarged text and working CTA',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var clicked = false;
      final tip = buildGrowthRecommendation(
        locale: 'he',
        professions: ['חשמלאי'],
        overallRatings: {'reviewCount': 20, 'avgOverallRating': 9.6},
        weeklyViews: 42,
        totalViews: 100,
        totalPayments: null,
        projects: [],
        requests: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: GrowthRecommendationCard(
                    title: 'המלצת צמיחה',
                    recommendation: tip,
                    isRtl: true,
                    onAction: () => clicked = true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(tip.summary), findsOneWidget);
      expect(find.text(tip.action), findsOneWidget);
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      expect(clicked, isTrue);
      expect(
        Directionality.of(tester.element(find.text(tip.summary))),
        TextDirection.rtl,
      );
    },
  );

  testWidgets('manual action has no misleading navigation button', (
    tester,
  ) async {
    final tip = buildGrowthRecommendation(
      locale: 'en',
      professions: ['Plumber'],
      overallRatings: {'reviewCount': 2},
      weeklyViews: 4,
      totalViews: 4,
      totalPayments: null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GrowthRecommendationCard(
            title: 'Growth Recommendation',
            recommendation: tip,
          ),
        ),
      ),
    );
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text(tip.summary), findsOneWidget);
  });
}
