"use strict";

const crypto = require("crypto");

const DOCUMENT_DOWNLOAD_TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

/**
 * Creates a 256-bit bearer token for a document download link.
 *
 * @return {string}
 */
function createDocumentDownloadToken() {
  return crypto.randomBytes(32).toString("base64url");
}

/**
 * Stores and looks up only a SHA-256 digest, never the bearer token itself.
 *
 * @param {string} token
 * @return {string}
 */
function hashDocumentDownloadToken(token) {
  return crypto.createHash("sha256").update(token).digest("hex");
}

/**
 * Reads the token from a branded Hosting path or a direct function query.
 *
 * @param {{path?: unknown, query?: object}} request
 * @return {string}
 */
function documentDownloadTokenFromRequest(request) {
  const pathToken = String(request?.path || "")
      .split("/")
      .filter(Boolean)
      .pop();
  const queryToken = request?.query?.token;
  const token = String(queryToken || pathToken || "").trim();
  return DOCUMENT_DOWNLOAD_TOKEN_PATTERN.test(token) ? token : "";
}

/**
 * Builds the stable branded URL placed in the email.
 *
 * @param {string} origin
 * @param {string} token
 * @return {string}
 */
function documentDownloadUrl(origin, token) {
  if (!DOCUMENT_DOWNLOAD_TOKEN_PATTERN.test(token)) {
    throw new Error("Invalid document download token.");
  }
  return `${String(origin).replace(/\/+$/, "")}/document-download/${token}`;
}

module.exports = {
  DOCUMENT_DOWNLOAD_TOKEN_PATTERN,
  createDocumentDownloadToken,
  documentDownloadTokenFromRequest,
  documentDownloadUrl,
  hashDocumentDownloadToken,
};
