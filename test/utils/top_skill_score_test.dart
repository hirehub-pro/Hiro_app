import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/utils/top_skill_score.dart';

void main() {
  test('a trusted 4.8 rating outranks one five-star review', () {
    final singleReview = calculateTopSkillScore(
      averageRating: 5,
      reviewCount: 1,
    );
    final establishedProfession = calculateTopSkillScore(
      averageRating: 4.8,
      reviewCount: 1000,
    );

    expect(establishedProfession, greaterThan(singleReview));
    expect(singleReview, closeTo(3.5714, 0.0001));
    expect(establishedProfession, closeTo(4.7745, 0.0001));
  });

  test('a profession without reviews has no ranking score', () {
    expect(calculateTopSkillScore(averageRating: 5, reviewCount: 0), 0);
  });
}
