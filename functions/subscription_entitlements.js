"use strict";

const crypto = require("crypto");

const APP_STORE_PROVIDER = "app_store";
const GOOGLE_PLAY_PROVIDER = "google_play";
const SUBSCRIPTION_PROVIDERS = [APP_STORE_PROVIDER, GOOGLE_PLAY_PROVIDER];
const APPLE_STATUS_ACTIVE = 1;
const APPLE_STATUS_BILLING_GRACE_PERIOD = 4;

function subscriptionAccountTokenForUid(uid) {
  const hex = crypto.createHash("sha1")
      .update(`hirehub-subscription::${uid}`)
      .digest("hex")
      .padEnd(32, "0")
      .slice(0, 32)
      .split("");
  hex[12] = "5";
  hex[16] = ((Number.parseInt(hex[16], 16) & 0x3) | 0x8).toString(16);
  const normalized = hex.join("");
  return [
    normalized.slice(0, 8),
    normalized.slice(8, 12),
    normalized.slice(12, 16),
    normalized.slice(16, 20),
    normalized.slice(20, 32),
  ].join("-");
}

function asDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function normalizedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function entitlementExpiry(entitlement) {
  return asDate(entitlement?.subscriptionExpiresAt);
}

function resolveAppleSubscriptionExpiry({
  transactionExpiresDate,
  gracePeriodExpiresDate,
  renewalDate,
  isInBillingGracePeriod,
}) {
  const regularExpiry = asDate(transactionExpiresDate) || asDate(renewalDate);
  if (!isInBillingGracePeriod) return regularExpiry;

  const graceExpiry = asDate(gracePeriodExpiresDate);
  if (!graceExpiry) return regularExpiry;
  if (!regularExpiry || graceExpiry > regularExpiry) return graceExpiry;
  return regularExpiry;
}

function isAppleSubscriptionEntitled(status, expiry, now = new Date()) {
  const normalizedStatus = Number(status);
  const expiryDate = asDate(expiry);
  const statusAllowsAccess = normalizedStatus === APPLE_STATUS_ACTIVE ||
    normalizedStatus === APPLE_STATUS_BILLING_GRACE_PERIOD;
  return Boolean(statusAllowsAccess && expiryDate && expiryDate > now);
}

function isCurrentlyEntitled(entitlement, now = new Date()) {
  if (entitlement?.isSubscribed !== true) return false;
  const status = normalizedString(entitlement.subscriptionStatus).toLowerCase();
  if (status !== "active" && status !== "active_canceled") return false;
  const expiry = entitlementExpiry(entitlement);
  return Boolean(expiry && expiry > now);
}

function isVerifiedAppleNotificationEntitlement(
    entitlement,
    allowedProductId,
    now = new Date(),
    recentVerificationMs = 10 * 60 * 1000,
) {
  if (!isCurrentlyEntitled(entitlement, now)) return false;

  const provider = normalizedString(
      entitlement.provider ||
      entitlement.subscriptionSource ||
      entitlement.subscriptionPlatform,
  ).toLowerCase();
  if (provider !== APP_STORE_PROVIDER) return false;
  if (normalizedString(entitlement.subscriptionProductId) !==
      normalizedString(allowedProductId)) {
    return false;
  }

  const verifiedAt = asDate(entitlement.subscriptionVerifiedAt);
  const freshUntil = asDate(entitlement.subscriptionVerificationFreshUntil);
  const verificationAgeMs = verifiedAt ?
    now.getTime() - verifiedAt.getTime() :
    Number.POSITIVE_INFINITY;

  return Boolean(
      (freshUntil && freshUntil > now) ||
      (verificationAgeMs >= 0 && verificationAgeMs < recentVerificationMs),
  );
}

function hasActiveProAccess({userData, entitlements}, now = new Date()) {
  if (userData?.role !== "worker") return false;
  if (userData?.isVIP === true) return true;
  return SUBSCRIPTION_PROVIDERS.some((provider) =>
    isCurrentlyEntitled(entitlements?.[provider], now));
}

