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
// Packaged fonts never change during an instance's lifetime. Reading once at
// cold start avoids a synchronous filesystem read for every generated PDF.
const FONT_BYTES = fs.readFileSync(FONT_PATH);

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

function normalizedIsoDate(value) {
  const result = boundedString(value, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(result)) return null;
  const date = new Date(`${result}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) &&
    date.toISOString().slice(0, 10) === result ? result : null;
}

function normalizePaymentMethods(value) {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 20).map((entry) => {
    const data = entry && typeof entry === "object" ? entry : {};
    const installmentDates = Array.isArray(data.installmentDates) ?
      data.installmentDates.slice(0, 999)
          .map(normalizedIsoDate)
          .filter(Boolean) : [];
    return {
      method: boundedString(data.method, 24, "cash"),
      amount: Math.max(0, money(data.amount)),
      cardNumber: boundedOptionalString(data.cardNumber, 32),
      cardName: boundedOptionalString(data.cardName, 80),
      cardExpiration: boundedOptionalString(data.cardExpiration, 12),
      installments: boundedOptionalString(data.installments, 8),
      dealType: ["regular", "installments", "credit", "deferred", "other"]
          .includes(boundedString(data.dealType, 20)) ?
        data.dealType : "regular",
      checkNumber: boundedOptionalString(data.checkNumber, 32),
      bank: boundedOptionalString(data.bank, 80),
      branch: boundedOptionalString(data.branch, 32),
      account: boundedOptionalString(data.account, 40),
      paymentDate: normalizedIsoDate(data.paymentDate),
      installmentDates,
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
    priceTaxModeDefault: ["before_tax", "after_tax", "vat_exempt"].includes(
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
  const text = boundedString(value, 4000);
  if (direction !== "rtl" || !/[\u0590-\u08ff]/u.test(text)) return text;
  // Fontkit reverses an RTL glyph run as a whole, including embedded LTR text.
  // Reverse only the Latin/number runs before encoding so Fontkit's layout
  // restores their visual order while still positioning them within Hebrew.
  return text.replace(
      /[A-Za-z0-9@._:/,+%#()$€£₪-]+/g,
      (run) => [...run].reverse().join(""),
  );
}

function formatMoney(value) {
  return `${new Intl.NumberFormat("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
    useGrouping: true,
  }).format(money(value))} \u20aa`;
}

function formatVatRate(value) {
  return new Intl.NumberFormat("en-US", {
    maximumFractionDigits: 2,
    useGrouping: false,
  }).format(safeNumber(value));
}

function taxableSubtotalBeforeTax(invoice) {
  const items = Array.isArray(invoice?.items) ? invoice.items : [];
  return money(items.reduce((total, item) => {
    return Number(item.vat_rate) > 0 ?
      total + safeNumber(item.total_amount) : total;
  }, 0));
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
    credit_note: "חשבונית מס זיכוי",
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
  const splitWord = (word) => {
    const parts = [];
    let part = "";
    for (const character of [...word]) {
      const candidate = `${part}${character}`;
      if (part && font.widthOfTextAtSize(
          visualText(candidate, direction), size,
      ) > maxWidth) {
        parts.push(part);
        part = character;
      } else {
        part = candidate;
      }
    }
    if (part) parts.push(part);
    return parts;
  };
  const fittedWords = words.flatMap((word) =>
    font.widthOfTextAtSize(visualText(word, direction), size) <= maxWidth ?
      [word] : splitWord(word),
  );
  for (const word of fittedWords) {
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

function fittedTextSize(font, value, maxWidth, preferredSize,
    minimumSize = 5.5) {
  const text = visualText(value, "ltr");
  const textWidth = font.widthOfTextAtSize(text, preferredSize);
  if (textWidth <= maxWidth) return preferredSize;
  return Math.max(minimumSize, preferredSize * maxWidth / textWidth);
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
  const addressWithPostalCode = splitTrailingPostalCode(safeValue);
  if (addressWithPostalCode) {
    const postalCodeWidth = font.widthOfTextAtSize(
        addressWithPostalCode.postalCode,
        11.25,
    );
    const addressLines = wrapLogicalText(
        addressWithPostalCode.address,
        font,
        11.25,
        Math.max(60, width - labelWidth - postalCodeWidth - 12),
    );
    const addressWidth = drawRight(
        page,
        font,
        addressLines[0] || "—",
        valueRight,
        y,
        11.25,
    );
    drawLeft(
        page,
        font,
        addressWithPostalCode.postalCode,
        Math.max(MARGIN, valueRight - addressWidth - postalCodeWidth - 6),
        y,
        11.25,
        {direction: "ltr"},
    );
    return;
  }
  const lines = wrapLogicalText(safeValue, font, 11.25,
      Math.max(60, width - labelWidth - 6));
  drawRight(page, font, lines[0] || "—", valueRight, y, 11.25);
}

function splitTrailingPostalCode(value) {
  const match = boundedString(value, 500).match(
      /^(.+?)[,\s]+(\d{4,8})$/u,
  );
  if (!match) return null;
  return {
    address: match[1].trim(),
    postalCode: match[2],
  };
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

function footerGeneratedAtText(generatedAt, previewOnly) {
  return previewOnly ? null : generatedAt;
}

function footerSignatureText(previewOnly, digitallySigned) {
  if (previewOnly) {
    return {
      title: "טיוטה – לתצוגה מקדימה בלבד",
      helper: "יש לשמור את המסמך כדי להפיק מסמך תקף",
    };
  }
  if (digitallySigned) {
    return {
      title: "חתימה דיגיטלית מאובטחת",
      helper: "מסמך ממוחשב נחתם דיגיטלית על ידי העסק המפיק",
    };
  }
  return {
    title: "מסמך הופק באופן ממוחשב",
    helper: "הופק על ידי הירו",
  };
}

function drawFooter(page, font, pageNumber, pageCount, generatedAt,
    reservation, appIcon, businessSignature, previewOnly, digitallySigned) {
  page.drawLine({
    start: {x: MARGIN, y: 59},
    end: {x: A4.width - MARGIN, y: 59},
    thickness: 0.8,
    color: rgb(38 / 255, 50 / 255, 56 / 255),
  });
  const footerText = footerSignatureText(previewOnly, digitallySigned);
  drawRight(page, font, footerText.title,
      A4.width - MARGIN, 37, 15.75, {color: TEXT});
  const signatureRight = A4.width - MARGIN;
  const signatureHelperWidth = drawRight(
      page, font, footerText.helper, signatureRight, 20, 8.25, {color: MUTED},
  );
  if (appIcon && !previewOnly) {
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
  const footerGeneratedAt = footerGeneratedAtText(generatedAt, previewOnly);
  if (footerGeneratedAt) {
    footerX += 4;
    footerX += drawLeft(page, font, "|", footerX, 36, 8.25, {
      color: MUTED,
      direction: "ltr",
    });
    footerX += 4;
    footerX += drawLeft(page, font, footerGeneratedAt, footerX, 36, 8.25, {
      color: MUTED,
      direction: "ltr",
    });
    footerX += 4;
    drawLeft(page, font, "הופק ב", footerX, 36, 8.25, {color: MUTED});
  }
  drawLeft(page, font, `${pageNumber} / ${pageCount}`, MARGIN, 17, 9.75, {
    color: MUTED_LIGHT,
  });

  if (businessSignature) {
    const signatureRight = A4.width - MARGIN;
    const signatureLineWidth = 190;
    const signatureLineY = 91;
    const signatureLabel = "חתימת העסק:";
    const signatureLabelSize = 11.25;
    const signatureLabelWidth = font.widthOfTextAtSize(
        visualText(signatureLabel), signatureLabelSize,
    );
    const signatureLineRight = signatureRight - signatureLabelWidth - 8;
    page.drawLine({
      start: {x: signatureLineRight - signatureLineWidth, y: signatureLineY},
      end: {x: signatureLineRight, y: signatureLineY},
      thickness: 0.8,
      color: MUTED,
    });
    drawRight(
        page,
        font,
        signatureLabel,
        signatureRight,
        signatureLineY - 4,
        signatureLabelSize,
        {color: MUTED},
    );
    const scale = Math.min(
        signatureLineWidth / businessSignature.width,
        62 / businessSignature.height,
    );
    const width = businessSignature.width * scale;
    const height = businessSignature.height * scale;
    page.drawImage(businessSignature, {
      x: signatureLineRight - width,
      y: signatureLineY + 6,
      width,
      height,
    });
  }
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
  // Coordinates run left-to-right, while the invoice table is read from the
  // right. Keep the description widest and the quantity deliberately narrow.
  const widths = [98.12, 98.12, 44, 270];
  page.drawRectangle({
    x, y: y - 23, width: widths.reduce((a, b) => a + b, 0),
    height: 25, color: BLUE,
  });
  const labels = ["סה״כ", "מחיר ליח׳", "כמות", "תיאור השירות/מוצר"];
  let cursor = x;
  labels.forEach((label, index) => {
    drawRight(page, font, label, cursor + widths[index] - 7, y - 16, 12, {
      color: WHITE,
    });
    cursor += widths[index];
  });
  return widths;
}

function itemRowLayout(font, item, widths) {
  const descriptionWidth = widths.at(-1) - 14;
  const descriptionLines = wrapLogicalText(
      boundedString(item.description, 120, "פריט"),
      font,
      11.25,
      descriptionWidth,
  );
  return {
    descriptionLines,
    height: Math.max(24, 12 + descriptionLines.length * 14),
  };
}

function drawItemRow(page, font, item, y, widths, layout) {
  const x = MARGIN;
  const rowHeight = layout.height;
  page.drawRectangle({
    x,
    y: y - rowHeight + 5,
    width: widths.reduce((a, b) => a + b, 0),
    height: rowHeight,
    borderColor: LINE,
    borderWidth: 0.5,
  });
  const values = [
    formatMoney(item.total_amount),
    formatMoney(item.price_per_unit),
    money(item.quantity).toLocaleString("en-US"),
  ];
  let cursor = x;
  values.forEach((value, index) => {
    const size = fittedTextSize(font, value, widths[index] - 14, 11.25);
    drawRight(page, font, value, cursor + widths[index] - 7, y - 14, size, {
      direction: "ltr",
    });
    cursor += widths[index];
  });
  const descriptionRight = x + widths.reduce((a, b) => a + b, 0) - 7;
  layout.descriptionLines.forEach((line, index) => {
    drawRight(
        page, font, line, descriptionRight, y - 14 - index * 14, 11.25,
        {direction: "rtl"},
    );
  });
  return rowHeight;
}

function drawSummary(page, font, invoice, presentation, reservation, y) {
  const width = 260;
  const x = MARGIN;
  const beforeRounding = money(invoice.payment_amount_including_vat);
  const rounding = presentation.roundTotalEnabled ? money(beforeRounding - Math.floor(beforeRounding)) : 0;
  const finalTotal = money(beforeRounding - rounding);
  const hasVat = invoice.items.some((item) => Number(item.vat_rate) > 0);
  const hasVatExempt = invoice.items.some(
      (item) => item.priceTaxMode === "vat_exempt",
  );
  const vatRate = hasVat ? Number(invoice.items.find(
      (item) => Number(item.vat_rate) > 0,
  ).vat_rate) : 0;
  const negative = presentation.isNegativeReceipt === true;
  const sign = (value) => negative ? -Math.abs(value) : value;
  const rows = hasVat || hasVatExempt ? [[
    "סה״כ לפני מע״מ",
    formatMoney(sign(invoice.amount_before_discount)),
  ]] : invoice.discount > 0 ? [[
    "סה״כ לפני הנחה",
    formatMoney(sign(invoice.amount_before_discount)),
  ]] : [];
  if (hasVatExempt) {
    rows.push([
      "סה״כ חייב במע״מ",
      formatMoney(sign(taxableSubtotalBeforeTax(invoice))),
    ]);
  }
  if (invoice.discount > 0) {
    rows.push(["הנחה", `-${formatMoney(invoice.discount)}`]);
  }
  if (hasVat) {
    rows.push(["מע״מ", formatMoney(sign(invoice.vat_amount))]);
  }
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
    const preferredSize = isLast ? 15 : 11.25;
    const labelWidth = drawRight(page, font, label, x + width - 14, rowY,
        preferredSize, {
      color: isLast ? BLUE_DARK : TEXT,
    });
    let vatRateWidth = 0;
    if (hasVat && label === "מע״מ") {
      const vatRateText = `${formatVatRate(vatRate)}%`;
      vatRateWidth = font.widthOfTextAtSize(vatRateText, 11.25);
      drawRight(
          page,
          font,
          vatRateText,
          x + width - 18 - labelWidth,
          rowY,
          11.25,
          {color: TEXT, direction: "ltr"},
      );
    }
    const valueMaxWidth = Math.max(
        40,
        width - 36 - labelWidth - vatRateWidth,
    );
    const valueSize = fittedTextSize(
        font,
        value,
        valueMaxWidth,
        preferredSize,
    );
    drawLeft(page, font, value, x + 14, rowY, valueSize, {
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

function creditCompanyLabel(company) {
  return {
    Diners: "דיינרס",
    CAL: "כאל",
    "Leumi Card": "לאומי קארד",
    "American Express": "אמריקן אקספרס",
    Isracard: "ישראכרט",
  }[boundedString(company, 80)] || boundedString(company, 80) || "-";
}

function creditDealTypeLabel(dealType) {
  return {
    regular: "רגיל",
    installments: "תשלומים",
    credit: "קרדיט",
    deferred: "חיוב נדחה",
    other: "אחר",
  }[boundedString(dealType, 20)] || "רגיל";
}

function paymentColumns(method) {
  const columns = ["תאריך"];
  if (["transfer", "check"].includes(method)) {
    columns.push("שם הבנק", "סניף", "מספר חשבון");
  }
  if (method === "check") columns.push("מספר צ׳ק");
  if (method === "credit") {
    columns.push("סוג כרטיס", "מספר כרטיס", "תוקף", "סוג העסקה", "מספר תשלום");
  } else {
    columns.push("סוג העסקה");
  }
  columns.push("סכום");
  return columns;
}

function paymentRow(method, payment, date, negative) {
  const value = (raw) => boundedString(raw, 80) || "-";
  const row = [
    formatDate(date),
  ];
  if (["transfer", "check"].includes(method)) {
    row.push(value(payment.bank), value(payment.branch), value(payment.account));
  }
  if (method === "check") row.push(value(payment.checkNumber));
  if (method === "credit") {
    row.push(
        creditCompanyLabel(payment.cardName),
        value(payment.cardNumber),
        value(payment.cardExpiration),
        creditDealTypeLabel(payment.dealType),
        value(payment.installmentLabel || payment.installments || "1"),
    );
  } else {
    row.push("-");
  }
  row.push(formatMoney(negative ? -Math.abs(payment.amount) : payment.amount));
  return row;
}

function splitInstallmentAmount(value, count) {
  const totalMinorUnits = Math.round(
      (safeNumber(value) + Number.EPSILON) * 100,
  );
  const base = Math.floor(totalMinorUnits / count);
  const remainder = totalMinorUnits % count;
  return Array.from({length: count}, (_, index) =>
    (base + (index < remainder ? 1 : 0)) / 100);
}

function expandPaymentInstallments(payment) {
  if (payment.method !== "credit") return [payment];
  if (payment.dealType === "credit") return [payment];
  const count = Number.parseInt(String(payment.installments || "1"), 10);
  const dates = Array.isArray(payment.installmentDates) ?
    payment.installmentDates : [];
  if (!Number.isInteger(count) || count <= 1 || count > 999 ||
      dates.length !== count) {
    return [payment];
  }
  const amounts = splitInstallmentAmount(payment.amount, count);
  return dates.map((paymentDate, index) => ({
    ...payment,
    amount: amounts[index],
    paymentDate,
    installmentLabel: `${index + 1}/${count}`,
  }));
}

function paymentGroups(presentation) {
  const groups = new Map();
  for (const payment of presentation.paymentMethods) {
    if (!groups.has(payment.method)) groups.set(payment.method, []);
    groups.get(payment.method).push(...expandPaymentInstallments(payment));
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
        payment.paymentDate || invoice.invoice_date,
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
      const size = fittedTextSize(font, value, columnWidth - 10, 9);
      drawRight(page, font, value, right, top - 20, size, {
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
  digitallySigned = false,
}) {
  const invoice = payload.invoices_list[0];
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const font = await pdf.embedFont(FONT_BYTES, {subset: true});

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
  const businessSignature = await embedOptionalImage(business.signatureBytes);
  const appIcon = previewOnly ? null :
    await embedOptionalImage(business.appIconBytes);
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
    const isFirstPage = pages.length === 0;
    const next = addInvoicePage(pdf);
    pages.push(next);
    if (!isFirstPage) {
      return {page: next, y: A4.height - MARGIN - 4};
    }
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
    ["מס' עוסק / ת.ז / ח.פ", invoice.customer_vat_number],
    ["כתובת", presentation.clientAddress],
    ["טלפון", presentation.clientPhone],
    ["דוא״ל", presentation.clientEmail],
  ], MARGIN, cardBottom, cardWidth, cardHeight, CLIENT_PALE);
  y = cardBottom - 28;

  const groups = paymentGroups(presentation);
  const hasClientSignatureLine =
    ["quote", "work_order"].includes(reservation.docType);
  const minimumContentY = Math.max(
      businessSignature ? 142 : 88,
      hasClientSignatureLine ? 170 : 88,
  );
  const ensureSpace = (needed, continuationTable = false) => {
    if (y - needed >= minimumContentY) return;
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
      let layout = itemRowLayout(font, item, widths);
      const continuationWidths = ensureSpace(layout.height + 3, true);
      if (continuationWidths) widths = continuationWidths;
      if (continuationWidths) layout = itemRowLayout(font, item, widths);
      y -= drawItemRow(page, font, item, y, widths, layout);
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

  if (hasClientSignatureLine) {
    ensureSpace(42);
    const lineWidth = 190;
    const lineStart = MARGIN;
    page.drawLine({
      start: {x: lineStart, y: 91},
      end: {x: lineStart + lineWidth, y: 91},
      thickness: 0.8,
      color: MUTED,
    });
    drawRight(page, font, "חתימת הלקוח:", lineStart + lineWidth, 72, 11.25, {
      color: MUTED,
    });
  }

  pages.forEach((currentPage, index) => {
    const finalPageBusinessSignature = index === pages.length - 1 ?
      businessSignature : null;
    drawFooter(
        currentPage,
        font,
        index + 1,
        pages.length,
        createdLabel,
        reservation,
        appIcon,
        finalPageBusinessSignature,
        previewOnly,
        digitallySigned,
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
  creditCompanyLabel,
  creditDealTypeLabel,
  expandPaymentInstallments,
  footerGeneratedAtText,
  footerSignatureText,
  fittedTextSize,
  formatMoney,
  normalizeTaxInvoicePresentation,
  paymentColumns,
  splitTrailingPostalCode,
  taxableSubtotalBeforeTax,
  validateTaxInvoicePresentation,
  visualText,
};
