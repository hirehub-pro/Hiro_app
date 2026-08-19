"use strict";

const crypto = require("crypto");

const ALLOWED_TYPES = new Set([
  "quote",
  "work_order",
  "transaction_account",
  "invoice",
  "invoice_receipt",
  "credit_note",
  "receipt",
]);
const SEQUENTIAL_TYPES = new Set([
  "transaction_account",
  "invoice",
  "invoice_receipt",
  "credit_note",
  "receipt",
]);
const PAYMENT_TYPES = new Set(["invoice_receipt", "receipt"]);

function string(value, maxLength, fallback = "") {
  const result = value == null ? "" : String(value).trim();
  return (result || fallback).slice(0, maxLength);
}

function optionalString(value, maxLength) {
  return string(value, maxLength) || null;
}

function finite(value, name) {
  const number = Number(value);
  if (!Number.isFinite(number)) throw new Error(`${name} must be a number.`);
  return number;
}

function money(value) {
  return Math.round(Number(value) * 100) / 100;
}

function validIsoDate(value, name, optional = false) {
  const result = string(value, 10);
  if (optional && !result) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(result) ||
      new Date(`${result}T00:00:00Z`).toISOString().slice(0, 10) !== result) {
    throw new Error(`${name} must be a valid date.`);
  }
  return result;
}

function normalizePaymentMethods(value) {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 20).map((raw, index) => {
    const data = raw && typeof raw === "object" ? raw : {};
    const method = string(data.method, 24, "cash");
    if (!["cash", "credit", "check", "transfer", "bit", "paybox",
      "other", "withholding_tax"].includes(method)) {
      throw new Error(`Payment method ${index + 1} is unsupported.`);
    }
    const amount = money(finite(data.amount, `Payment ${index + 1} amount`));
    if (amount <= 0) throw new Error(`Payment ${index + 1} must be positive.`);
    const result = {
      method,
      amount,
      cardNumber: optionalString(data.cardNumber, 32),
      cardName: optionalString(data.cardName, 80),
      cardExpiration: optionalString(data.cardExpiration, 12),
      installments: optionalString(data.installments, 8),
      checkNumber: optionalString(data.checkNumber, 32),
      bank: optionalString(data.bank, 80),
      branch: optionalString(data.branch, 32),
      account: optionalString(data.account, 40),
    };
    if (method === "check" && !result.checkNumber) {
      throw new Error(`Payment method ${index + 1} requires a check number.`);
    }
    return result;
  });
}

function normalizeItems(value, usesVat, vatRate) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 100) {
    throw new Error("The document must contain between 1 and 100 items.");
  }
  return value.map((raw, index) => {
    const data = raw && typeof raw === "object" ? raw : {};
    const description = string(data.description, 120);
    const quantity = finite(data.quantity, `Item ${index + 1} quantity`);
    const price = finite(data.price, `Item ${index + 1} price`);
    const priceTaxMode = data.priceTaxMode === "before_tax" ?
      "before_tax" : "after_tax";
    if (!description || quantity <= 0 || price < 0) {
      throw new Error(`Item ${index + 1} is invalid.`);
    }
    const unitBeforeTax = usesVat && priceTaxMode === "after_tax" ?
      price / (1 + vatRate) : price;
    return {
      index: index + 1,
      description,
      quantity,
      price,
      priceTaxMode,
      unitBeforeTax,
      grossBeforeTax: unitBeforeTax * quantity,
    };
  });
}

function normalizeLinkedDocuments(value) {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 100).map((raw) => {
    const data = raw && typeof raw === "object" ? raw : {};
    return {
      invoiceDocId: string(data.invoiceDocId || data.id, 180),
      docType: string(data.docType, 40),
      documentNumber: string(data.documentNumber, 40),
      name: string(data.name, 240),
      date: string(data.date, 20),
      amount: money(Number(data.amount) || 0),
    };
  }).filter((entry) => entry.invoiceDocId);
}

function normalizeDocumentLogo(data) {
  const mode = ["default", "none", "inline"].includes(data.documentLogoMode) ?
    data.documentLogoMode : "default";
  if (mode !== "inline") return {mode, hash: null, bytes: null};
  const encoded = typeof data.documentLogoBase64 === "string" ?
    data.documentLogoBase64.trim() : "";
  if (!encoded || encoded.length > 4 * 1024 * 1024 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) {
    throw new Error("The document logo is invalid or too large.");
  }
  const bytes = Buffer.from(encoded, "base64");
  const isJpeg = bytes.length >= 3 && bytes[0] === 0xff &&
    bytes[1] === 0xd8 && bytes[2] === 0xff;
  const isPng = bytes.length >= 8 &&
    bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  if (bytes.length < 1 || bytes.length > 3 * 1024 * 1024 ||
      (!isJpeg && !isPng)) {
    throw new Error("The document logo must be a JPEG or PNG under 3 MB.");
  }
  return {
    mode,
    hash: crypto.createHash("sha256").update(bytes).digest("hex"),
    bytes,
  };
}

