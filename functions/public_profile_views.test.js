"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  incrementProfessionViews,
  normalizeProfileViewProfession,
  profileViewDocumentId,
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

test("creates collision-safe profession document IDs", () => {
  assert.notEqual(
      profileViewDocumentId("Home/Cleaning"),
      profileViewDocumentId("Home_Cleaning"),
  );
  assert.equal(profileViewDocumentId("Home/Cleaning"), "Home%2FCleaning");
});

test("builds an Israel-local Sunday-based view period", () => {
  const period = profileViewPeriod(new Date("2026-09-07T22:30:00.000Z"));
  assert.equal(period.dayKey, "tuesday");
  assert.equal(period.weekKey, "2026-09-06");
  assert.equal(period.weekStart.toISOString(), "2026-09-06T00:00:00.000Z");
});

test("increments the weekday and all-time total", () => {
  const result = incrementProfessionViews({
    monday: 2,
    totalViews: 8,
    weekKey: "2026-09-06",
  }, {
    dayKey: "monday",
    weekKey: "2026-09-06",
  });
  assert.equal(result.monday, 3);
  assert.equal(result.totalViews, 9);
  assert.equal(result.sunday, 0);
});

test("resets weekdays for a new week but preserves the all-time total", () => {
  const result = incrementProfessionViews({
    sunday: 20,
    totalViews: 75,
    weekKey: "2026-08-30",
  }, {
    dayKey: "sunday",
    weekKey: "2026-09-06",
  });
  assert.equal(result.sunday, 1);
  assert.equal(result.monday, 0);
  assert.equal(result.totalViews, 76);
});
