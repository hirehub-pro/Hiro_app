"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const fontkit = require("@pdf-lib/fontkit");
const {PDFDocument, degrees, rgb} = require("pdf-lib");

const A4 = {width: 595.28, height: 841.89};
const MARGIN = 42.52;
const BLUE = rgb(33 / 255, 150 / 255, 243 / 255);
const BLUE_DARK = rgb(13 / 255, 71 / 255, 161 / 255);
const BLUE_PALE = rgb(227 / 255, 242 / 255, 253 / 255);
const CLIENT_PALE = rgb(245 / 255, 245 / 255, 245 / 255);
const TEXT = rgb(33 / 255, 33 / 255, 33 / 255);
const MUTED = rgb(55 / 255, 71 / 255, 79 / 255);
const MUTED_LIGHT = rgb(69 / 255, 90 / 255, 100 / 255);
const LINE = rgb(189 / 255, 189 / 255, 189 / 255);
const LINE_LIGHT = rgb(224 / 255, 224 / 255, 224 / 255);
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

function normalizeDocumentLogo(data) {
  const mode = ["default", "none", "inline"].includes(data.documentLogoMode) ?
    data.documentLogoMode : "default";
  if (mode !== "inline") return {mode, hash: null, bytes: null};
  const encoded = typeof data.documentLogoBase64 === "string" ?
    data.documentLogoBase64.trim() : "";
  const storedHash = boundedString(data.documentLogoHash, 64);
  if (!encoded && /^[a-f0-9]{64}$/.test(storedHash)) {
    return {mode, hash: storedHash, bytes: null};
  }
  if (!encoded || encoded.length > 4 * 1024 * 1024 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) {
    throw new Error("The document logo is invalid or too large.");
  }
  const bytes = Buffer.from(encoded, "base64");
  const isJpeg = bytes.length >= 3 && bytes[0] === 0xff &&
    bytes[1] === 0xd8 && bytes[2] === 0xff;
  const isPng = bytes.length >= 8 &&
    bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  if (bytes.length < 1 || bytes.length > 3 * 1024 * 1024 ||
      (!isJpeg && !isPng)) {
    throw new Error("The document logo must be a JPEG or PNG under 3 MB.");
  }
  return {
    mode,
    hash: crypto.createHash("sha256").update(bytes).digest("hex"),
    bytes,
  };
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
  const logo = normalizeDocumentLogo(data);
  const result = {
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
    isNegativeReceipt: data.isNegativeReceipt === true,
    paymentDueDate: dueDate && /^\d{4}-\d{2}-\d{2}$/.test(dueDate) ? dueDate : null,
    paymentMethods: normalizePaymentMethods(data.paymentMethods),
    documentLogoMode: logo.mode,
    documentLogoHash: logo.hash,
  };
  Object.defineProperty(result, "documentLogoBytes", {
    value: logo.bytes,
    enumerable: false,
  });
  return result;
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
  // Fontkit performs Unicode bidirectional layout while encoding the embedded
  // Rubik font. Returning logical text here prevents a second reversal of
  // Hebrew glyphs while preserving numbers, dates, email addresses and marks.
  return boundedString(value, 4000);
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
  if (dealerType === "company") return "חברה בע״מ";
  return dealerType === "licensed" ? "עוסק מורשה" : "עוסק פטור";
}

function displayDocumentNumber(value) {
  const raw = boundedString(value, 40);
  const suffix = raw.split("-").at(-1);
  const parsed = Number.parseInt(suffix, 10);
  return Number.isFinite(parsed) ? String(parsed) : suffix;
}