function calculatedItems(items, discount, usesVat, vatRate) {
  const gross = items.reduce((total, item) => total + item.grossBeforeTax, 0);
  let remainingDiscount = discount;
  return items.map((item, index) => {
    const proportional = gross > 0 ? discount * item.grossBeforeTax / gross : 0;
    const lineDiscount = index === items.length - 1 ?
      remainingDiscount : proportional;
    remainingDiscount -= lineDiscount;
    const totalBeforeTax = money(item.grossBeforeTax - lineDiscount);
    const vatAmount = usesVat ? money(totalBeforeTax * vatRate) : 0;
    return {
      index: item.index,
      description: item.description,
      quantity: money(item.quantity),
      price_per_unit: money(item.unitBeforeTax),
      discount: money(lineDiscount),
      total_amount: totalBeforeTax,
      vat_rate: usesVat ? money(vatRate * 100) : 0,
      vat_amount: vatAmount,
      originalPrice: money(item.price),
      priceTaxMode: item.priceTaxMode,
    };
  });
}

function normalizeServerDocumentRequest(raw, {dealerType, vatPercent}) {
  const data = raw && typeof raw === "object" ? raw : {};
  const docType = string(data.docType, 40);
  if (!ALLOWED_TYPES.has(docType)) throw new Error("Unsupported document type.");
  const operationId = string(data.operationId, 180);
  if (!/^[A-Za-z0-9_-]{12,180}$/.test(operationId)) {
    throw new Error("The document operation ID is invalid.");
  }
  const sequential = SEQUENTIAL_TYPES.has(docType);
  const sequenceNumber = sequential ?
    Math.trunc(finite(data.sequenceNumber, "sequenceNumber")) : null;
  const documentNumber = sequential ? string(data.documentNumber, 40) : "";
  if (sequential && (sequenceNumber < 1 ||
      !/^\d{4}-\d{4,}$/.test(documentNumber))) {
    throw new Error("The reserved document number is invalid.");
  }
  if (sequential && Number(documentNumber.split("-").at(-1)) !==
      sequenceNumber) {
    throw new Error("The reserved document number does not match its sequence.");
  }
  const invoiceDocId = sequential ?
    `${docType}_${documentNumber}` : `${docType}_${operationId}`;
  const date = validIsoDate(data.date, "date");
  const paymentDueDate = validIsoDate(
      data.paymentDueDate,
      "paymentDueDate",
      true,
  );
  const usesVat = ["licensed", "company"].includes(dealerType) &&
    docType !== "receipt";
  const vatRate = usesVat ? Number(vatPercent) / 100 : 0;
  if (!Number.isFinite(vatRate) || vatRate < 0 || vatRate > 1) {
    throw new Error("The configured VAT rate is invalid.");
  }
  const paymentMethods = normalizePaymentMethods(data.paymentMethods);
  const rawDiscount = money(Number(data.discountAmount) || 0);
  let items = [];
  let amountBeforeDiscount;
  let discount;
  let paymentAmount;
  let vatAmount;
  if (docType === "receipt") {
    if (paymentMethods.length < 1) {
      throw new Error("A receipt must include a payment method.");
    }
    paymentAmount = money(paymentMethods.reduce(
        (total, method) => total + method.amount,
        0,
    ));
    amountBeforeDiscount = paymentAmount;
    discount = 0;
    vatAmount = 0;
  } else {
    const normalizedItems = normalizeItems(data.items, usesVat, vatRate);
    amountBeforeDiscount = money(normalizedItems.reduce(
        (total, item) => total + item.grossBeforeTax,
        0,
    ));
    if (rawDiscount < 0 || rawDiscount > amountBeforeDiscount) {
      throw new Error("The discount is outside the document total.");
    }
    discount = rawDiscount;
    items = calculatedItems(normalizedItems, discount, usesVat, vatRate);
    paymentAmount = money(items.reduce(
        (total, item) => total + item.total_amount,
        0,
    ));
    vatAmount = money(items.reduce(
        (total, item) => total + item.vat_amount,
        0,
    ));
  }
  const beforeRounding = money(paymentAmount + vatAmount);
  const roundingAmount = data.roundTotalEnabled === true && docType !== "receipt" ?
    money(beforeRounding - Math.floor(beforeRounding)) : 0;
  const finalTotal = money(beforeRounding - roundingAmount);
  if (PAYMENT_TYPES.has(docType)) {
    const paid = money(paymentMethods.reduce(
        (total, method) => total + method.amount,
        0,
    ));
    if (Math.abs(paid - finalTotal) > 0.02) {
      throw new Error("Payment methods do not match the final total.");
    }
  }
  const isNegativeReceipt = docType === "receipt" &&
    data.isNegativeReceipt === true;
  const client = data.client && typeof data.client === "object" ?
    data.client : {};
  const clientEmail = string(client.email, 254).toLowerCase();
  if (clientEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(clientEmail)) {
    throw new Error("The client email address is invalid.");
  }
  const linkedDocuments = normalizeLinkedDocuments(data.linkedDocuments);
  const credit = data.creditNoteLegal &&
      typeof data.creditNoteLegal === "object" ? data.creditNoteLegal : {};
  const creditNoteLegal = docType === "credit_note" ? {
    originalInvoiceNumber: string(credit.originalInvoiceNumber, 40),
    originalInvoiceDate: string(credit.originalInvoiceDate, 20),
    creditReason: string(credit.creditReason, 1000),
    deliveryMethod: string(credit.deliveryMethod, 40),
    receiptConfirmation: string(credit.receiptConfirmation, 200),
  } : null;
  if (creditNoteLegal && (!creditNoteLegal.originalInvoiceNumber ||
      !creditNoteLegal.creditReason)) {
    throw new Error("Credit-note legal references are required.");
  }
  const documentLogo = normalizeDocumentLogo(data);
  const canonical = {
    operationId,
    docType,
    sequential,
    invoiceDocId,
    documentNumber,
    sequenceNumber,
    date,
    paymentDueDate,
    usesVat,
    vatRate,
    client: {
      id: string(client.id, 32),
      name: string(client.name, 200),
      address: string(client.address, 500),
      phone: string(client.phone, 32),
      email: clientEmail,
      externalClientNumber: string(client.externalClientNumber, 40),
      savedClientId: optionalString(client.savedClientId, 180),
    },
    items,
    amountBeforeDiscount,
    discount,
    paymentAmount,
    vatAmount,
    beforeRounding,
    roundingAmount,
    finalTotal,
    notes: string(data.notes, 4000),
    roundTotalEnabled: data.roundTotalEnabled === true,
    priceTaxModeDefault: data.priceTaxModeDefault === "before_tax" ?
      "before_tax" : "after_tax",
    paymentMethods,
    linkedDocuments,
    linkedDocumentIds: linkedDocuments.map((entry) => entry.invoiceDocId),
    sourceInvoiceDocId: optionalString(data.sourceInvoiceDocId, 180),
    sourceInvoiceNumber: optionalString(data.sourceInvoiceNumber, 40),
    isNegativeReceipt,
    cancellationSourceDocumentId: optionalString(
        data.cancellationSourceDocumentId,
        180,
    ),
    cancellationSourceDocumentNumber: optionalString(
        data.cancellationSourceDocumentNumber,
        40,
    ),
    creditNoteLegal,
    documentLogoMode: documentLogo.mode,
    documentLogoHash: documentLogo.hash,
  };
  if (isNegativeReceipt && (!canonical.cancellationSourceDocumentId ||
      !canonical.cancellationSourceDocumentNumber)) {
    throw new Error("A cancellation receipt must identify its source receipt.");
  }
  canonical.payloadHash = crypto.createHash("sha256")
      .update(JSON.stringify(canonical)).digest("hex");
  Object.defineProperty(canonical, "documentLogoBytes", {
    value: documentLogo.bytes,
    enumerable: false,
  });
  return canonical;
}

function serverDocumentPdfPayload(document, businessId) {
  return {
    vat_number: Number(businessId) || 0,
    invoices_payment_amount: document.paymentAmount,
    invoices_vat_amount: document.vatAmount,
    invoices_list: [{
      invoice_id: document.invoiceDocId,
      invoice_type: 0,
      vat_number: Number(businessId) || 0,
      invoice_reference_number: document.documentNumber,
      customer_vat_number: Number(document.client.id) || 0,
      customer_name: document.client.name,
      invoice_date: document.date,
      invoice_issuance_date: document.date,
      amount_before_discount: document.amountBeforeDiscount,
      discount: document.discount,
      payment_amount: document.paymentAmount,
      vat_amount: document.vatAmount,
      payment_amount_including_vat: document.beforeRounding,
      invoice_note: document.notes,
      items: document.items,
    }],
  };
}

module.exports = {
  ALLOWED_TYPES,
  SEQUENTIAL_TYPES,
  normalizeServerDocumentRequest,
  serverDocumentPdfPayload,
};
