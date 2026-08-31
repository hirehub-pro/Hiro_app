"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {PDFDocument} = require("pdf-lib");

const {
  buildTaxInvoicePdf,
  footerGeneratedAtText,
  formatMoney,
  normalizeTaxInvoicePresentation,
  taxableSubtotalBeforeTax,
  visualText,
} = require("./tax_invoice_pdf");

test("hides the creation date in preview footers only", () => {
  const generatedAt = "13:00 18-08-2026";
  assert.equal(footerGeneratedAtText(generatedAt, true), null);
  assert.equal(footerGeneratedAtText(generatedAt, false), generatedAt);
});

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
        total_amount: 210,
        vat_rate: 18,
        vat_amount: 37.8,
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
    priceTaxModeDefault: "vat_exempt",
  });
  assert.equal(presentation.clientEmail, "client@example.com");
  assert.equal(presentation.paymentDueDate, null);
  assert.equal(presentation.roundTotalEnabled, true);
  assert.equal(presentation.priceTaxModeDefault, "vat_exempt");
  assert.deepEqual(Object.keys(presentation).sort(), [
    "clientAddress",
    "clientEmail",
    "clientPhone",
    "documentLogoHash",
    "documentLogoMode",
    "externalClientNumber",
    "isNegativeReceipt",
    "paymentDueDate",
    "paymentMethods",
    "priceTaxModeDefault",
    "roundTotalEnabled",
    "savedClientId",
  ]);
  assert.equal("secret" in presentation.paymentMethods[0], false);
});

test("presentation validates an inline document logo without persisting bytes", () => {
  const logoBytes = require("fs").readFileSync(
      require("path").join(__dirname, "..", "assets", "icon", "app_icon.jpg"),
  );
  const presentation = normalizeTaxInvoicePresentation({
    documentLogoMode: "inline",
    documentLogoBase64: logoBytes.toString("base64"),
  });
  assert.equal(presentation.documentLogoMode, "inline");
  assert.match(presentation.documentLogoHash, /^[a-f0-9]{64}$/);
  assert.ok(Buffer.isBuffer(presentation.documentLogoBytes));
  assert.equal(Object.keys(presentation).includes("documentLogoBytes"), false);
});

test("passes logical Hebrew to Fontkit exactly once", () => {
  assert.equal(visualText("חשבונית מס 1042"), "חשבונית מס 1042");
  assert.equal(
      visualText("תאריך: 19-08-2026 | דוא״ל: client@example.com"),
      "תאריך: 19-08-2026 | דוא״ל: client@example.com",
  );
});

test("formats PDF money with thousands separators and two decimals", () => {
  assert.equal(formatMoney(1000), "1,000.00 ₪");
  assert.equal(formatMoney(1000000.5), "1,000,000.50 ₪");
  assert.equal(formatMoney(-1234.567), "-1,234.57 ₪");
});

test("calculates the subtotal subject to VAT when exempt items exist", () => {
  const invoice = {
    amount_before_discount: 4000,
    items: [
      {
        total_amount: 1000,
        vat_rate: 18,
        priceTaxMode: "before_tax",
      },
      {
        total_amount: 1000,
        vat_rate: 18,
        priceTaxMode: "after_tax",
      },
      {
        total_amount: 2000,
        vat_rate: 0,
        priceTaxMode: "vat_exempt",
      },
    ],
  };
  assert.equal(taxableSubtotalBeforeTax(invoice), 2000);
});

