"use strict";

const TERMINAL_INVOICE_EMAIL_STATUSES = new Set([
  "sending",
  "sent",
  "skipped",
  "failed",
]);

function normalizeEmail(value) {
  const email = value == null ? "" : String(value).trim().toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}

function isTerminalInvoiceEmailStatus(value) {
  return TERMINAL_INVOICE_EMAIL_STATUSES.has(
      value == null ? "" : String(value).trim().toLowerCase(),
  );
}

function buildInvoiceEmailDeliveries({
  clientEmail,
  businessName,
}) {
  const normalizedClientEmail = normalizeEmail(clientEmail);
  if (!normalizedClientEmail) return [];

  return [{
    email: normalizedClientEmail,
    subjectName: businessName,
    subjectPreposition: "מ",
    type: "client",
  }];
}

async function sendInvoiceEmailDeliveries(deliveries, sendDelivery) {
  const emailIds = [];
  for (const delivery of deliveries) {
    const emailId = await sendDelivery(delivery);
    if (emailId) emailIds.push(emailId);
  }
  return emailIds;
}

function buildSentInvoiceEmailUpdate(emailIds, sentAt, deleteErrorValue) {
  return {
    invoiceEmailStatus: "sent",
    invoiceEmailSentAt: sentAt,
    invoiceEmailId: emailIds[0] || null,
    invoiceEmailIds: emailIds,
    invoiceEmailError: deleteErrorValue,
  };
}

function buildFailedInvoiceEmailUpdate(error) {
  return {
    invoiceEmailStatus: "failed",
    invoiceEmailError: error instanceof Error ? error.message : String(error),
  };
}

module.exports = {
  buildFailedInvoiceEmailUpdate,
  buildInvoiceEmailDeliveries,
  buildSentInvoiceEmailUpdate,
  isTerminalInvoiceEmailStatus,
  sendInvoiceEmailDeliveries,
};
