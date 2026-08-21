"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {sumPublicProfileViews} = require("./public_profile_stats");

test("sums only valid positive public profile view totals", () => {
  assert.equal(sumPublicProfileViews([
    {totalViews: 12},
    {totalViews: 8.9},
    {totalViews: -4},
    {totalViews: "invalid"},
    {},
  ]), 20);
});

test("returns zero when profile view data is unavailable", () => {
  assert.equal(sumPublicProfileViews(null), 0);
});
