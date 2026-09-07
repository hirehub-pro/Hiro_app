"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  GOOGLE_PLAY_LOOKUP_NOT_FOUND,
  hasAllowedAppleProduct,
  hasAllowedGooglePlayProduct,
  isGooglePlayLookupNotFound,
} = require("./subscription_product_validation");

test("accepts a Google product returned by Google Play", () => {
  assert.equal(hasAllowedGooglePlayProduct({
    lineItems: [{productId: "pro_worker_monthly"}],
  }), true);
});

test("rejects an unrelated product returned by Google Play", () => {
  assert.equal(hasAllowedGooglePlayProduct({
    lineItems: [{productId: "unrelated_subscription"}],
  }), false);
});

test("rejects an empty Google response instead of trusting a client fallback", () => {
  assert.equal(hasAllowedGooglePlayProduct({lineItems: []}), false);
});

test("recognizes only explicit Google not-found lookup results", () => {
  assert.equal(isGooglePlayLookupNotFound({
    purchaseLookupStatus: GOOGLE_PLAY_LOOKUP_NOT_FOUND,
    lineItems: [],
  }), true);
  assert.equal(isGooglePlayLookupNotFound({lineItems: []}), false);
});

test("accepts the Pro product returned in an Apple transaction", () => {
  assert.equal(hasAllowedAppleProduct({
    transaction: {productId: "HIRO_SUBSCRIPTION"},
  }), true);
});

test("rejects an unrelated product returned in an Apple transaction", () => {
  assert.equal(hasAllowedAppleProduct({
    transaction: {productId: "unrelated_subscription"},
  }), false);
});
