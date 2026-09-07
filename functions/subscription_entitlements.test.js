"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  aggregateSubscriptionEntitlements,
  hasActiveProAccess,
  isAppleSubscriptionEntitled,
  isCurrentlyEntitled,
  isVerifiedAppleNotificationEntitlement,
  legacyEntitlements,
  resolveAppleSubscriptionExpiry,
  subscriptionAccountTokenForUid,
} = require("./subscription_entitlements");

const now = new Date("2026-09-06T12:00:00.000Z");

function entitlement(provider, expiresAt, options = {}) {
  return {
    provider,
    isSubscribed: options.isSubscribed ?? true,
    subscriptionStatus: options.status || "active",
    subscriptionCanceled: options.canceled ?? false,
    subscriptionExpiresAt: new Date(expiresAt),
    subscriptionProductId: options.productId || `${provider}_pro`,
  };
}

test("requires a future expiry even when provider status is active", () => {
  assert.equal(isCurrentlyEntitled(
      entitlement("google_play", "2026-09-06T11:59:59.000Z"),
      now,
  ), false);
});

test("uses Apple's grace expiry while billing grace period is active", () => {
  const expiry = resolveAppleSubscriptionExpiry({
    transactionExpiresDate: "2026-09-06T11:00:00.000Z",
    gracePeriodExpiresDate: "2026-09-22T11:00:00.000Z",
    renewalDate: "2026-09-06T11:00:00.000Z",
    isInBillingGracePeriod: true,
  });

  assert.equal(expiry.toISOString(), "2026-09-22T11:00:00.000Z");
});

test("does not use a stale grace date outside billing grace period", () => {
  const expiry = resolveAppleSubscriptionExpiry({
    transactionExpiresDate: "2026-10-06T11:00:00.000Z",
    gracePeriodExpiresDate: "2026-11-01T11:00:00.000Z",
    renewalDate: "2026-10-06T11:00:00.000Z",
    isInBillingGracePeriod: false,
  });

  assert.equal(expiry.toISOString(), "2026-10-06T11:00:00.000Z");
});

test("grace handling never shortens the regular paid period", () => {
  const expiry = resolveAppleSubscriptionExpiry({
    transactionExpiresDate: "2026-10-06T11:00:00.000Z",
    gracePeriodExpiresDate: "2026-09-22T11:00:00.000Z",
    renewalDate: "2026-10-06T11:00:00.000Z",
    isInBillingGracePeriod: true,
  });

  assert.equal(expiry.toISOString(), "2026-10-06T11:00:00.000Z");
});

test("falls back to Apple's renewal date when transaction expiry is absent", () => {
  const expiry = resolveAppleSubscriptionExpiry({
    gracePeriodExpiresDate: null,
    renewalDate: "2026-10-06T11:00:00.000Z",
    isInBillingGracePeriod: false,
  });

  assert.equal(expiry.toISOString(), "2026-10-06T11:00:00.000Z");
});

test("allows Apple active and billing-grace statuses before expiry", () => {
  const futureExpiry = new Date("2026-09-22T11:00:00.000Z");

  assert.equal(isAppleSubscriptionEntitled(1, futureExpiry, now), true);
  assert.equal(isAppleSubscriptionEntitled(4, futureExpiry, now), true);
});

test("denies Apple billing retry after grace and all expired access", () => {
  const futureExpiry = new Date("2026-09-22T11:00:00.000Z");
  const pastExpiry = new Date("2026-09-06T11:00:00.000Z");

  assert.equal(isAppleSubscriptionEntitled(3, futureExpiry, now), false);
  assert.equal(isAppleSubscriptionEntitled(2, futureExpiry, now), false);
  assert.equal(isAppleSubscriptionEntitled(5, futureExpiry, now), false);
  assert.equal(isAppleSubscriptionEntitled(4, pastExpiry, now), false);
});

test("accepts a fresh Apple notification entitlement before expiry", () => {
  const candidate = {
    ...entitlement("app_store", "2026-10-06T00:00:00.000Z", {
      productId: "hiro_subscription",
    }),
    subscriptionVerifiedAt: new Date("2026-09-06T11:55:00.000Z"),
  };

  assert.equal(isVerifiedAppleNotificationEntitlement(
      candidate,
      "hiro_subscription",
      now,
  ), true);
});

test("rejects an expired Apple entitlement even while verification is fresh", () => {
  const candidate = {
    ...entitlement("app_store", "2026-09-06T11:59:59.000Z", {
      productId: "hiro_subscription",
    }),
    subscriptionVerificationFreshUntil:
      new Date("2026-09-07T12:00:00.000Z"),
  };

  assert.equal(isVerifiedAppleNotificationEntitlement(
      candidate,
      "hiro_subscription",
      now,
  ), false);
});

