"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {PDFDocument} = require("pdf-lib");

const {
  buildTaxInvoicePdf,
  normalizeTaxInvoicePresentation,
  visualText,
} = require("./tax_invoice_pdf");

function samplePayload() {
  return {
    vat_number: 123456789,
    invoices_payment_amount: 200,
    invoices_vat_amount: 36,
    invoices_list: [{
      invoice_id: "invoice_2026-0042",
      invoice_type: 305,
      invoice_reference_number: "2026-0042",
      customer_vat_number: 987654321,
      customer_name: "לקוח בדיקה",
      invoice_date: "2026-08-18",
      invoice_issuance_date: "2026-08-18",
      amount_before_discount: 210,
      discount: 10,
      payment_amount: 200,
      vat_amount: 36,
      payment_amount_including_vat: 236,
      invoice_note: "תודה שבחרתם בהירו",
      items: [{
        description: "עבודת בדיקה",
        quantity: 2,
        price_per_unit: 105,
        discount: 10,
        total_amount: 200,
        vat_rate: 18,
        vat_amount: 36,
      }],
    }],
  };
}

test("presentation normalization keeps only bounded supported fields", () => {
  const presentation = normalizeTaxInvoicePresentation({
    clientAddress: "רחוב הבדיקה 1",
    clientEmail: "  CLIENT@EXAMPLE.COM ",
    paymentDueDate: "not-a-date",
    roundTotalEnabled: true,
    paymentMethods: [{method: "credit", amount: "236", secret: "drop-me"}],
    ignored: "drop-me",
  });
  assert.equal(presentation.clientEmail, "client@example.com");
  assert.equal(presentation.paymentDueDate, null);
  assert.equal(presentation.roundTotalEnabled, true);
  assert.deepEqual(Object.keys(presentation).sort(), [
    "clientAddress",
    "clientEmail",
    "clientPhone",
    "externalClientNumber",
    "paymentDueDate",
    "paymentMethods",
    "priceTaxModeDefault",
    "roundTotalEnabled",
    "savedClientId",
  ]);
  assert.equal("secret" in presentation.paymentMethods[0], false);
});

test("bidirectional conversion preserves number order in Hebrew text", () => {
  const visual = visualText("חשבונית מס 1042");
  assert.match(visual, /1042/);
  assert.doesNotMatch(visual, /2401/);
});

test("server generator creates a readable multi-language PDF", async () => {
  const bytes = await buildTaxInvoicePdf({
    payload: samplePayload(),
    allocation: {confirmationNumber: "987654321"},
    reservation: {
      docType: "invoice",
      documentNumber: "2026-0042",
      sequenceNumber: 42,
      invoiceDocId: "invoice_2026-0042",
    },
    business: {
      name: "עסק בדיקה",
      businessId: "123456789",
      address: "רחוב העסק 2",
      dealerType: "licensed",
      phone: "0500000000",
      email: "owner@example.com",
    },
    presentation: normalizeTaxInvoicePresentation({
      clientAddress: "רחוב הלקוח 1",
      clientPhone: "0511111111",
      clientEmail: "client@example.com",
    }),
    generatedAt: new Date("2026-08-18T10:00:00Z"),
  });
  assert.equal(bytes.subarray(0, 4).toString("ascii"), "%PDF");
  const pdf = await PDFDocument.load(bytes);
  assert.ok(pdf.getPageCount() >= 1);
  assert.match(pdf.getTitle(), /2026-0042/);
  assert.equal(pdf.getSubject(), "Tax Authority allocation 987654321");
});
