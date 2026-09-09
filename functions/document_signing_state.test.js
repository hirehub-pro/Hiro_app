"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  signingClaimIsCurrent,
  signingDocumentCanAcceptRequest,
  signingRequestIsActive,
} = require("./document_signing_state");

const storagePath = "invoices/worker/server_document_quote_1.pdf";

test("does not create another signing link while signing or after signing", () => {
  assert.equal(signingDocumentCanAcceptRequest({signatureStatus: "pending"}), true);
  assert.equal(signingDocumentCanAcceptRequest({signatureStatus: "signing"}), false);
  assert.equal(signingDocumentCanAcceptRequest({signatureStatus: "signed"}), false);
});

test("only the request selected by the document remains active", () => {
  const invoice = {
    signatureStatus: "pending",
    signingRequestId: "new-request",
    storagePath,
  };
  const signingRequest = {status: "pending", storagePath};

  assert.equal(signingRequestIsActive({
    invoice,
    requestId: "new-request",
    signingRequest,
  }), true);
  assert.equal(signingRequestIsActive({
    invoice,
    requestId: "old-request",
    signingRequest,
  }), false);
});

test("a signing claim must own both the request and document locks", () => {
  const invoice = {
    signatureStatus: "signing",
    signingRequestId: "request-id",
    storagePath,
  };
  const signingRequest = {
    status: "signing",
    signingAttemptId: "attempt-id",
    storagePath,
  };

  assert.equal(signingClaimIsCurrent({
    invoice,
    requestId: "request-id",
    signingRequest,
    signingAttemptId: "attempt-id",
  }), true);
  assert.equal(signingClaimIsCurrent({
    invoice,
    requestId: "request-id",
    signingRequest,
    signingAttemptId: "different-attempt",
  }), false);
});
