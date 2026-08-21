"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  PUBLIC_WORKER_PROFILE_COLLECTION,
  buildPublicWorkerProfile,
  hasSearchEntitlement,
} = require("./public_worker_profile");

test("builds a bounded public worker profile with public contact fields", () => {
  const profile = buildPublicWorkerProfile("worker-1", {
    role: "worker",
    name: "Ada",
    email: "private@example.com",
    phone: "+972500000000",
    subscriptionPurchaseToken: "private-token",
    subscriptionStatus: "active",
    subscriptionExpiresAt: "2027-01-01T00:00:00.000Z",
    professions: ["Electrician"],
    lat: 32.0852999,
    lng: 34.7817676,
    avgRating: 4.8,
  }, new Date("2026-08-20T00:00:00.000Z"));

  assert.equal(PUBLIC_WORKER_PROFILE_COLLECTION, "publicWorkerProfiles");
  assert.equal(profile.uid, "worker-1");
  assert.equal(profile.isSearchVisible, true);
  assert.equal(profile.lat, 32.0852999);
  assert.equal(profile.lng, 34.7817676);
  assert.equal(profile.email, "private@example.com");
  assert.equal(profile.phone, "+972500000000");
  assert.equal("hideSchedule" in profile, false);
  assert.equal("isInsured" in profile, false);
  assert.equal("subscriptionStatus" in profile, false);
  assert.equal("subscriptionPurchaseToken" in profile, false);
});

test("only active workers or VIP workers are visible", () => {
  const now = new Date("2026-08-20T00:00:00.000Z");
  assert.equal(hasSearchEntitlement({subscriptionStatus: "inactive"}, now), false);
  assert.equal(hasSearchEntitlement({isVIP: true}, now), true);
  assert.equal(hasSearchEntitlement({
    subscriptionStatus: "active",
    subscriptionExpiresAt: "2026-08-19T00:00:00.000Z",
  }, now), false);
  assert.equal(hasSearchEntitlement({
    subscriptionStatus: "active_canceled",
    subscriptionExpiresAt: "2026-08-21T00:00:00.000Z",
  }, now), true);
});

test("does not project non-worker accounts", () => {
  assert.equal(buildPublicWorkerProfile("customer-1", {
    role: "customer",
    subscriptionStatus: "active",
  }), null);
});
