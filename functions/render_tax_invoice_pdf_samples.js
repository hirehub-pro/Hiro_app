"use strict";

const fs = require("fs");
const path = require("path");
const {buildTaxInvoicePdf, normalizeTaxInvoicePresentation} =
  require("./tax_invoice_pdf");

const outputDirectory = process.argv[2] || "/tmp/hiro-pdf-qa";
fs.mkdirSync(outputDirectory, {recursive: true});

function payload(overrides = {}) {
  return {
    vat_number: 123456789,
    invoices_payment_amount: 1000,
    invoices_vat_amount: 180,
    invoices_list: [{
      invoice_id: "invoice_receipt_2026-0042",
      invoice_type: 305,
      invoice_reference_number: "2026-0042",
      customer_vat_number: 987654321,
      customer_name: "לקוח לדוגמה בע״מ",
      invoice_date: "2026-08-19",
      invoice_issuance_date: "2026-08-19",
      amount_before_discount: 1050,
      discount: 50,
      payment_amount: 1000,
      vat_amount: 180,
      payment_amount_including_vat: 1180,
      invoice_note: "תודה שבחרתם בהירו. מסמך זה נוצר לצורך בדיקת העיצוב.",
      items: [
        {
          description: "שירות התקנה ובדיקה",
          quantity: 2,
          price_per_unit: 300,
          total_amount: 600,
          vat_rate: 18,
          vat_amount: 108,
        },
        {
          description: "ציוד וחומרים",
          quantity: 1,
          price_per_unit: 450,
          total_amount: 450,
          vat_rate: 18,
          vat_amount: 81,
        },
      ],
      ...overrides,
    }],
  };
}

const business = {
  name: "העסק של ישראל ישראלי",
  businessId: "123456789",
  address: "רחוב הרצל 10, תל אביב",
  dealerType: "licensed",
  phone: "050-1234567",
  email: "owner@example.com",
  logoBytes: fs.readFileSync(path.join(__dirname, "..", "assets", "icon", "app_icon.jpg")),
  appIconBytes: fs.readFileSync(path.join(__dirname, "..", "assets", "icon", "app_icon.jpg")),
};

async function render() {
  const invoiceReceipt = await buildTaxInvoicePdf({
    payload: payload(),
    allocation: {confirmationNumber: "987654321"},
    reservation: {
      docType: "invoice_receipt",
      documentNumber: "2026-0042",
      sequenceNumber: 42,
      invoiceDocId: "invoice_receipt_2026-0042",
    },
    business: {
      ...business,
      logoBytes: Buffer.from(business.logoBytes),
      appIconBytes: Buffer.from(business.appIconBytes),
    },
    presentation: normalizeTaxInvoicePresentation({
      clientAddress: "רחוב הלקוח 25, ירושלים",
      clientPhone: "052-7654321",
      clientEmail: "client@example.com",
      roundTotalEnabled: true,
      paymentMethods: [
        {
          method: "credit",
          amount: 700,
          cardName: "Visa",
          cardNumber: "1234",
          cardExpiration: "12/29",
          installments: "5",
          paymentDate: "2026-09-10",
          installmentDates: [
            "2026-09-10",
            "2026-10-10",
            "2026-11-10",
            "2026-12-10",
            "2027-01-10",
          ],
        },
        {method: "transfer", amount: 300, bank: "לאומי", branch: "800", account: "123456"},
        {method: "bit", amount: 180},
      ],
    }),
    generatedAt: new Date("2026-08-19T09:30:00Z"),
  });
  fs.writeFileSync(path.join(outputDirectory, "invoice-receipt.pdf"), invoiceReceipt);

  const quotePayload = payload({
    invoice_id: "quote_operation_0043",
    invoice_reference_number: "",
  });
  const quote = await buildTaxInvoicePdf({
    payload: quotePayload,
    allocation: null,
    reservation: {
      docType: "quote",
      documentNumber: "",
      sequenceNumber: null,
      invoiceDocId: "quote_operation_0043",
    },
    business: {
      ...business,
      logoBytes: Buffer.from(business.logoBytes),
      appIconBytes: Buffer.from(business.appIconBytes),
    },
    presentation: normalizeTaxInvoicePresentation({
      clientAddress: "רחוב הלקוח 25, ירושלים",
      clientPhone: "052-7654321",
      clientEmail: "client@example.com",
      paymentDueDate: "2026-09-19",
    }),
    generatedAt: new Date("2026-08-19T09:30:00Z"),
  });
  fs.writeFileSync(path.join(outputDirectory, "quote.pdf"), quote);

  const quotePreview = await buildTaxInvoicePdf({
    payload: quotePayload,
    allocation: null,
    reservation: {
      docType: "quote",
      documentNumber: "",
      sequenceNumber: null,
      invoiceDocId: "quote_operation_0043",
    },
    business: {
      ...business,
      logoBytes: Buffer.from(business.logoBytes),
      appIconBytes: Buffer.from(business.appIconBytes),
    },
    presentation: normalizeTaxInvoicePresentation({
      clientAddress: "רחוב הלקוח 25, ירושלים",
      clientPhone: "052-7654321",
      clientEmail: "client@example.com",
      paymentDueDate: "2026-09-19",
    }),
    generatedAt: new Date("2026-08-19T09:30:00Z"),
    previewOnly: true,
  });
  fs.writeFileSync(
      path.join(outputDirectory, "quote-preview.pdf"),
      quotePreview,
  );
}

render().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