function paymentMethodLabel(method) {
  return {
    cash: "מזומן",
    credit: "כרטיס אשראי",
    check: "המחאה",
    transfer: "העברה בנקאית",
    bit: "ביט",
    paybox: "פייבוקס",
    other: "אחר",
    withholding_tax: "ניכוי מס במקור",
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
  const text = visualText(value, options.direction || "ltr");
  page.drawText(text, {
    x,
    y,
    size,
    font,
    color: options.color || TEXT,
  });
  return font.widthOfTextAtSize(text, size);
}

function drawRoundedRectangle(page, {x, y, width, height, radius = 8,
  color, borderColor, borderWidth = 0}) {
  const r = Math.max(0, Math.min(radius, width / 2, height / 2));
  if (color) {
    page.drawRectangle({x: x + r, y, width: width - r * 2, height, color});
    page.drawRectangle({x, y: y + r, width, height: height - r * 2, color});
    for (const [cx, cy] of [
      [x + r, y + r], [x + width - r, y + r],
      [x + r, y + height - r], [x + width - r, y + height - r],
    ]) {
      page.drawCircle({x: cx, y: cy, size: r, color});
    }
  }
  if (borderColor && borderWidth > 0) {
    page.drawLine({
      start: {x: x + r, y}, end: {x: x + width - r, y},
      thickness: borderWidth, color: borderColor,
    });
    page.drawLine({
      start: {x: x + r, y: y + height},
      end: {x: x + width - r, y: y + height},
      thickness: borderWidth, color: borderColor,
    });
    page.drawLine({
      start: {x, y: y + r}, end: {x, y: y + height - r},
      thickness: borderWidth, color: borderColor,
    });
    page.drawLine({
      start: {x: x + width, y: y + r},
      end: {x: x + width, y: y + height - r},
      thickness: borderWidth, color: borderColor,
    });
  }
}

function drawLabelValue(page, font, label, value, xRight, y, width) {
  const labelWidth = drawRight(page, font, `${label}:`, xRight, y, 11.25, {
    color: TEXT,
  });
  const valueRight = xRight - labelWidth - 3;
  const safeValue = boundedString(value, 500, "—");
  const lines = wrapLogicalText(safeValue, font, 11.25,
      Math.max(60, width - labelWidth - 6));
  drawRight(page, font, lines[0] || "—", valueRight, y, 11.25);
}

function drawInlineLabelValue(page, font, label, value, xRight, y, size,
    options = {}) {
  const labelWidth = drawRight(page, font, `${label}:`, xRight, y, size, {
    color: options.color || TEXT,
  });
  drawRight(page, font, value, xRight - labelWidth - 3, y, size, {
    color: options.color || TEXT,
    direction: options.valueDirection || "ltr",
  });
}

function drawFooter(page, font, pageNumber, pageCount, generatedAt,
    reservation, appIcon) {
  page.drawLine({
    start: {x: MARGIN, y: 59},
    end: {x: A4.width - MARGIN, y: 59},
    thickness: 0.8,
    color: rgb(38 / 255, 50 / 255, 56 / 255),
  });
  drawRight(page, font, "חתימה דיגיטלית מאובטחת",
      A4.width - MARGIN, 37, 15.75, {color: TEXT});
  const signatureRight = A4.width - MARGIN;
  const signatureHelper = "מסמך ממוחשב הופק על ידי הירו";
  const signatureHelperWidth = drawRight(
      page, font, signatureHelper, signatureRight, 20, 8.25, {color: MUTED},
  );
  if (appIcon) {
    const scale = Math.min(20 / appIcon.width, 20 / appIcon.height);
    const iconWidth = appIcon.width * scale;
    page.drawImage(appIcon, {
      x: signatureRight - signatureHelperWidth - 4 - iconWidth,
      y: 13,
      width: iconWidth,
      height: appIcon.height * scale,
    });
  }

  const number = displayDocumentNumber(reservation.documentNumber);
  let footerX = MARGIN;
  if (number) {
    footerX += drawLeft(page, font, number, footerX, 36, 8.25, {
      color: MUTED,
      direction: "ltr",
    });
    footerX += 3;
  }
  footerX += drawLeft(
      page, font, documentTitle(reservation.docType), footerX, 36, 8.25,
      {color: MUTED},
  );
  footerX += 4;
  footerX += drawLeft(page, font, "|", footerX, 36, 8.25, {
    color: MUTED,
    direction: "ltr",
  });
  footerX += 4;
  footerX += drawLeft(page, font, generatedAt, footerX, 36, 8.25, {
    color: MUTED,
    direction: "ltr",
  });
  footerX += 4;
  drawLeft(page, font, "הופק ב", footerX, 36, 8.25, {color: MUTED});
  drawLeft(page, font, `${pageNumber} / ${pageCount}`, MARGIN, 17, 9.75, {
    color: MUTED_LIGHT,
  });
}

function addInvoicePage(pdf) {
  const page = pdf.addPage([A4.width, A4.height]);
  page.drawRectangle({
    x: 0,
    y: 0,
    width: A4.width,
    height: A4.height,
    color: WHITE,
  });
  return page;
}

function drawPageHeader(page, font, reservation, allocation, payload, logo) {
  const x = MARGIN;
  const width = A4.width - MARGIN * 2;
  const top = A4.height - MARGIN;
  const headerHeight = logo ? 136 : allocation?.confirmationNumber ? 114 : 98;
  const y = top - headerHeight;
  drawRoundedRectangle(page, {
    x, y, width, height: headerHeight, radius: 12, color: BLUE_PALE,
  });
  if (logo) {
    const scale = Math.min(112 / logo.width, 112 / logo.height);
    page.drawImage(logo, {
      x: MARGIN + 16 + (112 - logo.width * scale) / 2,
      y: top - 12 - 112 + (112 - logo.height * scale) / 2,
      width: logo.width * scale,
      height: logo.height * scale,
    });
  }
  const right = A4.width - MARGIN - 16;
  const number = displayDocumentNumber(reservation.documentNumber);
  const titleLabel = number ?
    `${documentTitle(reservation.docType)} מספר` :
    documentTitle(reservation.docType);
  const titleWidth = drawRight(page, font, titleLabel, right, top - 40, 27.75, {
    color: BLUE_DARK,
  });
  if (number) {
    drawRight(page, font, number, right - titleWidth - 7, top - 40, 27.75, {
      color: BLUE_DARK,
      direction: "ltr",
    });
  }
  drawRight(page, font, "מקור", right, top - 66, 15.75, {color: MUTED});
  let detailY = top - 93;
  if (allocation?.confirmationNumber) {
    drawInlineLabelValue(
        page, font, "מספר הקצאה", String(allocation.confirmationNumber),
        right, detailY, 12, {
      color: MUTED,
    });
    detailY -= 18;
  }
  drawInlineLabelValue(
      page, font, "תאריך", formatDate(payload.invoices_list[0].invoice_date),
      right, detailY, 12, {
    color: MUTED,
  });
  return y;
}

function addDetailCard(page, font, title, name, nameLabel, entries,
    x, y, width, height, color) {
  drawRoundedRectangle(page, {x, y, width, height, radius: 8, color});
  drawRight(page, font, title, x + width - 10, y + height - 22, 12.75, {
    color: BLUE_DARK,
  });
  let rowY = y + height - 46;
  if (name) {
    if (nameLabel) {
      const labelWidth = drawRight(page, font, `${nameLabel}:`,
          x + width - 10, rowY, 15, {color: TEXT});
      drawRight(page, font, name, x + width - 13 - labelWidth,
          rowY, 15, {color: TEXT});
    } else {
      drawRight(page, font, name, x + width - 10, rowY, 15, {color: TEXT});
    }
    rowY -= 19;
  }
  for (const [label, value] of entries) {
    if (!value) continue;
    drawLabelValue(page, font, label, value, x + width - 10, rowY, width - 20);
    rowY -= 14;
  }
}

function drawItemsHeader(page, font, y) {
  const x = MARGIN;
  const widths = [250.76, 60, 100, 99.48];
  page.drawRectangle({
    x, y: y - 23, width: widths.reduce((a, b) => a + b, 0),
    height: 25, color: BLUE,
  });
  const labels = ["תיאור השירות/מוצר", "כמות", "מחיר ליח׳", "סה״כ לתשלום"];
  let cursor = x;
  labels.forEach((label, index) => {
    drawRight(page, font, label, cursor + widths[index] - 7, y - 16, 12, {
      color: WHITE,
    });
    cursor += widths[index];
  });
  return widths;
}

function drawItemRow(page, font, item, y, widths) {
  const x = MARGIN;
  const rowHeight = 24;
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
    formatMoney(item.price_per_unit * (1 + Number(item.vat_rate || 0) / 100)),
    formatMoney(totalIncludingVat),
  ];
  let cursor = x;
  values.forEach((value, index) => {
    drawRight(page, font, value, cursor + widths[index] - 7, y - 14, 11.25, {
      direction: index === 0 ? "rtl" : "ltr",
    });
    cursor += widths[index];
  });
  return rowHeight;
}

