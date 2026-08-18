"use strict";

const TAX_AUTHORITY_TOKEN_COLLECTION = "taxAuthorityOAuthTokens";

function taxAuthorityTokenDocumentPath(userId) {
  if (typeof userId !== "string" ||
      userId.length < 1 ||
      userId.length > 128 ||
      userId.includes("/")) {
    throw new TypeError("A valid Firebase user ID is required.");
  }
  return `${TAX_AUTHORITY_TOKEN_COLLECTION}/${userId}`;
}

module.exports = {
  TAX_AUTHORITY_TOKEN_COLLECTION,
  taxAuthorityTokenDocumentPath,
};
