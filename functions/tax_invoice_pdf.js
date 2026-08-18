"use strict";

const fs = require("fs");
const path = require("path");
const fontkit = require("@pdf-lib/fontkit");
const bidi = require("bidi-js")();
const {PDFDocument, rgb} = require("pdf-lib");

const A4 = {width: 595.28, height: 841.89};
const MARGIN = 42;
const BLUE = rgb(0.10, 0.46, 0.82);
const BLUE_DARK = rgb(0.05, 0.22, 0.45);
const BLUE_PALE = rgb(0.93, 0.97, 1);
const TEXT = rgb(0.08, 0.12, 0.20);
const MUTED = rgb(0.28, 0.36, 0.47);
const LINE = rgb(0.80, 0.84, 0.89);
const WHITE = rgb(1, 1, 1);
const FONT_PATH = path.join(
    __dirname,
    "assets",
    "fonts",
    "Rubik-VariableFont_wght.ttf",
);

function boundedString(value, maxLength, fallback = "") {
  const result = value == null ? "" : String(value).trim();
  return (result || fallback).slice(0, maxLength);
}

function boundedOptionalString(value, maxLength) {
  const result = boundedString(value, maxLength);
  return result || null;
}

function safeNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function money(value) {
  return Math.round(safeNumber(value) * 100) / 100;
}

function normalizePaymentMethods(value) {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 20).map((entry) => {
    const data = entry && typeof entry === "object" ? entry : {};
    return {
      method: boundedString(data.method, 24, "cash"),
      amount: Math.max(0, money(data.amount)),
      cardNumber: boundedOptionalString(data.cardNumber, 32),
      cardName: boundedOptionalString(data.cardName, 80),
      cardExpiration: boundedOptionalString(data.cardExpiration, 12),
      installments: boundedOptionalString(data.installments, 8),
      checkNumber: boundedOptionalString(data.checkNumber, 32),
      bank: boundedOptionalString(data.bank, 80),
      branch: boundedOptionalString(data.branch, 32),
      account: boundedOptionalString(data.account, 40),
    };
  });
}

/**
 * Whitelists non-authoritative document presentation data. All monetary fields
 * shown in the PDF are derived later from the validated Tax Authority payload.
 *
 * @param {unknown} value raw callable value
 * @return {object} safe presentation data
 */
function normalizeTaxInvoicePresentation(value) {
  const data = value && typeof value === "object" ? value : {};
  const dueDate = boundedOptionalString(data.paymentDueDate, 10);
  return {
    clientAddress: boundedString(data.clientAddress, 500),
    clientPhone: boundedString(data.clientPhone, 32),
    clientEmail: (() => {
      const email = boundedString(data.clientEmail, 254).toLowerCase();
      return !email || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : "";
    })(),
    externalClientNumber: boundedString(data.externalClientNumber, 40),
    savedClientId: boundedOptionalString(data.savedClientId, 180),
    priceTaxModeDefault: ["before_tax", "after_tax"].includes(
        boundedString(data.priceTaxModeDefault, 20),
    ) ? data.priceTaxModeDefault : "before_tax",
    roundTotalEnabled: data.roundTotalEnabled === true,
    paymentDueDate: dueDate && /^\d{4}-\d{2}-\d{2}$/.test(dueDate) ? dueDate : null,
    paymentMethods: normalizePaymentMethods(data.paymentMethods),
  };
}

function validateTaxInvoicePresentation({presentation, payload, reservation}) {
  if (reservation.docType !== "invoice_receipt") return;
  if (presentation.paymentMethods.length < 1) {
    throw new Error("An invoice-receipt must include a payment method.");
  }
  const invoice = payload.invoices_list[0];
  const beforeRounding = money(invoice.payment_amount_including_vat);
  const rounding = presentation.roundTotalEnabled ?
    money(beforeRounding - Math.floor(beforeRounding)) : 0;
  const expected = money(beforeRounding - rounding);
  const paid = money(presentation.paymentMethods.reduce(
      (total, method) => total + method.amount,
      0,
  ));
  if (Math.abs(expected - paid) > 0.02) {
    throw new Error(
        "The invoice-receipt payment methods do not match its final total.",
    );
  }
}

function visualText(value, direction = "rtl") {
  const text = boundedString(value, 4000);
  if (!text) return "";
  const levels = bidi.getEmbeddingLevels(text, direction);
  return bidi.getReorderedString(text, levels);
}