function drawSummary(page, font, invoice, presentation, reservation, y) {
  const width = 260;
  const x = A4.width - MARGIN - width;
  const beforeRounding = money(invoice.payment_amount_including_vat);
  const rounding = presentation.roundTotalEnabled ? money(beforeRounding - Math.floor(beforeRounding)) : 0;
  const finalTotal = money(beforeRounding - rounding);
  const hasVat = invoice.items.some((item) => Number(item.vat_rate) > 0);
  const negative = presentation.isNegativeReceipt === true;
  const sign = (value) => negative ? -Math.abs(value) : value;
  const rows = hasVat ? [
    ["סה״כ לפני מע״מ", formatMoney(sign(invoice.payment_amount))],
    ["מע״מ", formatMoney(sign(invoice.vat_amount))],
  ] : [];
  if (invoice.discount > 0) rows.push(["הנחה", `-${formatMoney(invoice.discount)}`]);
  if (rounding > 0) {
    rows.push([
      "סכום לעיגול",
      reservation.docType === "credit_note" ?
        formatMoney(rounding) : `-${formatMoney(rounding)}`,
    ]);
  }
  rows.push([
    reservation.docType === "receipt" ? "סה״כ שולם" : "סה״כ לתשלום",
    formatMoney(sign(finalTotal)),
  ]);
  const showDueDate = presentation.paymentDueDate &&
    ["quote", "transaction_account", "invoice"].includes(reservation.docType);
  const height = 28 + rows.length * 22 + (showDueDate ? 27 : 0);
  drawRoundedRectangle(page, {
    x, y: y - height, width, height, radius: 10,
    color: BLUE_PALE, borderColor: rgb(187 / 255, 222 / 255, 251 / 255),
    borderWidth: 0.6,
  });
  let rowY = y - 25;
  rows.forEach(([label, value], index) => {
    const isLast = index === rows.length - 1;
    drawRight(page, font, label, x + width - 14, rowY,
        isLast ? 15 : 11.25, {
      color: isLast ? BLUE_DARK : TEXT,
    });
    drawLeft(page, font, value, x + 14, rowY,
        isLast ? 15 : 11.25, {
      color: isLast ? BLUE_DARK : TEXT,
    });
    if (!isLast && index < rows.length - 1) {
      page.drawLine({
        start: {x: x + 14, y: rowY - 8},
        end: {x: x + width - 14, y: rowY - 8},
        thickness: 0.45,
        color: LINE,
      });
    }
    rowY -= 21;
  });
  if (showDueDate) {
    drawRight(page, font, "תאריך אחרון לתשלום", x + width - 14,
        rowY - 1, 11.25, {color: MUTED});
    drawLeft(page, font, formatDate(presentation.paymentDueDate),
        x + 14, rowY - 1, 11.25, {color: MUTED});
  }
  return {bottom: y - height, finalTotal, rounding};
}

