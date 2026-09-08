"use strict";

const PAYMENT_ANALYTICS_COLLECTION = "paymentAnalytics";
const PAYMENT_ANALYTICS_ALL_TIME_ID = "all_time";
const PAYMENT_ANALYTICS_CURRENT_YEAR_ID = "current_year";

function paymentMonthDocumentId(month) {
  return `month_${String(month).padStart(2, "0")}`;
}

function parseDocumentPeriod(date) {
  const normalized = String(date || "").replaceAll("-", "");
  const match = normalized.match(/^(\d{4})(\d{2})\d{2}$/);
  if (!match) throw new Error("Payment analytics requires a valid document date.");
  const year = Number(match[1]);
  const month = Number(match[2]);
  if (!Number.isInteger(year) || year < 2000 || year > 9999 ||
      !Number.isInteger(month) || month < 1 || month > 12) {
    throw new Error("Payment analytics requires a valid document period.");
  }
  return {year, month};
}

function paymentAnalyticsEntry(document) {
  if (!document || !["receipt", "invoice_receipt"].includes(document.docType)) {
    return null;
  }
  const amount = Math.round(Number(document.finalTotal) * 100) / 100;
  if (!Number.isFinite(amount) || amount < 0) {
    throw new Error("Payment analytics requires a non-negative document total.");
  }
  const period = parseDocumentPeriod(document.date);
  return {
    ...period,
    delta: document.isNegativeReceipt === true ? -amount : amount,
  };
}

function financialAnalyticsEntry(document) {
  if (!document) return null;
  const isPayment = ["receipt", "invoice_receipt"].includes(document.docType);
  const includesVat = ["invoice", "invoice_receipt", "credit_note"].includes(
      document.docType,
  );
  if (!isPayment && !includesVat) return null;

  const period = parseDocumentPeriod(document.date);
  let paymentDelta = 0;
  let vatDelta = 0;
  if (isPayment) {
    const paymentAmount = Math.round(Number(document.finalTotal) * 100) / 100;
    if (!Number.isFinite(paymentAmount) || paymentAmount < 0) {
      throw new Error("Financial analytics requires a valid payment total.");
    }
    paymentDelta = document.isNegativeReceipt === true ?
      -paymentAmount : paymentAmount;
  }
  if (includesVat) {
    const vatAmount = Math.round(Number(document.vatAmount) * 100) / 100;
    if (!Number.isFinite(vatAmount) || vatAmount < 0) {
      throw new Error("Financial analytics requires a valid VAT total.");
    }
    vatDelta = document.docType === "credit_note" ? -vatAmount : vatAmount;
  }
  return {...period, paymentDelta, vatDelta};
}

function paymentAnalyticsYearMode(entryYear, storedYear) {
  const normalizedStoredYear = Number(storedYear);
  if (!Number.isInteger(normalizedStoredYear) || entryYear > normalizedStoredYear) {
    return "reset";
  }
  return entryYear === normalizedStoredYear ? "current" : "historical";
}

function paymentAnalyticsSnapshot(documents, currentYear) {
  const months = Array(12).fill(0);
  const vatMonths = Array(12).fill(0);
  let currentYearTotal = 0;
  let currentYearVat = 0;
  let allTimeTotal = 0;
  let allTimeVat = 0;
  for (const document of documents || []) {
    if (!document || document.documentStatus !== "finalized") {
      continue;
    }
    let period;
    try {
      period = parseDocumentPeriod(document.date);
    } catch (_) {
      continue;
    }
    const {year, month} = period;
    if (["receipt", "invoice_receipt"].includes(document.docType)) {
      const signedAmount = Math.round(Number(document.amount) * 100) / 100;
      if (Number.isFinite(signedAmount)) {
        allTimeTotal = Math.round((allTimeTotal + signedAmount) * 100) / 100;
        if (year === currentYear) {
          months[month - 1] = Math.round(
              (months[month - 1] + signedAmount) * 100,
          ) / 100;
          currentYearTotal = Math.round(
              (currentYearTotal + signedAmount) * 100,
          ) / 100;
        }
      }
    }
    if (["invoice", "invoice_receipt", "credit_note"].includes(
        document.docType,
    )) {
      const vatAmount = Math.round(Number(document.vatAmount) * 100) / 100;
      if (!Number.isFinite(vatAmount)) continue;
      const signedVat = document.docType === "credit_note" ?
        -Math.abs(vatAmount) : Math.abs(vatAmount);
      allTimeVat = Math.round((allTimeVat + signedVat) * 100) / 100;
      if (year === currentYear) {
        vatMonths[month - 1] = Math.round(
            (vatMonths[month - 1] + signedVat) * 100,
        ) / 100;
        currentYearVat = Math.round(
            (currentYearVat + signedVat) * 100,
        ) / 100;
      }
    }
  }
  return {
    months,
    vatMonths,
    currentYearTotal,
    currentYearVat,
    allTimeTotal,
    allTimeVat,
  };
}

module.exports = {
  PAYMENT_ANALYTICS_ALL_TIME_ID,
  PAYMENT_ANALYTICS_COLLECTION,
  PAYMENT_ANALYTICS_CURRENT_YEAR_ID,
  financialAnalyticsEntry,
  paymentAnalyticsEntry,
  paymentAnalyticsSnapshot,
  paymentAnalyticsYearMode,
  paymentMonthDocumentId,
};