function formatMoney(value) {
  return `${money(value).toFixed(2)} \u20aa`;
}

function formatDate(value) {
  const match = boundedString(value, 10).match(/^(\d{4})-(\d{2})-(\d{2})$/);
  return match ? `${match[3]}-${match[2]}-${match[1]}` : boundedString(value, 30);
}

function documentTitle(docType) {
  return {
    quote: "הצעת מחיר",
    work_order: "הזמנת עבודה",
    transaction_account: "חשבון עסקה",
    invoice: "חשבונית מס",
    invoice_receipt: "חשבונית מס / קבלה",
    credit_note: "חשבונית זיכוי",
    receipt: "קבלה",
  }[docType] || "מסמך";
}

function dealerLabel(dealerType) {
  return dealerType === "company" ? "חברה בע״מ" : "עוסק מורשה";
}

function paymentMethodLabel(method) {
  return {
    cash: "מזומן",
    credit: "כרטיס אשראי",
    check: "המחאה",
    transfer: "העברה בנקאית",
  }[method] || method;
}

function wrapLogicalText(text, font, size, maxWidth, direction = "rtl") {
  const words = boundedString(text, 4000).split(/\s+/).filter(Boolean);
  if (words.length === 0) return [];
  const lines = [];
  let line = "";
  for (const word of words) {
    const candidate = line ? `${line} ${word}` : word;
    if (font.widthOfTextAtSize(visualText(candidate, direction), size) <= maxWidth) {
      line = candidate;
    } else {
      if (line) lines.push(line);
      line = word;
    }
  }
  if (line) lines.push(line);
  return lines;
}

function drawRight(page, font, value, xRight, y, size, options = {}) {
  const text = visualText(value, options.direction || "rtl");
  const width = font.widthOfTextAtSize(text, size);
  page.drawText(text, {
    x: Math.max(MARGIN, xRight - width),
    y,
    size,
    font,
    color: options.color || TEXT,
  });
  return width;
}

function drawLeft(page, font, value, x, y, size, options = {}) {
  page.drawText(visualText(value, options.direction || "ltr"), {
    x,
    y,
    size,
    font,
    color: options.color || TEXT,
  });
}

function drawLabelValue(page, font, label, value, xRight, y, width) {
  const labelWidth = drawRight(page, font, `${label}:`, xRight, y, 9, {color: MUTED});
  const valueRight = xRight - labelWidth - 6;
  const safeValue = boundedString(value, 500, "—");
  const lines = wrapLogicalText(safeValue, font, 9, Math.max(60, width - labelWidth - 10));
  drawRight(page, font, lines[0] || "—", valueRight, y, 9);
}

function drawFooter(page, font, pageNumber, generatedAt) {
  page.drawLine({
    start: {x: MARGIN, y: 35},
    end: {x: A4.width - MARGIN, y: 35},
    thickness: 0.6,
    color: LINE,
  });
  drawLeft(page, font, `${pageNumber}`, MARGIN, 20, 8, {color: MUTED});
  drawRight(page, font, "מסמך ממוחשב הופק על ידי הירו", A4.width - MARGIN, 20, 8, {
    color: MUTED,
  });
  drawLeft(page, font, generatedAt, MARGIN + 18, 20, 8, {color: MUTED});
}

function addInvoicePage(pdf) {
  return pdf.addPage([A4.width, A4.height]);
}

function drawPageHeader(page, font, reservation, allocation, payload, logo) {
  const x = MARGIN;
  const width = A4.width - MARGIN * 2;
  page.drawRectangle({x, y: 706, width, height: 94, color: BLUE_PALE});
  if (logo) {
    page.drawImage(logo, {
      x: MARGIN + 18,
      y: 720,
      width: 65,
      height: 65,
    });
  }
  drawRight(page, font, documentTitle(reservation.docType), A4.width - MARGIN - 18, 765, 22, {
    color: BLUE_DARK,
  });
  const originalLabel = reservation.documentNumber ?
    `מקור | מס׳ ${reservation.documentNumber}` : "מקור";
  drawRight(page, font, originalLabel, A4.width - MARGIN - 18, 744, 10, {
    color: MUTED,
  });
  if (allocation?.confirmationNumber) {
    drawRight(page, font, `מספר הקצאה: ${allocation.confirmationNumber}`, A4.width - MARGIN - 18, 725, 10, {
      color: MUTED,
    });
  }
  drawLeft(page, font, formatDate(payload.invoices_list[0].invoice_date), MARGIN + 18, 725, 10, {
    color: MUTED,
  });
}