function paymentColumns(method) {
  const columns = ["תאריך", "סכום"];
  if (["transfer", "check"].includes(method)) {
    columns.push("שם הבנק", "סניף", "מספר חשבון");
  }
  if (method === "check") columns.push("מספר צ׳ק");
  if (method === "credit") {
    columns.push("סוג כרטיס", "מספר כרטיס", "תוקף", "מספר תשלומים");
  }
  columns.push("פרטים נוספים");
  return columns;
}

function paymentRow(method, payment, date, negative) {
  const value = (raw) => boundedString(raw, 80) || "-";
  const row = [
    formatDate(date),
    formatMoney(negative ? -Math.abs(payment.amount) : payment.amount),
  ];
  if (["transfer", "check"].includes(method)) {
    row.push(value(payment.bank), value(payment.branch), value(payment.account));
  }
  if (method === "check") row.push(value(payment.checkNumber));
  if (method === "credit") {
    row.push(
        value(payment.cardName),
        value(payment.cardNumber),
        value(payment.cardExpiration),
        value(payment.installments || "1"),
    );
  }
  row.push("-");
  return row;
}

function paymentGroups(presentation) {
  const groups = new Map();
  for (const payment of presentation.paymentMethods) {
    if (!groups.has(payment.method)) groups.set(payment.method, []);
    groups.get(payment.method).push(payment);
  }
  return [...groups.entries()];
}

function drawPaymentSectionTitle(page, font, y) {
  drawRight(page, font, "אמצעי תשלום", A4.width - MARGIN - 14, y, 12, {
    color: TEXT,
  });
  return y - 19;
}

