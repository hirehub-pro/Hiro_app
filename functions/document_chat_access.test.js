"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  DOCUMENT_CHAT_ACCESS_ID_PATTERN,
  createDocumentChatAccessId,
  documentChatAccessAllows,
  isDocumentChatAccessId,
} = require("./document_chat_access");

test("creates random URL-safe document chat access IDs", () => {
  const first = createDocumentChatAccessId();
  const second = createDocumentChatAccessId();

  assert.match(first, DOCUMENT_CHAT_ACCESS_ID_PATTERN);
  assert.match(second, DOCUMENT_CHAT_ACCESS_ID_PATTERN);
  assert.notEqual(first, second);
});

test("rejects malformed document chat access IDs", () => {
  assert.equal(isDocumentChatAccessId("a".repeat(43)), true);
  assert.equal(isDocumentChatAccessId("short"), false);
  assert.equal(isDocumentChatAccessId("/".repeat(43)), false);
  assert.equal(isDocumentChatAccessId(null), false);
});

test("allows only the grant owner and intended recipient", () => {
  const access = {ownerId: "worker-1", recipientId: "client-1"};

  assert.equal(documentChatAccessAllows(access, "worker-1"), true);
  assert.equal(documentChatAccessAllows(access, "client-1"), true);
  assert.equal(documentChatAccessAllows(access, "stranger"), false);
  assert.equal(documentChatAccessAllows(access, ""), false);
});