function addDetailCard(page, font, title, entries, x, y, width, height, color) {
  page.drawRectangle({x, y, width, height, color, borderColor: LINE, borderWidth: 0.5});
  drawRight(page, font, title, x + width - 12, y + height - 22, 12, {color: BLUE_DARK});
  let rowY = y + height - 42;
  for (const [label, value] of entries) {
    if (!value) continue;
    drawLabelValue(page, font, label, value, x + width - 12, rowY, width - 24);
    rowY -= 16;
  }
}

function drawItemsHeader(page, font, y) {
  const x = MARGIN;
  const widths = [250, 62, 95, 104];
  page.drawRectangle({x, y: y - 23, width: widths.reduce((a, b) => a + b, 0), height: 25, color: BLUE});
  const labels = ["תיאור", "כמות", "מחיר לפני מע״מ", "סה״כ כולל מע״מ"];
  let cursor = x;
  labels.forEach((label, index) => {
    drawRight(page, font, label, cursor + widths[index] - 7, y - 15, 8, {color: WHITE});
    cursor += widths[index];
  });
  return widths;
}

function drawItemRow(page, font, item, y, widths) {
  const x = MARGIN;
  const rowHeight = 30;
  page.drawRectangle({
    x,
    y: y - rowHeight + 5,
    width: widths.reduce((a, b) => a + b, 0),
    height: rowHeight,
    borderColor: LINE,
    borderWidth: 0.5,
  });
  const totalIncludingVat = money(item.total_amount + item.vat_amount);
  const values = [
    boundedString(item.description, 120, "פריט"),
    money(item.quantity).toString(),
    formatMoney(item.price_per_unit),
    formatMoney(totalIncludingVat),
  ];
  let cursor = x;
  values.forEach((value, index) => {
    drawRight(page, font, value, cursor + widths[index] - 7, y - 13, 8, {
      direction: index === 0 ? "rtl" : "ltr",
    });
    cursor += widths[index];
  });
  return rowHeight;
}

function drawSummary(page, font, invoice, presentation, y) {
  const width = 245;
  const x = A4.width - MARGIN - width;
  const beforeRounding = money(invoice.payment_amount_including_vat);
  const rounding = presentation.roundTotalEnabled ? money(beforeRounding - Math.floor(beforeRounding)) : 0;
  const finalTotal = money(beforeRounding - rounding);
  const hasVat = invoice.items.some((item) => Number(item.vat_rate) > 0);
  const rows = hasVat ? [
    ["סה״כ לפני מע״מ", formatMoney(invoice.payment_amount)],
    ["מע״מ", formatMoney(invoice.vat_amount)],
  ] : [];
  if (invoice.discount > 0) rows.unshift(["הנחה", `-${formatMoney(invoice.discount)}`]);
  if (rounding > 0) rows.push(["עיגול", `-${formatMoney(rounding)}`]);
  rows.push(["סה״כ לתשלום", formatMoney(finalTotal)]);
  const height = 18 + rows.length * 21;
  page.drawRectangle({x, y: y - height, width, height, color: BLUE_PALE, borderColor: LINE, borderWidth: 0.5});
  let rowY = y - 23;
  rows.forEach(([label, value], index) => {
    const isLast = index === rows.length - 1;
    drawRight(page, font, label, x + width - 12, rowY, isLast ? 11 : 9, {
      color: isLast ? BLUE_DARK : TEXT,
    });
    drawLeft(page, font, value, x + 12, rowY, isLast ? 11 : 9, {
      color: isLast ? BLUE_DARK : TEXT,
    });
    rowY -= 21;
  });
  return {bottom: y - height, finalTotal, rounding};
}

/**
 * Builds the final authoritative allocation invoice PDF.
 *
 * @param {object} input PDF data
 * @return {Promise<Buffer>} generated bytes
 */
