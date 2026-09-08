const double topSkillNeutralRating = 7.0;
const int topSkillConfidenceReviews = 20;

double calculateTopSkillScore({
  required double averageRating,
  required int reviewCount,
}) {
  if (reviewCount <= 0) return 0;

  return ((reviewCount * averageRating) +
          (topSkillConfidenceReviews * topSkillNeutralRating)) /
      (reviewCount + topSkillConfidenceReviews);
}
