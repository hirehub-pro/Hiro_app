const crypto = require("crypto");

const ALLOWED_INVOICE_TYPES = new Map([
  [305, "invoice"],
  [320, "invoice_receipt"],
]);

function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJson(value[key])}`,
    ).join(",")}}`;
  }
  return JSON.stringify(value);
}

function taxInvoicePayloadHash(payload) {
  return crypto.createHash("sha256").update(canonicalJson(payload)).digest("hex");
}

function taxInvoiceDraftSignature({secret, userId, reservation, payloadHash}) {
  const value = [
    "tax-invoice-draft-v1",
    userId,
    reservation.invoiceDocId,
    reservation.docType,
    reservation.documentNumber,
    reservation.sequenceNumber,
    payloadHash,
  ].join("\n");
  return crypto.createHmac("sha256", secret).update(value).digest("hex");
}

function validTaxInvoiceDraftSignature(args, candidate) {
  if (typeof candidate !== "string" || !/^[a-f0-9]{64}$/.test(candidate)) {
    return false;
  }
  const expected = taxInvoiceDraftSignature(args);
  return crypto.timingSafeEqual(Buffer.from(expected, "hex"),
      Buffer.from(candidate, "hex"));
}

function money(value) {
  return Math.round(Number(value) * 100) / 100;
}

function closeMoney(actual, expected, tolerance = 0.02) {
  return Math.abs(money(actual) - money(expected)) <= tolerance;
}