async function buildTaxInvoicePdf({
  payload,
  allocation,
  reservation,
  business,
  presentation,
  generatedAt = new Date(),
}) {
  const invoice = payload.invoices_list[0];
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const fontBytes = fs.readFileSync(FONT_PATH);
  const font = await pdf.embedFont(fontBytes, {subset: true});
  let logo = null;
  if (business.logoBytes) {
    try {
      logo = await pdf.embedJpg(business.logoBytes);
    } catch (error) {
      try {
        logo = await pdf.embedPng(business.logoBytes);
      } catch (ignoredError) {
        logo = null;
      }
    }
  }
  const createdLabel = new Intl.DateTimeFormat("he-IL", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "Asia/Jerusalem",
  }).format(generatedAt);

  let page = addInvoicePage(pdf);
  let pageNumber = 1;
  drawPageHeader(page, font, reservation, allocation, payload, logo);
  drawFooter(page, font, pageNumber, createdLabel);

  const cardWidth = (A4.width - MARGIN * 2 - 16) / 2;
  addDetailCard(page, font, "פרטי העסק", [
    ["שם", business.name],
    [dealerLabel(business.dealerType), business.businessId],
    ["כתובת", business.address],
    ["טלפון", business.phone],
    ["דוא״ל", business.email],
  ], MARGIN, 572, cardWidth, 116, BLUE_PALE);
  addDetailCard(page, font, "פרטי לקוח", [
    ["לכבוד", invoice.customer_name],
    ["מספר עוסק", invoice.customer_vat_number],
    ["כתובת", presentation.clientAddress],
    ["טלפון", presentation.clientPhone],
    ["דוא״ל", presentation.clientEmail],
  ], MARGIN + cardWidth + 16, 572, cardWidth, 116, rgb(0.97, 0.97, 0.98));

  let y = 544;
  if (reservation.docType !== "receipt") {
    let widths = drawItemsHeader(page, font, y);
    y -= 27;
    for (const item of invoice.items) {
      if (y < 115) {
        page = addInvoicePage(pdf);
        pageNumber += 1;
        drawFooter(page, font, pageNumber, createdLabel);
        y = 780;
        widths = drawItemsHeader(page, font, y);
        y -= 27;
      }
      y -= drawItemRow(page, font, item, y, widths);
    }
  }

  if (y < 230) {
    page = addInvoicePage(pdf);
    pageNumber += 1;
    drawFooter(page, font, pageNumber, createdLabel);
    y = 780;
  }
  const summary = drawSummary(page, font, invoice, presentation, y - 12);
  y = summary.bottom - 22;

  if (["invoice_receipt", "receipt"].includes(reservation.docType) &&
      presentation.paymentMethods.length > 0) {
    drawRight(page, font, "פרטי תשלום", A4.width - MARGIN, y, 11, {color: BLUE_DARK});
    y -= 19;
    for (const method of presentation.paymentMethods) {
      const details = [
        paymentMethodLabel(method.method),
        formatMoney(method.amount),
        method.checkNumber ? `מס׳ ${method.checkNumber}` : null,
        method.cardNumber ? `כרטיס ${method.cardNumber}` : null,
      ].filter(Boolean).join(" | ");
      drawRight(page, font, details, A4.width - MARGIN, y, 9);
      y -= 16;
    }
  }

  if (invoice.invoice_note) {
    if (y < 95) {
      page = addInvoicePage(pdf);
      pageNumber += 1;
      drawFooter(page, font, pageNumber, createdLabel);
      y = 780;
    }
    drawRight(page, font, "הערות", A4.width - MARGIN, y, 11, {color: BLUE_DARK});
    y -= 17;
    for (const line of wrapLogicalText(invoice.invoice_note, font, 9, A4.width - MARGIN * 2)) {
      drawRight(page, font, line, A4.width - MARGIN, y, 9);
      y -= 14;
    }
  }

  pdf.setTitle(`${documentTitle(reservation.docType)} ${reservation.documentNumber}`);
  pdf.setSubject(allocation?.confirmationNumber ?
    `Tax Authority allocation ${allocation.confirmationNumber}` :
    `Hiro ${reservation.docType} document`);
  pdf.setCreator("Hiro server invoice service");
  pdf.setProducer("Hiro");
  pdf.setCreationDate(generatedAt);
  const bytes = await pdf.save();
  return Buffer.from(bytes);
}

module.exports = {
  buildTaxInvoicePdf,
  formatMoney,
  normalizeTaxInvoicePresentation,
  validateTaxInvoicePresentation,
  visualText,
};
