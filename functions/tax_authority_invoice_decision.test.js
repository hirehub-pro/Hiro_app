const test = require("node:test");
const assert = require("node:assert/strict");

const {
  invoiceDecisionDocumentStatus,
  invoiceDecisionPath,
  invoiceDecisionPayload,
  normalizeInvoiceDecision,
} = require("./tax_authority_invoice_decision");

function payload() {
  return {invoices_list: [{
    invoice_id: "invoice_2026-0042",
    vat_number: 123456789,
    authorized_company: 111111111,
    user_name: "Hiro",
    accounting_software_number: 987654321,
    customer_vat_number: 987654321,
  }]};
}

test("maps supported decisions to the documented V1 paths", () => {
  assert.equal(invoiceDecisionPath("cancel"),
      "/InvoiceDecisionApi/v1/Cancel");
  assert.equal(invoiceDecisionPath("continue"),
      "/InvoiceDecisionApi/v1/Continue");
  assert.equal(invoiceDecisionPath("further_objection"),
      "/InvoiceDecisionApi/v1/FurtherObjection");
  assert.throws(() => invoiceDecisionPath("reverse_charge"), /action 3/);
  assert.equal(normalizeInvoiceDecision("reverse_charge"), "reverse_charge");
});

test("builds only fields allowed by ChoiceRequest", () => {
  assert.deepEqual(invoiceDecisionPayload(payload()), {
    invoice_id: "invoice_2026-0042",
    vat_number: 123456789,
    authorized_company: 111111111,
    user_name: "Hiro",
    accounting_software_number: 987654321,
  });
});

test("maps decisions to persisted workflow states", () => {
  assert.equal(invoiceDecisionDocumentStatus("cancel"),
      "allocation_cancelled");
  assert.equal(invoiceDecisionDocumentStatus("continue"),
      "continued_without_allocation");
  assert.equal(invoiceDecisionDocumentStatus("further_objection"),
      "hearing_requested");
  assert.equal(invoiceDecisionDocumentStatus("reverse_charge"),
      "reverse_charge_requested");
});
