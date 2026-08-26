"use strict";

const DOCUMENT_TYPE_CODES = Object.freeze({
  transaction_account: 300,
  invoice: 305,
  invoice_receipt: 320,
  credit_note: 330,
  receipt: 400,
});

function digitsOnly(value) {
  return String(value == null ? "" : value).replace(/[^0-9]/g, "");
}

function normalizeCompactDate(value, label = "date") {
  const digits = digitsOnly(value);
  if (digits.length !== 8) {
    throw new Error(`${label} must contain exactly 8 digits.`);
  }
  const year = Number(digits.slice(0, 4));
  const month = Number(digits.slice(4, 6));
  const day = Number(digits.slice(6, 8));
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (parsed.getUTCFullYear() !== year || parsed.getUTCMonth() !== month - 1 ||
      parsed.getUTCDate() !== day) {
    throw new Error(`${label} is not a valid calendar date.`);
  }
  return digits;
}

function compactDateToDate(value, label = "date") {
  const compact = normalizeCompactDate(value, label);
  return new Date(Date.UTC(
      Number(compact.slice(0, 4)),
      Number(compact.slice(4, 6)) - 1,
      Number(compact.slice(6, 8)),
  ));
}

function amountToAgorot(value, label = "amount") {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric < 0) {
    throw new Error(`${label} must be a non-negative finite amount.`);
  }
  const agorot = Math.round((numeric + Number.EPSILON) * 100);
  if (!Number.isSafeInteger(agorot)) {
    throw new Error(`${label} is outside the supported range.`);
  }
  return agorot;
}

function buildClientLedgerPosting({userId, document, sourceDocumentPath}) {
  const data = document && typeof document === "object" ? document : {};
  const client = data.client && typeof data.client === "object" ? data.client : {};
  const clientId = String(client.savedClientId || data.savedClientId || "").trim();
  if (!clientId) return null;
  if (clientId.length > 180 || clientId.includes("/")) {
    throw new Error("The saved client ID is invalid for a ledger posting.");
  }

  const docType = String(data.docType || data.type || "").trim();
  const documentType = DOCUMENT_TYPE_CODES[docType];
  if (!documentType) return null;
  const sourceDocumentId = String(data.invoiceDocId || data.sourceDocumentId || "")
      .trim();
  if (!sourceDocumentId || sourceDocumentId.length > 180 ||
      sourceDocumentId.includes("/")) {
    throw new Error("The source document ID is invalid for a ledger posting.");
  }
  const accountKey = String(client.externalClientNumber ||
    data.externalClientNumber || "").trim();
  if (!/^\d{1,15}$/.test(accountKey)) {
    throw new Error("A valid customer account key is required for a ledger posting.");
  }

  const documentDate = normalizeCompactDate(data.date, "document date");
  const totalAgorot = amountToAgorot(
      Math.abs(Number(data.finalTotal ?? data.amount)),
      "document total",
  );
  let debitAgorot = 0;
  let creditAgorot = 0;
  if (["invoice", "transaction_account"].includes(docType)) {
    debitAgorot = totalAgorot;
  } else if (docType === "invoice_receipt") {
    debitAgorot = totalAgorot;
    creditAgorot = totalAgorot;
  } else if (docType === "credit_note") {
    creditAgorot = totalAgorot;
  } else if (data.isNegativeReceipt === true) {
    debitAgorot = totalAgorot;
  } else {
    creditAgorot = totalAgorot;
  }

  const normalizedUserId = String(userId || "").trim();
  const normalizedSourcePath = String(sourceDocumentPath || "").trim();
  if (!normalizedUserId || !normalizedSourcePath.startsWith(
      `users/${normalizedUserId}/invoices/`)) {
    throw new Error("The ledger source document path is invalid.");
  }
  const reversalOf = data.isNegativeReceipt === true ?
    String(data.cancellationSourceDocumentId || "").trim() || null : null;
  return {
    userId: normalizedUserId,
    clientId,
    accountKey,
    effectiveDate: compactDateToDate(documentDate),
    documentDate,
    documentType,
    documentKind: docType,
    documentNumber: String(data.documentNumber || data.invoiceNumber || "").trim(),
    debitAgorot,
    creditAgorot,
    sourceDocumentId,
    sourceDocumentPath: normalizedSourcePath,
    reversalOf,
  };
}

function entryCompactDate(entry) {
  if (entry?.effectiveDate && typeof entry.effectiveDate.toDate === "function") {
    return normalizeCompactDate(entry.effectiveDate.toDate().toISOString().slice(0, 10));
  }
  if (entry?.effectiveDate instanceof Date) {
    return normalizeCompactDate(entry.effectiveDate.toISOString().slice(0, 10));
  }
  return normalizeCompactDate(entry?.documentDate, "ledger entry date");
}

function safeAgorot(value, label) {
  const numeric = Number(value);
  if (!Number.isSafeInteger(numeric) || numeric < 0) {
    throw new Error(`${label} must be a non-negative integer amount in agorot.`);
  }
  return numeric;
}

function aggregateClientLedgerEntries(entries, {fromDate, toDate}) {
  const compactFrom = normalizeCompactDate(fromDate, "fromDate");
  const compactTo = normalizeCompactDate(toDate, "toDate");
  if (compactFrom > compactTo) throw new Error("The ledger date range is invalid.");
  let openingAgorot = 0;
  let periodDebitAgorot = 0;
  let periodCreditAgorot = 0;
  for (const entry of entries || []) {
    const date = entryCompactDate(entry);
    if (date > compactTo) continue;
    const debit = safeAgorot(entry.debitAgorot, "Ledger debit");
    const credit = safeAgorot(entry.creditAgorot, "Ledger credit");
    if (date < compactFrom) {
      openingAgorot += debit - credit;
    } else {
      periodDebitAgorot += debit;
      periodCreditAgorot += credit;
    }
    if (![openingAgorot, periodDebitAgorot, periodCreditAgorot]
        .every(Number.isSafeInteger)) {
      throw new Error("The customer ledger totals exceed the supported range.");
    }
  }
  return {
    openingBalance: openingAgorot / 100,
    periodDebits: periodDebitAgorot / 100,
    periodCredits: periodCreditAgorot / 100,
  };
}

module.exports = {
  DOCUMENT_TYPE_CODES,
  aggregateClientLedgerEntries,
  amountToAgorot,
  buildClientLedgerPosting,
  compactDateToDate,
  normalizeCompactDate,
};