test("rejects an Apple entitlement with no expiration", () => {
  const candidate = {
    ...entitlement("app_store", "2026-10-06T00:00:00.000Z", {
      productId: "hiro_subscription",
    }),
    subscriptionExpiresAt: null,
    subscriptionVerifiedAt: new Date("2026-09-06T11:55:00.000Z"),
  };

  assert.equal(isVerifiedAppleNotificationEntitlement(
      candidate,
      "hiro_subscription",
      now,
  ), false);
});

test("accepts a canceled Apple subscription until its paid period expires", () => {
  const candidate = {
    ...entitlement("app_store", "2026-10-06T00:00:00.000Z", {
      canceled: true,
      productId: "hiro_subscription",
      status: "active_canceled",
    }),
    subscriptionVerifiedAt: new Date("2026-09-06T11:55:00.000Z"),
  };

  assert.equal(isVerifiedAppleNotificationEntitlement(
      candidate,
      "hiro_subscription",
      now,
  ), true);
});

test("rejects the wrong provider, product, or stale verification", () => {
  const base = {
    ...entitlement("app_store", "2026-10-06T00:00:00.000Z", {
      productId: "hiro_subscription",
    }),
    subscriptionVerifiedAt: new Date("2026-09-06T11:00:00.000Z"),
  };

  assert.equal(isVerifiedAppleNotificationEntitlement(
      {...base, provider: "google_play"},
      "hiro_subscription",
      now,
  ), false);
  assert.equal(isVerifiedAppleNotificationEntitlement(
      {...base, subscriptionProductId: "different_product"},
      "hiro_subscription",
      now,
  ), false);
  assert.equal(isVerifiedAppleNotificationEntitlement(
      base,
      "hiro_subscription",
      now,
  ), false);
});

test("requires a worker entitlement for paid backend tools", () => {
  assert.equal(hasActiveProAccess({
    userData: {role: "worker"},
    entitlements: {
      app_store: entitlement("app_store", "2026-10-06T00:00:00.000Z"),
    },
  }, now), true);
  assert.equal(hasActiveProAccess({
    userData: {role: "worker"},
    entitlements: {
      app_store: entitlement("app_store", "2026-09-06T11:59:59.000Z"),
    },
  }, now), false);
  assert.equal(hasActiveProAccess({
    userData: {role: "customer", isVIP: true},
    entitlements: {},
  }, now), false);
  assert.equal(hasActiveProAccess({
    userData: {role: "worker", isVIP: true},
    entitlements: {},
  }, now), true);
});

test("keeps access when either provider remains entitled", () => {
  const result = aggregateSubscriptionEntitlements({
    google_play: entitlement("google_play", "2026-09-05T00:00:00.000Z", {
      isSubscribed: false,
      status: "inactive",
    }),
    app_store: entitlement("app_store", "2026-10-06T00:00:00.000Z"),
  }, now);

  assert.equal(result.isSubscribed, true);
  assert.equal(result.subscriptionPlatform, "app_store");
  assert.deepEqual(result.subscriptionPlatforms, ["app_store"]);
});

test("a refund on one provider cannot revoke the other provider", () => {
  const result = aggregateSubscriptionEntitlements({
    app_store: entitlement("app_store", "2026-10-06T00:00:00.000Z", {
      isSubscribed: false,
      status: "inactive",
    }),
    google_play: entitlement("google_play", "2026-09-20T00:00:00.000Z"),
  }, now);

  assert.equal(result.isSubscribed, true);
  assert.equal(result.subscriptionPlatform, "google_play");
});

test("reports active_canceled when all live entitlements stop renewing", () => {
  const result = aggregateSubscriptionEntitlements({
    app_store: entitlement("app_store", "2026-10-06T00:00:00.000Z", {
      canceled: true,
      status: "active_canceled",
    }),
  }, now);

  assert.equal(result.isSubscribed, true);
  assert.equal(result.subscriptionStatus, "active_canceled");
  assert.equal(result.subscriptionCanceled, true);
});

test("selects the live entitlement with the latest expiry", () => {
  const result = aggregateSubscriptionEntitlements({
    app_store: entitlement("app_store", "2026-10-01T00:00:00.000Z"),
    google_play: entitlement("google_play", "2026-11-01T00:00:00.000Z"),
  }, now);

  assert.equal(result.subscriptionPlatform, "google_play");
  assert.deepEqual(result.subscriptionPlatforms, ["google_play", "app_store"]);
});

test("converts one legacy provider record for a safe pre-launch transition", () => {
  const converted = legacyEntitlements({
    subscriptionSource: "app_store",
    isSubscribed: true,
    subscriptionStatus: "active",
    subscriptionExpiresAt: new Date("2026-10-01T00:00:00.000Z"),
  });

  assert.equal(converted.app_store.isSubscribed, true);
  assert.equal(converted.google_play, undefined);
});

test("generates the same UUID-shaped account token as the Flutter client", () => {
  assert.equal(
      subscriptionAccountTokenForUid("test-user-123"),
      "8b374f5a-f4f2-5215-ada8-9afbe05ab8c1",
  );
});
