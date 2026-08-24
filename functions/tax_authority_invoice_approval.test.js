const test = require("node:test");
const assert = require("node:assert/strict");

const {
  extractInvoiceApproval,
  singleInvoiceApprovalPayload,
} = require("./tax_authority_invoice_approval");

function payload() {
  return {
    vat_number: 123456789,
    invoices_amount: 1,
    invoices_payment_amount: 100,
    invoices_vat_amount: 18,
    invoices_list: [{
      invoice_id: "invoice_2026-0042",
      invoice_type: 305,
      vat_number: 123456789,
      invoice_reference_number: "2026-0042",
      customer_vat_number: 987654321,
      invoice_date: "2026-08-24",
      invoice_issuance_date: "2026-08-24",
      accounting_software_number: 987654321,
      amount_before_discount: 100,
      discount: 0,
      payment_amount: 100,
      vat_amount: 18,
      payment_amount_including_vat: 118,
      action: 0,
      items: [{
        index: 1,
        description: "Service",
        quantity: 1,
        price_per_unit: 100,
        discount: 0,
        total_amount: 100,
        vat_rate: 18,
        vat_amount: 18,
      }],
    }],
  };
}

test("unwraps exactly one invoice for Invoices/v2/Approval", () => {
  const request = singleInvoiceApprovalPayload(payload());
  assert.equal(request.invoice_id, "invoice_2026-0042");
  assert.equal(request.customer_vat_number, 987654321);
  assert.equal(request.items[0].vat_amount, 18);
  assert.equal("invoices_list" in request, false);
});

test("rejects a batch before calling the single-invoice endpoint", () => {
  const request = payload();
  request.invoices_list.push({...request.invoices_list[0]});
  assert.throws(
      () => singleInvoiceApprovalPayload(request),
      /Exactly one invoice/,
  );
});

test("extracts an approved V2 invoice response", () => {
  const approval = extractInvoiceApproval({
    status: 200,
    message: "Invoice approved",
    confirmation_number: "2026082401234567890123456",
    approved: true,
  }, payload());
  assert.equal(approval.approved, true);
  assert.equal(approval.invoiceId, "invoice_2026-0042");
  assert.equal(approval.confirmationNumber, "2026082401234567890123456");
});

test("preserves V2 rejection details", () => {
  const errors = [{
    code: 460,
    message: "Invoice not approved",
    param: "vat_number",
    location: "approval",
  }];
  const approval = extractInvoiceApproval({
    status: 200,
    message: {errors},
    confirmation_number: "0",
    approved: false,
  }, payload());
  assert.equal(approval.approved, false);
  assert.equal(approval.confirmationNumber, null);
  assert.deepEqual(approval.errors, errors);
});
