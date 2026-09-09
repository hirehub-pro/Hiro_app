"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  createSigningAccessCode,
  normalizeSigningAccessCode,
  signingAccessCodeMatches,
  signingAccessSessionHash,
  signingAccessSessionMatches,
} = require("./document_signing_access");

test("creates a human-readable access code and stores only its hash", () => {
  const access = createSigningAccessCode();
  assert.match(access.code, /^[A-Z2-9]{4}-[A-Z2-9]{4}$/);
  assert.match(access.salt, /^[A-Za-z0-9_-]+$/);
  assert.match(access.hash, /^[a-f0-9]{64}$/);
  assert.equal(signingAccessCodeMatches(access.code, access.salt, access.hash), true);
  assert.equal(signingAccessCodeMatches("AAAA-AAAA", access.salt, access.hash), false);
});

test("normalizes spaces and separators in an access code", () => {
  assert.equal(normalizeSigningAccessCode(" abcd - 2345 "), "ABCD2345");
});

test("validates a signing access session without storing its token", () => {
  const token = "A".repeat(43);
  const hash = signingAccessSessionHash(token);
  assert.equal(signingAccessSessionMatches(token, hash), true);
  assert.equal(signingAccessSessionMatches("B".repeat(43), hash), false);
});