function drawPaymentGroup(page, font, method, payments, invoice,
    presentation, y) {
  const x = MARGIN + 14;
  const width = A4.width - MARGIN * 2 - 28;
  const columns = paymentColumns(method).reverse();
  const rows = payments.map((payment) =>
    paymentRow(
        method,
        payment,
        invoice.invoice_date,
        presentation.isNegativeReceipt,
    ).reverse(),
  );
  const titleHeight = 29;
  const headerHeight = 30;
  const rowHeight = 32;
  const height = titleHeight + headerHeight + rows.length * rowHeight;
  drawRoundedRectangle(page, {
    x, y: y - height, width, height, radius: 7,
    color: WHITE, borderColor: rgb(209 / 255, 224 / 255, 239 / 255),
    borderWidth: 0.8,
  });
  page.drawRectangle({
    x, y: y - titleHeight, width, height: titleHeight,
    color: rgb(235 / 255, 245 / 255, 254 / 255),
  });
  drawRight(page, font, `אמצעי תשלום: ${paymentMethodLabel(method)}`,
      x + width - 14, y - 19, 10.5, {color: rgb(20 / 255, 84 / 255, 178 / 255)});
  page.drawRectangle({
    x, y: y - titleHeight - headerHeight,
    width, height: headerHeight,
    color: rgb(248 / 255, 251 / 255, 254 / 255),
  });
  const columnWidth = width / columns.length;
  columns.forEach((column, index) => {
    const right = x + (index + 1) * columnWidth - 5;
    drawRight(page, font, column, right, y - titleHeight - 19, 8.25, {
      color: rgb(56 / 255, 64 / 255, 77 / 255),
    });
  });
  rows.forEach((row, rowIndex) => {
    const top = y - titleHeight - headerHeight - rowIndex * rowHeight;
    page.drawLine({
      start: {x, y: top - rowHeight},
      end: {x: x + width, y: top - rowHeight},
      thickness: 0.45,
      color: rgb(209 / 255, 224 / 255, 239 / 255),
    });
    row.forEach((value, index) => {
      const right = x + (index + 1) * columnWidth - 5;
      drawRight(page, font, value, right, top - 20, 9, {
        color: rgb(46 / 255, 51 / 255, 59 / 255),
        direction: index === columns.indexOf("סכום") ? "ltr" : "rtl",
      });
    });
  });
  return y - height - 10;
}

