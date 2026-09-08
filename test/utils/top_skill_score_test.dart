import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/utils/top_skill_score.dart';

void main() {
  test('a trusted 9.6 rating outranks one perfect review', () {
    final singleReview = calculateTopSkillScore(
      averageRating: 10,
      reviewCount: 1,
    );
    final establishedProfession = calculateTopSkillScore(
      averageRating: 9.6,
      reviewCount: 1000,
    );

    expect(establishedProfession, greaterThan(singleReview));
    expect(singleReview, closeTo(7.1429, 0.0001));
    expect(establishedProfession, closeTo(9.5490, 0.0001));
  });

  test('a profession without reviews has no ranking score', () {
    expect(calculateTopSkillScore(averageRating: 10, reviewCount: 0), 0);
  });
}
