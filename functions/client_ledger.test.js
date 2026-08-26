"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  aggregateClientLedgerEntries,
  buildClientLedgerPosting,
} = require("./client_ledger");

function document(docType, overrides = {}) {
  return {
    docType,
    invoiceDocId: `${docType}_2026-0001`,
    documentNumber: "2026-0001",
    date: "2026-08-25",
    finalTotal: 118,
    client: {
      savedClientId: "client-1",
      externalClientNumber: "1001",
    },
    ...overrides,
  };
}

function posting(docType, overrides = {}) {
  const source = document(docType, overrides);
  return buildClientLedgerPosting({
    userId: "worker-1",
    document: source,
    sourceDocumentPath: `users/worker-1/invoices/${source.invoiceDocId}`,
  });
}

test("maps finalized documents to customer debit and credit postings", () => {
  assert.deepEqual(
      ["invoice", "transaction_account"].map((type) => {
        const result = posting(type);
        return [result.debitAgorot, result.creditAgorot];
      }),
      [[11800, 0], [11800, 0]],
  );
  assert.deepEqual(
      ["credit_note", "receipt"].map((type) => {
        const result = posting(type);
        return [result.debitAgorot, result.creditAgorot];
      }),
      [[0, 11800], [0, 11800]],
  );
  const invoiceReceipt = posting("invoice_receipt");
  assert.deepEqual(
      [invoiceReceipt.debitAgorot, invoiceReceipt.creditAgorot],
      [11800, 11800],
  );
});

test("creates a reversing debit for a cancelled receipt", () => {
  const result = posting("receipt", {
    isNegativeReceipt: true,
    cancellationSourceDocumentId: "receipt_2026-0000",
  });
  assert.equal(result.debitAgorot, 11800);
  assert.equal(result.creditAgorot, 0);
  assert.equal(result.reversalOf, "receipt_2026-0000");
});

test("uses a null posting for documents without a saved client", () => {
  assert.equal(posting("invoice", {client: {externalClientNumber: "1001"}}), null);
  assert.equal(posting("quote"), null);
});

test("calculates B110 opening, debit, and credit amounts by date", () => {
  const totals = aggregateClientLedgerEntries([
    {documentDate: "20260701", debitAgorot: 50000, creditAgorot: 0},
    {documentDate: "20260720", debitAgorot: 0, creditAgorot: 12500},
    {documentDate: "20260801", debitAgorot: 11800, creditAgorot: 0},
    {documentDate: "20260815", debitAgorot: 0, creditAgorot: 6000},
    {documentDate: "20260901", debitAgorot: 99900, creditAgorot: 0},
  ], {fromDate: "20260801", toDate: "20260831"});
  assert.deepEqual(totals, {
    openingBalance: 375,
    periodDebits: 118,
    periodCredits: 60,
  });
});

test("rejects invalid account keys and non-integer stored agorot", () => {
  assert.throws(() => posting("invoice", {
    client: {savedClientId: "client-1", externalClientNumber: "ABC"},
  }), /account key/);
  assert.throws(() => aggregateClientLedgerEntries([
    {documentDate: "20260801", debitAgorot: 1.5, creditAgorot: 0},
  ], {fromDate: "20260801", toDate: "20260831"}), /integer amount/);
});