function drawNotes(page, font, note, y) {
  const lines = wrapLogicalText(note, font, 9.75, A4.width - MARGIN * 2 - 20);
  const height = Math.max(35, 20 + lines.length * 15);
  drawRight(page, font, "הערות", A4.width - MARGIN, y, 9.75, {
    color: BLUE_DARK,
  });
  y -= 15;
  drawRoundedRectangle(page, {
    x: MARGIN, y: y - height, width: A4.width - MARGIN * 2,
    height, radius: 5, color: WHITE, borderColor: LINE_LIGHT,
    borderWidth: 0.6,
  });
  let lineY = y - 17;
  for (const line of lines) {
    drawRight(page, font, line, A4.width - MARGIN - 10, lineY, 9.75);
    lineY -= 15;
  }
  return y - height - 16;
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
  previewOnly = false,
}) {
  const invoice = payload.invoices_list[0];
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const fontBytes = fs.readFileSync(FONT_PATH);
  const font = await pdf.embedFont(fontBytes, {subset: true});

  async function embedOptionalImage(bytes) {
    if (!bytes) return null;
    const imageBytes = Buffer.from(bytes);
    try {
      return await pdf.embedJpg(imageBytes);
    } catch (error) {
      try {
        return await pdf.embedPng(imageBytes);
      } catch (ignoredError) {
        return null;
      }
    }
  }

  const logo = await embedOptionalImage(business.logoBytes);
  const appIcon = await embedOptionalImage(business.appIconBytes);
  const generatedParts = Object.fromEntries(new Intl.DateTimeFormat("en-GB", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
    timeZone: "Asia/Jerusalem",
  }).formatToParts(generatedAt).map((part) => [part.type, part.value]));
  const createdLabel = `${generatedParts.hour}:${generatedParts.minute} ` +
    `${generatedParts.day}-${generatedParts.month}-${generatedParts.year}`;
  const pages = [];

  function newPage() {
    const next = addInvoicePage(pdf);
    pages.push(next);
    const headerBottom = drawPageHeader(
        next, font, reservation, allocation, payload, logo,
    );
    return {page: next, y: headerBottom - 18};
  }

  let state = newPage();
  let page = state.page;
  let y = state.y;
  const cardGap = 24;
  const cardWidth = (A4.width - MARGIN * 2 - cardGap) / 2;
  const cardHeight = 116;
  const cardBottom = y - cardHeight;
  addDetailCard(page, font, "פרטי העסק", business.name, null, [
    [dealerLabel(business.dealerType), business.businessId],
    ["כתובת העסק", business.address],
    ["טלפון", business.phone],
    ["דוא״ל", business.email],
  ], MARGIN + cardWidth + cardGap, cardBottom,
  cardWidth, cardHeight, BLUE_PALE);
  addDetailCard(page, font, "פרטי לקוח", invoice.customer_name, "לכבוד", [
    ["מספר עוסק", invoice.customer_vat_number],
    ["טלפון", presentation.clientPhone],
    ["דוא״ל", presentation.clientEmail],
    ["כתובת", presentation.clientAddress],
  ], MARGIN, cardBottom, cardWidth, cardHeight, CLIENT_PALE);
  y = cardBottom - 28;

  const groups = paymentGroups(presentation);
  const ensureSpace = (needed, continuationTable = false) => {
    if (y - needed >= 88) return;
    state = newPage();
    page = state.page;
    y = state.y;
    if (continuationTable) {
      const widths = drawItemsHeader(page, font, y);
      y -= 26;
      return widths;
    }
    return null;
  };

  function drawPayments() {
    if (groups.length === 0) return;
    const firstChunkLength = Math.min(10, groups[0][1].length);
    ensureSpace(28 + 29 + 30 + firstChunkLength * 32 + 10);
    y = drawPaymentSectionTitle(page, font, y);
    for (const [method, payments] of groups) {
      for (let offset = 0; offset < payments.length; offset += 10) {
        const chunk = payments.slice(offset, offset + 10);
        const needed = 29 + 30 + chunk.length * 32 + 10;
        ensureSpace(needed);
        y = drawPaymentGroup(
            page, font, method, chunk, invoice, presentation, y,
        );
      }
    }
  }

  if (reservation.docType === "receipt") {
    drawPayments();
    y -= 8;
  } else {
    let widths = drawItemsHeader(page, font, y);
    y -= 26;
    for (const item of invoice.items) {
      const continuationWidths = ensureSpace(27, true);
      if (continuationWidths) widths = continuationWidths;
      y -= drawItemRow(page, font, item, y, widths);
    }
    y -= 18;
  }

  ensureSpace(150);
  const summary = drawSummary(
      page, font, invoice, presentation, reservation, y,
  );
  y = summary.bottom - 22;

  if (reservation.docType === "invoice_receipt") {
    y -= 18;
    drawPayments();
  }

  if (invoice.invoice_note) {
    const noteLines = wrapLogicalText(
        invoice.invoice_note, font, 9.75, A4.width - MARGIN * 2 - 20,
    );
    ensureSpace(55 + noteLines.length * 15);
    y = drawNotes(page, font, invoice.invoice_note, y);
  }

  if (["quote", "work_order"].includes(reservation.docType)) {
    ensureSpace(42);
    const lineWidth = 230;
    const center = A4.width / 2;
    page.drawLine({
      start: {x: center - lineWidth / 2, y: 91},
      end: {x: center + lineWidth / 2, y: 91},
      thickness: 0.8,
      color: MUTED,
    });
    drawRight(page, font, "חתימה:", center + lineWidth / 2 + 62, 88, 11.25, {
      color: MUTED,
    });
  }

  pages.forEach((currentPage, index) => {
    drawFooter(
        currentPage,
        font,
        index + 1,
        pages.length,
        createdLabel,
        reservation,
        appIcon,
    );
    if (previewOnly) {
      const watermark = visualText("לתצוגה מקדימה בלבד");
      const watermarkSize = 20;
      let row = 0;
      for (let y = 35; y < A4.height; y += 125) {
        const rowOffset = row % 2 === 0 ? -75 : 35;
        for (let x = rowOffset; x < A4.width; x += 220) {
          currentPage.drawText(watermark, {
            x,
            y,
            size: watermarkSize,
            font,
            color: BLUE_DARK,
            opacity: 0.075,
            rotate: degrees(28),
          });
        }
        row += 1;
      }
    }
  });

  pdf.setTitle(
      `${documentTitle(reservation.docType)} ` +
      `${reservation.documentNumber}`,
  );
  pdf.setSubject(previewOnly ?
    "Hiro document preview - not final" :
    allocation?.confirmationNumber ?
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
