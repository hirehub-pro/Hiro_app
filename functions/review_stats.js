"use strict";

function finiteRating(value) {
  const rating = Number(value);
  return Number.isFinite(rating) && rating >= 1 && rating <= 5 ? rating : null;
}

function reviewStatsDocumentId(profession) {
  return `profession_${encodeURIComponent(String(profession ?? "").trim())}`;
}

function emptyTotals(profession = null) {
  return {
    profession,
    reviewCount: 0,
    totalOverallRating: 0,
    totalPriceRating: 0,
    totalServiceRating: 0,
    totalTimingRating: 0,
    totalWorkQualityRating: 0,
  };
}

function addReview(totals, review) {
  const overall = finiteRating(review?.rating);
  const price = finiteRating(review?.priceRating);
  const service = finiteRating(review?.serviceRating);
  const timing = finiteRating(review?.timingRating);
  const workQuality = finiteRating(review?.workQualityRating);
  if ([overall, price, service, timing, workQuality].includes(null)) {
    return false;
  }

  totals.reviewCount += 1;
  totals.totalOverallRating += overall;
  totals.totalPriceRating += price;
  totals.totalServiceRating += service;
  totals.totalTimingRating += timing;
  totals.totalWorkQualityRating += workQuality;
  return true;
}

function withAverages(totals) {
  const divisor = totals.reviewCount;
  return {
    ...totals,
    avgOverallRating: divisor ? totals.totalOverallRating / divisor : 0,
    avgPriceRating: divisor ? totals.totalPriceRating / divisor : 0,
    avgServiceRating: divisor ? totals.totalServiceRating / divisor : 0,
    avgTimingRating: divisor ? totals.totalTimingRating / divisor : 0,
    avgWorkQualityRating: divisor ?
      totals.totalWorkQualityRating / divisor : 0,
  };
}

function emptyReviewStats(profession = null) {
  return withAverages(emptyTotals(profession));
}

function buildReviewStats(reviewDocuments) {
  const overall = emptyTotals();
  const professionTotals = new Map();

  for (const review of Array.isArray(reviewDocuments) ? reviewDocuments : []) {
    const profession = String(review?.profession ?? "").trim();
    if (!profession) continue;
    const totals = professionTotals.get(profession) || emptyTotals(profession);
    if (!addReview(totals, review)) continue;
    professionTotals.set(profession, totals);
    addReview(overall, review);
  }

  return {
    overall: withAverages(overall),
    professions: new Map(
        [...professionTotals.entries()].map(
            ([profession, totals]) => [profession, withAverages(totals)],
        ),
    ),
  };
}

module.exports = {
  buildReviewStats,
  emptyReviewStats,
  reviewStatsDocumentId,
};
