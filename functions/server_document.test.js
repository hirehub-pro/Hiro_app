"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  normalizeServerDocumentRequest,
  serverDocumentPdfPayload,
} = require("./server_document");

function base(overrides = {}) {
  return {
    operationId: "document_operation_0001",
    docType: "invoice",
    documentNumber: "2026-0042",
    sequenceNumber: 42,
    date: "2026-08-18",
    client: {
      id: "987654321",
      name: "Test Client",
      email: "client@example.com",
    },
    items: [{
      description: "Service",
      quantity: 2,
      price: 118,
      priceTaxMode: "after_tax",
    }],
    discountAmount: 10,
    roundTotalEnabled: false,
    paymentMethods: [],
    ...overrides,
  };
}

function normalize(input) {
  return normalizeServerDocumentRequest(input, {
    dealerType: "licensed",
    vatPercent: 18,
  });
}

test("calculates invoice totals on the server and ignores client totals", () => {
  const document = normalize({
    ...base(),
    finalTotal: 0.01,
    vatAmount: 999999,
    paymentAmount: -100,
  });
  assert.equal(document.amountBeforeDiscount, 200);
  assert.equal(document.discount, 10);
  assert.equal(document.paymentAmount, 190);
  assert.equal(document.vatAmount, 34.2);
  assert.equal(document.finalTotal, 224.2);
  assert.equal(document.items[0].price_per_unit, 100);
});

test("requires invoice-receipt payments to equal the calculated total", () => {
  assert.throws(() => normalize(base({
    docType: "invoice_receipt",
    documentNumber: "2026-0043",
    sequenceNumber: 43,
    paymentMethods: [{method: "cash", amount: 1}],
  })), /do not match/);

  const document = normalize(base({
    docType: "invoice_receipt",
    documentNumber: "2026-0043",
    sequenceNumber: 43,
    paymentMethods: [{method: "cash", amount: 224.2}],
  }));
  assert.equal(document.finalTotal, 224.2);
});

test("ignores empty payment rows for document types without payments", () => {
  for (const docType of [
    "quote",
    "work_order",
    "transaction_account",
    "invoice",
    "credit_note",
  ]) {
    const document = normalize(base({
      docType,
      paymentMethods: [{method: "cash"}],
      ...(docType === "credit_note" ? {
        creditNoteLegal: {
          originalInvoiceNumber: "2026-0001",
          creditReason: "Correction",
        },
      } : {}),
    }));
    assert.deepEqual(document.paymentMethods, [], docType);
  }
});

test("builds receipts from payment methods without accepting line items", () => {
  const document = normalize(base({
    docType: "receipt",
    documentNumber: "2026-0044",
    sequenceNumber: 44,
    items: [{description: "ignored", quantity: -10, price: -20}],
    discountAmount: 999,
    paymentMethods: [
      {method: "cash", amount: 70},
      {method: "transfer", amount: 30},
    ],
  }));
  assert.equal(document.finalTotal, 100);
  assert.equal(document.vatAmount, 0);
  assert.deepEqual(document.items, []);
});

test("validates and preserves a check due date", () => {
  const document = normalize(base({
    docType: "receipt",
    documentNumber: "2026-0046",
    sequenceNumber: 46,
    paymentMethods: [{
      method: "check",
      amount: 100,
      checkNumber: "123456",
      paymentDate: "2026-09-30",
    }],
  }));
  assert.equal(document.paymentMethods[0].paymentDate, "2026-09-30");

  assert.throws(() => normalize(base({
    docType: "receipt",
    documentNumber: "2026-0047",
    sequenceNumber: 47,
    paymentMethods: [{
      method: "check",
      amount: 100,
      checkNumber: "123456",
    }],
  })), /requires a due date/);
});

test("validates and preserves credit installment dates", () => {
  const document = normalize(base({
    docType: "invoice_receipt",
    documentNumber: "2026-0048",
    sequenceNumber: 48,
    paymentMethods: [{
      method: "credit",
      amount: 224.2,
      installments: "3",
      installmentDates: ["2026-09-01", "2026-10-01", "2026-11-01"],
    }],
  }));
  assert.deepEqual(document.paymentMethods[0].installmentDates, [
    "2026-09-01",
    "2026-10-01",
    "2026-11-01",
  ]);

  assert.throws(() => normalize(base({
    docType: "invoice_receipt",
    documentNumber: "2026-0049",
    sequenceNumber: 49,
    paymentMethods: [{
      method: "credit",
      amount: 224.2,
      installments: "3",
      installmentDates: ["2026-09-01", "2026-10-01"],
    }],
  })), /one date per installment/);
});

test("rejects mismatched numbers, invalid email, and incomplete cancellation", () => {
  assert.throws(() => normalize(base({sequenceNumber: 41})), /sequence/);
  assert.throws(() => normalize(base({
    client: {name: "Test", email: "not-an-email"},
  })), /email/);
  assert.throws(() => normalize(base({
    docType: "receipt",
    documentNumber: "2026-0044",
    sequenceNumber: 44,
    isNegativeReceipt: true,
    paymentMethods: [{method: "cash", amount: 100}],
  })), /source receipt/);
});

test("allows credit notes without legal references", () => {
  const withoutReferences = normalize(base({
    docType: "credit_note",
    documentNumber: "2026-0045",
    sequenceNumber: 45,
  }));
  assert.equal(withoutReferences.creditNoteLegal, null);

  const withOptionalReferences = normalize(base({
    docType: "credit_note",
    documentNumber: "2026-0045",
    sequenceNumber: 45,
    creditNoteLegal: {
      originalInvoiceNumber: "2026-0001",
      creditReason: "Optional correction details",
    },
  }));
  assert.equal(
      withOptionalReferences.creditNoteLegal.originalInvoiceNumber,
      "2026-0001",
  );
});

test("maps authoritative data into the PDF payload", () => {
  const document = normalize(base());
  const payload = serverDocumentPdfPayload(document, "123456789");
  assert.equal(payload.invoices_payment_amount, 190);
  assert.equal(payload.invoices_vat_amount, 34.2);
  assert.equal(payload.invoices_list[0].payment_amount_including_vat, 224.2);
  assert.equal(payload.invoices_list[0].invoice_reference_number, "2026-0042");
});

test("hashes an inline logo but excludes its bytes from stored document data", () => {
  const logoBytes = require("fs").readFileSync(
      require("path").join(__dirname, "..", "assets", "icon", "app_icon.jpg"),
  );
  const document = normalize(base({
    documentLogoMode: "inline",
    documentLogoBase64: logoBytes.toString("base64"),
  }));
  assert.equal(document.documentLogoMode, "inline");
  assert.match(document.documentLogoHash, /^[a-f0-9]{64}$/);
  assert.ok(Buffer.isBuffer(document.documentLogoBytes));
  assert.equal(Object.keys(document).includes("documentLogoBytes"), false);
});
