"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  incrementWeeklyViewShard,
  normalizeProfileViewProfession,
  profileViewPeriod,
} = require("./public_profile_views");

test("uses only a profession published by the worker", () => {
  assert.equal(
      normalizeProfileViewProfession("plumber", ["Electrician", "Plumber"]),
      "Plumber",
  );
  assert.equal(
      normalizeProfileViewProfession("Invented", ["Electrician", "Plumber"]),
      "Electrician",
  );
  assert.equal(normalizeProfileViewProfession(null, []), "General");
});

test("builds an Israel-local Sunday-based view period", () => {
  const period = profileViewPeriod(new Date("2026-09-07T22:30:00.000Z"));
  assert.equal(period.dayKey, "tuesday");
  assert.equal(period.weekKey, "2026-09-06");
  assert.equal(period.weekStart.toISOString(), "2026-09-06T00:00:00.000Z");
});

test("increments the current weekday and weekly total", () => {
  const period = {
    dayKey: "monday",
    weekKey: "2026-09-06",
  };
  const result = incrementWeeklyViewShard({
    monday: 2,
    TVTW: 5,
    weekKey: "2026-09-06",
  }, period);
  assert.equal(result.monday, 3);
  assert.equal(result.TVTW, 6);
  assert.equal(result.sunday, 0);
});

test("resets a shard when a new week starts", () => {
  const result = incrementWeeklyViewShard({
    sunday: 20,
    TVTW: 20,
    weekKey: "2026-08-30",
  }, {
    dayKey: "sunday",
    weekKey: "2026-09-06",
  });
  assert.equal(result.sunday, 1);
  assert.equal(result.TVTW, 1);
});
