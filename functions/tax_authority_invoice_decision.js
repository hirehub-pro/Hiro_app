const DECISION_PATHS = Object.freeze({
  cancel: "Cancel",
  continue: "Continue",
  further_objection: "FurtherObjection",
});

function normalizeInvoiceDecision(value) {
  const decision = String(value || "").trim().toLowerCase();
  if (!Object.hasOwn(DECISION_PATHS, decision)) {
    throw new Error("Unsupported Tax Authority invoice decision.");
  }
  return decision;
}

function invoiceDecisionPath(decision) {
  return `/InvoiceDecisionApi/v1/${DECISION_PATHS[
    normalizeInvoiceDecision(decision)
  ]}`;
}

function invoiceDecisionPayload(authoritativePayload) {
  const invoices = authoritativePayload?.invoices_list;
  if (!Array.isArray(invoices) || invoices.length !== 1) {
    throw new Error("Exactly one authoritative invoice is required.");
  }
  const invoice = invoices[0];
  return {
    invoice_id: invoice.invoice_id,
    vat_number: invoice.vat_number,
    ...(invoice.authorized_company == null ? {} : {
      authorized_company: invoice.authorized_company,
    }),
    ...(invoice.user_id == null ? {} : {user_id: invoice.user_id}),
    ...(invoice.user_name == null ? {} : {user_name: invoice.user_name}),
    accounting_software_number: invoice.accounting_software_number,
  };
}

function invoiceDecisionDocumentStatus(decision) {
  switch (normalizeInvoiceDecision(decision)) {
    case "cancel":
      return "allocation_cancelled";
    case "continue":
      return "continued_without_allocation";
    case "further_objection":
      return "hearing_requested";
  }
}

module.exports = {
  invoiceDecisionDocumentStatus,
  invoiceDecisionPath,
  invoiceDecisionPayload,
  normalizeInvoiceDecision,
};
