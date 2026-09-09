"use strict";

function signingDocumentCanAcceptRequest(invoice) {
  const status = String(invoice?.signatureStatus || "").trim();
  return status !== "signed" && status !== "signing";
}

function signingRequestIsActive({invoice, requestId, signingRequest}) {
  if (!invoice || !signingRequest || !requestId) return false;
  const requestStatus = String(signingRequest.status || "").trim();
  return String(invoice.signingRequestId || "").trim() === requestId &&
    String(invoice.signatureStatus || "").trim() !== "signed" &&
    ["pending", "signing"].includes(requestStatus) &&
    String(invoice.storagePath || "").trim() ===
      String(signingRequest.storagePath || "").trim();
}

function signingClaimIsCurrent({
  invoice,
  requestId,
  signingRequest,
  signingAttemptId,
}) {
  return signingRequestIsActive({invoice, requestId, signingRequest}) &&
    String(invoice.signatureStatus || "").trim() === "signing" &&
    String(signingRequest.status || "").trim() === "signing" &&
    String(signingRequest.signingAttemptId || "").trim() === signingAttemptId;
}

module.exports = {
  signingClaimIsCurrent,
  signingDocumentCanAcceptRequest,
  signingRequestIsActive,
};