function validateTaxInvoiceAllocation({payload, invoiceDocId, currentYear}) {
  const invoice = payload?.invoices_list?.[0];
  if (!invoice || payload.invoices_list.length !== 1) {
    throw new Error("Exactly one invoice is required.");
  }

  const docType = ALLOWED_INVOICE_TYPES.get(invoice.invoice_type);
  if (!docType) {
    throw new Error("Only tax invoices and invoice-receipts can request allocations.");
  }

  const reference = String(invoice.invoice_reference_number || "");
  const referenceMatch = reference.match(/^(?:(\d{4})-)?(\d{4,})$/);
  if (!referenceMatch ||
      (referenceMatch[1] && Number(referenceMatch[1]) !== currentYear)) {
    throw new Error("The invoice number is invalid.");
  }
  const sequenceNumber = Number.parseInt(referenceMatch[2], 10);
  if (!Number.isSafeInteger(sequenceNumber) || sequenceNumber < 1) {
    throw new Error("The invoice sequence number is invalid.");
  }

  const expectedInvoiceDocId = `${docType}_${reference}`;
  if (invoiceDocId !== expectedInvoiceDocId || invoice.invoice_id !== expectedInvoiceDocId) {
    throw new Error("The invoice ID does not match its type and document number.");
  }
  if (invoice.action !== 0) {
    throw new Error("Unsupported Tax Authority invoice action.");
  }
  if (!Number.isSafeInteger(invoice.customer_vat_number) ||
      invoice.customer_vat_number < 1) {
    throw new Error("The customer VAT number is invalid.");
  }
  const invoiceDate = String(invoice.invoice_date || "");
  const issuanceDate = String(invoice.invoice_issuance_date || "");
  const dateMatch = invoiceDate.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  const parsedDate = dateMatch ? new Date(`${invoiceDate}T00:00:00Z`) : null;
  if (!dateMatch || !parsedDate || Number.isNaN(parsedDate.getTime()) ||
      parsedDate.toISOString().slice(0, 10) !== invoiceDate ||
      issuanceDate !== invoiceDate) {
    throw new Error("The invoice and issuance dates must be the same valid ISO date.");
  }

  const items = invoice.items;
  if (!Array.isArray(items) || items.length < 1 || items.length > 100) {
    throw new Error("The invoice must contain between 1 and 100 line items.");
  }

  let amountBeforeDiscount = 0;
  let grossVatAmount = 0;
  const vatRates = new Set();
  items.forEach((item, index) => {
    const quantity = Number(item.quantity);
    const unitPrice = Number(item.price_per_unit);
    const lineDiscount = Number(item.discount || 0);
    const lineTotal = Number(item.total_amount);
    const vatRate = Number(item.vat_rate);
    const lineVat = Number(item.vat_amount);
    const values = [quantity, unitPrice, lineDiscount, lineTotal, vatRate, lineVat];
    if (values.some((value) => !Number.isFinite(value)) ||
        quantity <= 0 || unitPrice < 0 || lineDiscount < 0 ||
        vatRate < 0 || vatRate > 100) {
      throw new Error(`Line item ${index + 1} contains invalid amounts.`);
    }
    if (lineDiscount !== 0) {
      throw new Error("Discounts must be stored at document level only.");
    }

    const lineBeforeDiscount = money(quantity * unitPrice);
    const expectedLineVat = money(lineBeforeDiscount * vatRate / 100);
    if (!closeMoney(lineTotal, lineBeforeDiscount) ||
        !closeMoney(lineVat, expectedLineVat)) {
      throw new Error(`Line item ${index + 1} totals do not match its quantity, price, and VAT rate.`);
    }
    amountBeforeDiscount += lineBeforeDiscount;
    grossVatAmount += expectedLineVat;
    vatRates.add(money(vatRate).toFixed(2));
  });

  const discount = money(Number(invoice.discount || 0));
  const normalizedBeforeDiscount = money(amountBeforeDiscount);
  if (!Number.isFinite(discount) || discount < 0 ||
      discount > normalizedBeforeDiscount) {
    throw new Error("The document discount is invalid.");
  }
  if (discount > 0 && vatRates.size > 1) {
    throw new Error(
        "A document discount requires one VAT rate across all line items.",
    );
  }
  const paymentAmount = money(normalizedBeforeDiscount - discount);
  const documentVatRate = vatRates.size === 1 ? Number([...vatRates][0]) : 0;
  const vatAmount = discount > 0 ?
    money(paymentAmount * documentVatRate / 100) : money(grossVatAmount);

  const calculated = {
    amountBeforeDiscount: normalizedBeforeDiscount,
    discount,
    paymentAmount,
    vatAmount,
  };
  const includingVat = money(calculated.paymentAmount + calculated.vatAmount);
  if (!closeMoney(invoice.amount_before_discount, calculated.amountBeforeDiscount, 0.05) ||
      !closeMoney(invoice.discount, calculated.discount, 0.05) ||
      !closeMoney(invoice.payment_amount, calculated.paymentAmount, 0.05) ||
      !closeMoney(invoice.vat_amount, calculated.vatAmount, 0.05) ||
      !closeMoney(invoice.payment_amount_including_vat, includingVat, 0.05) ||
      !closeMoney(payload.invoices_payment_amount, calculated.paymentAmount, 0.05) ||
      !closeMoney(payload.invoices_vat_amount, calculated.vatAmount, 0.05)) {
    throw new Error("The invoice totals do not match the server-calculated line item totals.");
  }

  return {
    docType,
    documentNumber: reference,
    sequenceNumber,
    invoiceDocId: expectedInvoiceDocId,
  };
}

function taxAuthorityFailureState(error) {
  if (error?.details?.definitive === true) return "failed";
  const status = Number(error?.details?.authorityStatus);
  return Number.isInteger(status) && status >= 400 && status < 500 ?
    "failed" : "needs_reconciliation";
}

function taxInvoiceFinalizationMode(invoice) {
  const documentStatus = String(invoice?.documentStatus || "").trim();
  const isAllocated = ["allocation_approved", "finalized"].includes(
      documentStatus,
  ) && invoice?.taxAuthorityAllocation?.approved === true &&
    Boolean(invoice?.taxAuthorityAllocation?.confirmationNumber);
  if (isAllocated) return "allocated";
  const isContinued = ["continued_without_allocation", "finalized"].includes(
      documentStatus,
  ) && invoice?.taxAuthorityDecision?.decision === "continue" &&
    invoice?.taxAuthorityDecision?.status === "accepted";
  return isContinued ? "continued_without_allocation" : null;
}

module.exports = {
  taxAuthorityFailureState,
  taxInvoiceFinalizationMode,
  taxInvoiceDraftSignature,
  taxInvoicePayloadHash,
  validTaxInvoiceDraftSignature,
  validateTaxInvoiceAllocation,
};
