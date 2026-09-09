"use strict";

const crypto = require("crypto");

const DOCUMENT_CHAT_ACCESS_ID_PATTERN = /^[A-Za-z0-9_-]{43}$/;

/**
 * Creates an unguessable identifier for an authenticated chat access grant.
 * The identifier is not sufficient to download a document by itself.
 *
 * @return {string}
 */
function createDocumentChatAccessId() {
  return crypto.randomBytes(32).toString("base64url");
}

/**
 * @param {unknown} value
 * @return {boolean}
 */
function isDocumentChatAccessId(value) {
  return typeof value === "string" &&
    DOCUMENT_CHAT_ACCESS_ID_PATTERN.test(value.trim());
}

/**
 * @param {{ownerId?: unknown, recipientId?: unknown}} access
 * @param {unknown} userId
 * @return {boolean}
 */
function documentChatAccessAllows(access, userId) {
  const uid = typeof userId === "string" ? userId.trim() : "";
  if (!uid) return false;
  return uid === String(access?.ownerId || "").trim() ||
    uid === String(access?.recipientId || "").trim();
}

module.exports = {
  DOCUMENT_CHAT_ACCESS_ID_PATTERN,
  createDocumentChatAccessId,
  documentChatAccessAllows,
  isDocumentChatAccessId,
};