function compareByExpiry(left, right) {
  const leftTime = entitlementExpiry(left)?.getTime() || 0;
  const rightTime = entitlementExpiry(right)?.getTime() || 0;
  return rightTime - leftTime;
}

function aggregateSubscriptionEntitlements(entitlements, now = new Date()) {
  const records = SUBSCRIPTION_PROVIDERS
      .map((provider) => {
        const value = entitlements?.[provider];
        return value && typeof value === "object" ? {...value, provider} : null;
      })
      .filter(Boolean);
  const active = records
      .filter((record) => isCurrentlyEntitled(record, now))
      .sort(compareByExpiry);
  const primary = active[0] || records.sort(compareByExpiry)[0] || null;
  const isSubscribed = active.length > 0;
  const willRenew = active.some(
      (record) => record.subscriptionCanceled !== true,
  );

  return {
    isSubscribed,
    subscriptionStatus: !isSubscribed ? "inactive" :
      willRenew ? "active" : "active_canceled",
    subscriptionCanceled: !isSubscribed || !willRenew,
    subscriptionExpiresAt: isSubscribed ?
      active[0].subscriptionExpiresAt :
      primary?.subscriptionExpiresAt || null,
    subscriptionPlatforms: active.map((record) => record.provider),
    subscriptionPlatform: primary?.provider || null,
    subscriptionSource: primary?.provider || null,
    subscriptionProductId: primary?.subscriptionProductId || null,
    subscriptionProviderState: primary?.subscriptionProviderState || null,
    subscriptionPurchaseOrderId:
      primary?.subscriptionPurchaseOrderId || null,
    subscriptionPurchaseToken: primary?.subscriptionPurchaseToken || null,
    subscriptionAccountToken: primary?.subscriptionAccountToken || null,
    subscriptionOwnershipKey: primary?.subscriptionOwnershipKey || null,
    subscriptionOriginalTransactionId:
      primary?.subscriptionOriginalTransactionId || null,
    subscriptionTransactionId: primary?.subscriptionTransactionId || null,
  };
}

function legacyEntitlements(userData) {
  if (!userData || typeof userData !== "object") return {};
  const provider = normalizedString(
      userData.subscriptionSource || userData.subscriptionPlatform,
  ).toLowerCase();
  if (!SUBSCRIPTION_PROVIDERS.includes(provider)) return {};

  return {
    [provider]: {
      provider,
      isSubscribed: userData.isSubscribed === true,
      subscriptionStatus: userData.subscriptionStatus || "inactive",
      subscriptionCanceled: userData.subscriptionCanceled === true,
      subscriptionExpiresAt: userData.subscriptionExpiresAt || null,
      subscriptionProductId: userData.subscriptionProductId || null,
      subscriptionProviderState: userData.subscriptionProviderState || null,
      subscriptionPurchaseOrderId:
        userData.subscriptionPurchaseOrderId || null,
      subscriptionPurchaseToken: userData.subscriptionPurchaseToken || null,
      subscriptionAccountToken: userData.subscriptionAccountToken || null,
      subscriptionOwnershipKey: userData.subscriptionOwnershipKey || null,
      subscriptionOriginalTransactionId:
        userData.subscriptionOriginalTransactionId || null,
      subscriptionTransactionId: userData.subscriptionTransactionId || null,
    },
  };
}

module.exports = {
  APP_STORE_PROVIDER,
  GOOGLE_PLAY_PROVIDER,
  SUBSCRIPTION_PROVIDERS,
  aggregateSubscriptionEntitlements,
  hasActiveProAccess,
  isAppleSubscriptionEntitled,
  isCurrentlyEntitled,
  isVerifiedAppleNotificationEntitlement,
  legacyEntitlements,
  resolveAppleSubscriptionExpiry,
  subscriptionAccountTokenForUid,
};
