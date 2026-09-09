"use strict";

function money(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

/// Reverses a receipt payment against its linked invoice without allowing the
/// invoice balance to become negative.
function receiptCancellationPayment({
  invoiceAmount,
  previousPaidAmount,
  cancellationAmount,
}) {
  const total = Math.abs(Number(invoiceAmount) || 0);
  const paid = Math.min(total, Math.max(0, Number(previousPaidAmount) || 0));
  const reversal = Math.abs(Number(cancellationAmount) || 0);
  const paidAmount = money(Math.max(0, paid - reversal));
  return {
    paidAmount,
    paymentStatus: paidAmount + 0.01 >= total ?
      "paid" : paidAmount > 0.01 ? "partial" : "unpaid",
  };
}

module.exports = {receiptCancellationPayment};
