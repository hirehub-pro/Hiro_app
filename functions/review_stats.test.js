"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  buildReviewStats,
  emptyReviewStats,
  reviewStatsDocumentId,
} = require("./review_stats");

test("builds overall and per-profession review statistics", () => {
  const stats = buildReviewStats([
    {
      profession: "Electrician",
      rating: 4,
      priceRating: 3,
      serviceRating: 5,
      timingRating: 4,
      workQualityRating: 4,
    },
    {
      profession: "Electrician",
      rating: 5,
      priceRating: 5,
      serviceRating: 4,
      timingRating: 5,
      workQualityRating: 5,
    },
    {
      profession: "Plumber",
      rating: 3,
      priceRating: 2,
      serviceRating: 3,
      timingRating: 3,
      workQualityRating: 4,
    },
  ]);

  assert.equal(stats.overall.reviewCount, 3);
  assert.equal(stats.overall.totalOverallRating, 12);
  assert.equal(stats.overall.avgOverallRating, 4);
  assert.equal(stats.professions.get("Electrician").reviewCount, 2);
  assert.equal(stats.professions.get("Electrician").avgPriceRating, 4);
});

test("uses IDs that cannot collide with the overall document", () => {
  assert.equal(reviewStatsDocumentId("overall"), "profession_overall");
  assert.notEqual(
      reviewStatsDocumentId("Home/Cleaning"),
      reviewStatsDocumentId("Home_Cleaning"),
  );
});

test("ignores incomplete rating records", () => {
  const stats = buildReviewStats([{profession: "Plumber", rating: 5}]);
  assert.equal(stats.overall.reviewCount, 0);
  assert.equal(stats.professions.size, 0);
});

test("creates complete zero statistics for professions without reviews", () => {
  const stats = emptyReviewStats("Painter");
  assert.equal(stats.profession, "Painter");
  assert.equal(stats.reviewCount, 0);
  assert.equal(stats.totalServiceRating, 0);
  assert.equal(stats.avgWorkQualityRating, 0);
});
