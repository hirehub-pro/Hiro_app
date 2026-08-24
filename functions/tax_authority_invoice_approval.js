function singleInvoiceApprovalPayload(payload) {
  const invoices = payload?.invoices_list;
  if (!Array.isArray(invoices) || invoices.length !== 1) {
    throw new Error("Exactly one invoice is required by Invoices/v2/Approval.");
  }
  return invoices[0];
}

function extractInvoiceApproval(response, requestPayload) {
  const confirmationNumber = String(
      response?.confirmation_number ?? "",
  ).trim();
  const approved = response?.approved === true &&
    confirmationNumber !== "" && confirmationNumber !== "0";

  return {
    approved,
    invoiceId: requestPayload?.invoices_list?.[0]?.invoice_id || null,
    confirmationNumber: approved ? confirmationNumber : null,
    transactionId: null,
    errors: Array.isArray(response?.message?.errors) ?
      response.message.errors : [],
  };
}

module.exports = {
  extractInvoiceApproval,
  singleInvoiceApprovalPayload,
};
