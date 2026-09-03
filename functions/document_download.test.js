"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  DOCUMENT_DOWNLOAD_TOKEN_PATTERN,
  createDocumentDownloadToken,
  documentDownloadTokenFromRequest,
  documentDownloadUrl,
  hashDocumentDownloadToken,
} = require("./document_download");

test("creates random 256-bit URL-safe download tokens", () => {
  const first = createDocumentDownloadToken();
  const second = createDocumentDownloadToken();

  assert.match(first, DOCUMENT_DOWNLOAD_TOKEN_PATTERN);
  assert.match(second, DOCUMENT_DOWNLOAD_TOKEN_PATTERN);
  assert.notEqual(first, second);
});

test("hashes a token without retaining the bearer value", () => {
  const token = "a".repeat(43);
  const digest = hashDocumentDownloadToken(token);

  assert.match(digest, /^[a-f0-9]{64}$/);
  assert.notEqual(digest, token);
  assert.equal(hashDocumentDownloadToken(token), digest);
});

test("reads tokens from the Hosting path or direct function query", () => {
  const token = "A".repeat(43);

  assert.equal(documentDownloadTokenFromRequest({
    path: `/document-download/${token}`,
    query: {},
  }), token);
  assert.equal(documentDownloadTokenFromRequest({
    path: "/",
    query: {token},
  }), token);
  assert.equal(documentDownloadTokenFromRequest({
    path: "/document-download/not-valid",
    query: {},
  }), "");
});

test("builds a branded download URL without a double slash", () => {
  const token = "_".repeat(43);

  assert.equal(
      documentDownloadUrl("https://hiro-services.com/", token),
      `https://hiro-services.com/document-download/${token}`,
  );
});
