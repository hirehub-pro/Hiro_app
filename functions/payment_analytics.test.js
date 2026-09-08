"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  financialAnalyticsEntry,
  paymentAnalyticsEntry,
  paymentAnalyticsSnapshot,
  paymentAnalyticsYearMode,
  paymentMonthDocumentId,
} = require("./payment_analytics");

test("maps receipts to their document month and year", () => {
  assert.deepEqual(paymentAnalyticsEntry({
    docType: "receipt",
    date: "2026-09-08",
    finalTotal: 123.456,
  }), {
    year: 2026,
    month: 9,
    delta: 123.46,
  });
  assert.equal(paymentMonthDocumentId(9), "month_09");
});

test("subtracts negative receipts", () => {
  assert.equal(paymentAnalyticsEntry({
    docType: "receipt",
    date: "2026-09-08",
    finalTotal: 75,
    isNegativeReceipt: true,
  }).delta, -75);
});

test("includes invoice-receipts but excludes invoices and credit notes", () => {
  assert.equal(paymentAnalyticsEntry({
    docType: "invoice_receipt",
    date: "2026-09-08",
    finalTotal: 200,
  }).delta, 200);
  assert.equal(paymentAnalyticsEntry({
    docType: "invoice",
    date: "2026-09-08",
    finalTotal: 200,
  }), null);
  assert.equal(paymentAnalyticsEntry({
    docType: "credit_note",
    date: "2026-09-08",
    finalTotal: 200,
  }), null);
});

test("tracks VAT for invoices and subtracts tax invoice credits", () => {
  assert.deepEqual(financialAnalyticsEntry({
    docType: "invoice",
    date: "2026-09-08",
    finalTotal: 118,
    vatAmount: 18,
  }), {
    year: 2026,
    month: 9,
    paymentDelta: 0,
    vatDelta: 18,
  });
  assert.equal(financialAnalyticsEntry({
    docType: "invoice_receipt",
    date: "2026-09-08",
    finalTotal: 118,
    vatAmount: 18,
  }).vatDelta, 18);
  assert.equal(financialAnalyticsEntry({
    docType: "credit_note",
    date: "2026-09-08",
    finalTotal: 118,
    vatAmount: 18,
  }).vatDelta, -18);
  assert.equal(financialAnalyticsEntry({
    docType: "receipt",
    date: "2026-09-08",
    finalTotal: 118,
    vatAmount: 18,
  }).vatDelta, 0);
});

test("rejects invalid payment totals and dates", () => {
  assert.throws(() => paymentAnalyticsEntry({
    docType: "receipt",
    date: "invalid",
    finalTotal: 10,
  }), /valid document date/);
  assert.throws(() => paymentAnalyticsEntry({
    docType: "receipt",
    date: "2026-09-08",
    finalTotal: -1,
  }), /non-negative/);
});

test("selects safe yearly reset behavior", () => {
  assert.equal(paymentAnalyticsYearMode(2026, undefined), "reset");
  assert.equal(paymentAnalyticsYearMode(2026, 2025), "reset");
  assert.equal(paymentAnalyticsYearMode(2026, 2026), "current");
  assert.equal(paymentAnalyticsYearMode(2025, 2026), "historical");
});

test("rebuilds current-year and all-time totals from finalized payments", () => {
  const snapshot = paymentAnalyticsSnapshot([
    {docType: "receipt", documentStatus: "finalized", date: "20260102", amount: 100},
    {docType: "invoice_receipt", documentStatus: "finalized", date: "2026-01-03", amount: 50, vatAmount: 9},
    {docType: "receipt", documentStatus: "finalized", date: "2026-01-04", amount: -25},
    {docType: "receipt", documentStatus: "finalized", date: "2025-12-31", amount: 40},
    {docType: "invoice", documentStatus: "finalized", date: "2026-01-05", amount: 900, vatAmount: 162},
    {docType: "credit_note", documentStatus: "finalized", date: "2026-01-07", amount: 118, vatAmount: 18},
    {docType: "invoice", documentStatus: "finalized", date: "2025-12-30", amount: 47, vatAmount: 7},
    {docType: "receipt", documentStatus: "processing", date: "2026-01-06", amount: 500},
  ], 2026);

  assert.equal(snapshot.months[0], 125);
  assert.equal(snapshot.currentYearTotal, 125);
  assert.equal(snapshot.allTimeTotal, 165);
  assert.equal(snapshot.vatMonths[0], 153);
  assert.equal(snapshot.currentYearVat, 153);
  assert.equal(snapshot.allTimeVat, 160);
});