test("server generator wraps long item descriptions without failing", async () => {
  const payload = samplePayload();
  payload.invoices_list[0].items[0].description =
    "שירות מקצועי ארוך במיוחד שצריך לעבור לשורה נוספת בתוך עמודת " +
    "התיאור בלי לגלוש אל עמודות הכמות והמחירים";
  payload.invoices_list[0].items.push({
    description: "תיאורארוךמאודללאמרווחיםשגםהואחייבלהישארבתוךעמודתהתיאורבלבד",
    quantity: 1000,
    price_per_unit: 1000000,
    total_amount: 1000000000,
    vat_rate: 18,
    vat_amount: 180000000,
  });
  const bytes = await buildTaxInvoicePdf({
    payload,
    allocation: null,
    reservation: {
      docType: "quote",
      documentNumber: "",
      sequenceNumber: null,
      invoiceDocId: "quote_wrapping_test",
    },
    business: {
      name: "עסק בדיקה",
      businessId: "123456789",
      dealerType: "licensed",
    },
    presentation: normalizeTaxInvoicePresentation({}),
    generatedAt: new Date("2026-08-18T10:00:00Z"),
  });
  const pdf = await PDFDocument.load(bytes);
  assert.ok(pdf.getPageCount() >= 1);
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

test("preview PDFs are marked preview-only without changing final PDFs", async () => {
  const input = {
    payload: samplePayload(),
    allocation: null,
    reservation: {
      docType: "quote",
      documentNumber: "",
      sequenceNumber: null,
      invoiceDocId: "quote_preview_test",
    },
    business: {
      name: "עסק בדיקה",
      businessId: "123456789",
      address: "רחוב העסק 2",
      dealerType: "licensed",
    },
    presentation: normalizeTaxInvoicePresentation({
      clientAddress: "רחוב הלקוח 1",
    }),
    generatedAt: new Date("2026-08-18T10:00:00Z"),
  };
  const [previewBytes, finalBytes] = await Promise.all([
    buildTaxInvoicePdf({...input, previewOnly: true}),
    buildTaxInvoicePdf({...input, previewOnly: false}),
  ]);
  const previewPdf = await PDFDocument.load(previewBytes);
  const finalPdf = await PDFDocument.load(finalBytes);
  assert.equal(previewPdf.getSubject(), "Hiro document preview - not final");
  assert.equal(finalPdf.getSubject(), "Hiro quote document");
  assert.notDeepEqual(previewBytes, finalBytes);
});

test("server generator creates a receipt without Tax Authority allocation", async () => {
  const payload = samplePayload();
  payload.invoices_payment_amount = 100;
  payload.invoices_vat_amount = 0;
  payload.invoices_list[0] = {
    ...payload.invoices_list[0],
    invoice_id: "receipt_2026-0044",
    invoice_reference_number: "2026-0044",
    amount_before_discount: 100,
    discount: 0,
    payment_amount: 100,
    vat_amount: 0,
    payment_amount_including_vat: 100,
    items: [],
  };
  const bytes = await buildTaxInvoicePdf({
    payload,
    allocation: null,
    reservation: {
      docType: "receipt",
      documentNumber: "2026-0044",
      sequenceNumber: 44,
      invoiceDocId: "receipt_2026-0044",
    },
    business: {
      name: "עסק בדיקה",
      businessId: "123456789",
      address: "רחוב העסק 2",
      dealerType: "licensed",
    },
    presentation: normalizeTaxInvoicePresentation({
      paymentMethods: [{method: "bit", amount: 100}],
    }),
    generatedAt: new Date("2026-08-18T10:00:00Z"),
  });
  const pdf = await PDFDocument.load(bytes);
  assert.equal(pdf.getTitle(), "קבלה 2026-0044");
  assert.equal(pdf.getSubject(), "Hiro receipt document");
});

test("Flutter-matched renderer supports every document type", async () => {
  const types = [
    "quote",
    "work_order",
    "transaction_account",
    "invoice",
    "invoice_receipt",
    "credit_note",
    "receipt",
  ];
  for (const [index, docType] of types.entries()) {
    const currentPayload = samplePayload();
    const isReceipt = docType === "receipt";
    if (isReceipt) {
      currentPayload.invoices_payment_amount = 236;
      currentPayload.invoices_vat_amount = 0;
      currentPayload.invoices_list[0] = {
        ...currentPayload.invoices_list[0],
        amount_before_discount: 236,
        discount: 0,
        payment_amount: 236,
        vat_amount: 0,
        payment_amount_including_vat: 236,
        items: [],
      };
    }
    const bytes = await buildTaxInvoicePdf({
      payload: currentPayload,
      allocation: docType === "invoice" ?
        {confirmationNumber: "123456789"} : null,
      reservation: {
        docType,
        documentNumber: ["quote", "work_order"].includes(docType) ?
          "" : `2026-${String(index + 1).padStart(4, "0")}`,
        sequenceNumber: ["quote", "work_order"].includes(docType) ?
          null : index + 1,
        invoiceDocId: `${docType}_sample`,
      },
      business: {
        name: "עסק בדיקה",
        businessId: "123456789",
        address: "רחוב העסק 2",
        dealerType: "licensed",
      },
      presentation: normalizeTaxInvoicePresentation({
        paymentDueDate: "2026-09-18",
        paymentMethods: ["invoice_receipt", "receipt"].includes(docType) ?
          [{method: "cash", amount: 236}] : [],
      }),
      generatedAt: new Date("2026-08-19T10:00:00Z"),
    });
    const pdf = await PDFDocument.load(bytes);
    assert.ok(pdf.getPageCount() >= 1, docType);
    assert.equal(bytes.subarray(0, 4).toString("ascii"), "%PDF", docType);
  }
});
