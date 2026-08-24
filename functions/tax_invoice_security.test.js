const test = require("node:test");
const assert = require("node:assert/strict");

const {
  canRollbackCancelledInvoice,
  taxAuthorityFailureState,
  taxInvoiceDraftSignature,
  taxInvoicePayloadHash,
  validTaxInvoiceDraftSignature,
  validateTaxInvoiceAllocation,
} = require("./tax_invoice_security");

test("rolls back only the latest unfinished cancelled invoice number", () => {
  assert.equal(canRollbackCancelledInvoice({
    invoice: {documentStatus: "allocation_cancelled"},
    counterValue: 43,
    sequenceNumber: 42,
  }), true);
  assert.equal(canRollbackCancelledInvoice({
    invoice: {documentStatus: "allocation_cancelled"},
    counterValue: 44,
    sequenceNumber: 42,
  }), false);
  assert.equal(canRollbackCancelledInvoice({
    invoice: {documentStatus: "finalized", storagePath: "invoices/42.pdf"},
    counterValue: 43,
    sequenceNumber: 42,
  }), false);
});

function validPayload() {
  return {
    vat_number: 123456789,
    invoices_payment_amount: 200,
    invoices_vat_amount: 36,
    invoices_list: [{
      invoice_id: "invoice_2026-0042",
      invoice_type: 305,
      invoice_reference_number: "2026-0042",
      customer_vat_number: 987654321,
      invoice_date: "2026-08-18",
      invoice_issuance_date: "2026-08-18",
      action: 0,
      amount_before_discount: 210,
      discount: 10,
      payment_amount: 200,
      vat_amount: 36,
      payment_amount_including_vat: 236,
      items: [{
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

test("accepts a consistent invoice and derives its reservation", () => {
  const reservation = validateTaxInvoiceAllocation({
    payload: validPayload(),
    invoiceDocId: "invoice_2026-0042",
    currentYear: 2026,
  });
  assert.deepEqual(reservation, {
    docType: "invoice",
    documentNumber: "2026-0042",
    sequenceNumber: 42,
    invoiceDocId: "invoice_2026-0042",
  });
});

test("rejects a fabricated document ID or unsupported document type", () => {
  assert.throws(() => validateTaxInvoiceAllocation({
    payload: validPayload(),
    invoiceDocId: "invoice_2026-9999",
    currentYear: 2026,
  }), /invoice ID/i);

  const payload = validPayload();
  payload.invoices_list[0].invoice_type = 999;
  assert.throws(() => validateTaxInvoiceAllocation({
    payload,
    invoiceDocId: "invoice_2026-0042",
    currentYear: 2026,
  }), /Only tax invoices/i);
});

test("rejects client totals that do not match the line items", () => {
  const payload = validPayload();
  payload.invoices_list[0].payment_amount = 1;
  assert.throws(() => validateTaxInvoiceAllocation({
    payload,
    invoiceDocId: "invoice_2026-0042",
    currentYear: 2026,
  }), /server-calculated/i);
});

test("payload hashes are stable across object key order and change with data", () => {
  assert.equal(taxInvoicePayloadHash({a: 1, b: 2}),
      taxInvoicePayloadHash({b: 2, a: 1}));
  assert.notEqual(taxInvoicePayloadHash({a: 1}),
      taxInvoicePayloadHash({a: 2}));
});

test("uncertain failures require reconciliation instead of an automatic retry", () => {
  assert.equal(taxAuthorityFailureState({details: {authorityStatus: 400}}),
      "failed");
  assert.equal(taxAuthorityFailureState({details: {definitive: true}}),
      "failed");
  assert.equal(taxAuthorityFailureState({details: {authorityStatus: 503}}),
      "needs_reconciliation");
  assert.equal(taxAuthorityFailureState(new Error("socket closed")),
      "needs_reconciliation");
});

test("draft signatures reject changes to immutable reservation data", () => {
  const args = {
    secret: "test-secret",
    userId: "user-1",
    reservation: {
      invoiceDocId: "invoice_2026-0042",
      docType: "invoice",
      documentNumber: "2026-0042",
      sequenceNumber: 42,
    },
    payloadHash: taxInvoicePayloadHash(validPayload()),
  };
  const signature = taxInvoiceDraftSignature(args);
  assert.equal(validTaxInvoiceDraftSignature(args, signature), true);
  assert.equal(validTaxInvoiceDraftSignature({
    ...args,
    reservation: {...args.reservation, sequenceNumber: 43},
  }, signature), false);
});
