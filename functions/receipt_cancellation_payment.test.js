"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {receiptCancellationPayment} =
  require("./receipt_cancellation_payment");

test("moves a cancelled receipt amount from paid back to remaining", () => {
  assert.deepEqual(receiptCancellationPayment({
    invoiceAmount: 2000,
    previousPaidAmount: 2000,
    cancellationAmount: 500,
  }), {
    paidAmount: 1500,
    paymentStatus: "partial",
  });
});

test("does not reduce invoice payments below zero", () => {
  assert.deepEqual(receiptCancellationPayment({
    invoiceAmount: 2000,
    previousPaidAmount: 500,
    cancellationAmount: 1000,
  }), {
    paidAmount: 0,
    paymentStatus: "unpaid",
  });
});
