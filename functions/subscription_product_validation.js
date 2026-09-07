"use strict";

const APPLE_SUBSCRIPTION_PRODUCT_ID = "HIRO_SUBSCRIPTION";
const GOOGLE_PLAY_SUBSCRIPTION_PRODUCT_IDS = new Set([
  "pro_worker_monthly",
  "com-hiro-app-pro-worker-monthly",
]);
const GOOGLE_PLAY_LOOKUP_NOT_FOUND = "not_found";

function normalizedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function googlePlayReturnedProductIds(playState) {
  return (playState?.lineItems || [])
      .map((item) => normalizedString(item?.productId))
      .filter(Boolean);
}

function hasAllowedGooglePlayProduct(playState) {
  const productIds = googlePlayReturnedProductIds(playState);
  return productIds.some((id) => GOOGLE_PLAY_SUBSCRIPTION_PRODUCT_IDS.has(id));
}

function hasAllowedAppleProduct({transaction, renewalInfo}) {
  const productIds = [
    transaction?.productId,
    renewalInfo?.productId,
    renewalInfo?.autoRenewProductId,
  ].map(normalizedString).filter(Boolean);
  return productIds.includes(APPLE_SUBSCRIPTION_PRODUCT_ID);
}

function isGooglePlayLookupNotFound(playState) {
  return playState?.purchaseLookupStatus === GOOGLE_PLAY_LOOKUP_NOT_FOUND;
}

module.exports = {
  APPLE_SUBSCRIPTION_PRODUCT_ID,
  GOOGLE_PLAY_LOOKUP_NOT_FOUND,
  GOOGLE_PLAY_SUBSCRIPTION_PRODUCT_IDS,
  googlePlayReturnedProductIds,
  hasAllowedAppleProduct,
  hasAllowedGooglePlayProduct,
  isGooglePlayLookupNotFound,
};
