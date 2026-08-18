"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  TAX_AUTHORITY_TOKEN_COLLECTION,
  taxAuthorityTokenDocumentPath,
} = require("./tax_authority_token_security");

test("stores Tax Authority tokens only in the server collection", () => {
  assert.equal(TAX_AUTHORITY_TOKEN_COLLECTION, "taxAuthorityOAuthTokens");
  assert.equal(
      taxAuthorityTokenDocumentPath("firebase-user-123"),
      "taxAuthorityOAuthTokens/firebase-user-123",
  );
  assert.equal(
      taxAuthorityTokenDocumentPath("firebase-user-123")
          .startsWith("users/"),
      false,
  );
});

test("rejects invalid token document user IDs", () => {
  for (const userId of ["", "user/another-document", null, 123]) {
    assert.throws(
        () => taxAuthorityTokenDocumentPath(userId),
        /valid Firebase user ID/i,
    );
  }
});
