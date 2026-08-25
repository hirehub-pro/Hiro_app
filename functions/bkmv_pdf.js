"use strict";

const fs = require("fs");
const path = require("path");
const fontkit = require("@pdf-lib/fontkit");
const {PDFDocument, rgb} = require("pdf-lib");

const A4 = {width: 595.28, height: 841.89};
const MARGIN = 36;
const TEXT = rgb(0.12, 0.12, 0.12);
const MUTED = rgb(0.35, 0.35, 0.35);
const LINE = rgb(0.7, 0.7, 0.7);
const HEADER = rgb(0.92, 0.92, 0.92);
const FONT_PATH = path.join(
    __dirname,
    "assets",
    "fonts",
    "Rubik-VariableFont_wght.ttf",
);

function text(value) {
  return String(value == null ? "" : value);
}

function formatCompactDate(value) {
  const digits = text(value);
  return /^\d{8}$/.test(digits) ?
    `${digits.slice(6, 8)}/${digits.slice(4, 6)}/${digits.slice(2, 4)}` : digits;
}

function formatCompactTime(value) {
  const digits = text(value);
  return /^\d{4}$/.test(digits) ? `${digits.slice(0, 2)}:${digits.slice(2)}` : digits;
}

function formatMoney(value) {
  return new Intl.NumberFormat("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  }).format(Number(value) || 0);
}

function hasHebrew(value) {
  return /[\u0590-\u05ff]/.test(text(value));
}

function textTokens(value) {
  return text(value).trim().split(/\s+/).filter(Boolean);
}

function logicalTextWidth(font, value, size) {
  const tokens = textTokens(value);
  if (!tokens.length) return 0;
  const spaceWidth = font.widthOfTextAtSize(" ", size);
  return tokens.reduce((total, token) =>
    total + font.widthOfTextAtSize(token, size), 0) +
    (spaceWidth * (tokens.length - 1));
}

function drawRtlTokens(page, font, value, right, y, size, color) {
  const tokens = textTokens(value);
  const spaceWidth = font.widthOfTextAtSize(" ", size);
  let cursor = right;
  for (const token of tokens) {
    const width = font.widthOfTextAtSize(token, size);
    page.drawText(token, {x: cursor - width, y, size, font, color});
    cursor -= width + spaceWidth;
  }
}

function drawRight(page, font, value, right, y, size = 11, options = {}) {
  const valueText = text(value);
  const color = options.color || TEXT;
  if (hasHebrew(valueText)) {
    drawRtlTokens(page, font, valueText, right, y, size, color);
    return;
  }
  const width = font.widthOfTextAtSize(valueText, size);
  page.drawText(valueText, {x: Math.max(MARGIN, right - width), y,
    size, font, color});
}

function drawLeft(page, font, value, x, y, size = 11, options = {}) {
  const valueText = text(value);
  const color = options.color || TEXT;
  if (hasHebrew(valueText)) {
    drawRtlTokens(page, font, valueText,
        x + logicalTextWidth(font, valueText, size), y, size, color);
    return;
  }
  page.drawText(valueText, {x, y, size, font, color});
}

function drawCentered(page, font, value, center, y, size = 11) {
  const valueText = text(value);
  const width = hasHebrew(valueText) ?
    logicalTextWidth(font, valueText, size) :
    font.widthOfTextAtSize(valueText, size);
  drawLeft(page, font, valueText, center - width / 2, y, size);
}

function drawDetailRow(page, font, {label, value, y}) {
  drawRight(page, font, label, A4.width - MARGIN, y, 11);
  drawLeft(page, font, value, MARGIN, y, 11);
}

function drawTableRow(page, font, {y, height, columns, values, header = false}) {
  const x = MARGIN;
  const width = A4.width - (MARGIN * 2);
  if (header) {
    page.drawRectangle({x, y: y - height, width, height, color: HEADER});
  }
  page.drawLine({start: {x, y}, end: {x: x + width, y}, thickness: 0.6, color: LINE});
  page.drawLine({
    start: {x, y: y - height},
    end: {x: x + width, y: y - height},
    thickness: 0.6,
    color: LINE,
  });
  let currentX = x;
  page.drawLine({
    start: {x: currentX, y},
    end: {x: currentX, y: y - height},
    thickness: 0.6,
    color: LINE,
  });
  for (let index = 0; index < columns.length; index += 1) {
    const columnWidth = columns[index];
    const value = text(values[index]);
    const size = header ? 8.2 : 8.5;
    const available = columnWidth - 8;
    let shown = value;
    while (shown.length > 1 && font.widthOfTextAtSize(shown, size) > available) {
      shown = shown.slice(0, -1);
    }
    if (shown !== value && shown.length > 2) shown = `${shown.slice(0, -1)}…`;
    const valueWidth = hasHebrew(shown) ?
      logicalTextWidth(font, shown, size) :
      font.widthOfTextAtSize(shown, size);
    drawLeft(page, font, shown,
        currentX + Math.max(4, (columnWidth - valueWidth) / 2),
        y - height + ((height - size) / 2) + 1, size);
    currentX += columnWidth;
    page.drawLine({
      start: {x: currentX, y},
      end: {x: currentX, y: y - height},
      thickness: 0.6,
      color: LINE,
    });
  }
}

async function createPdf(title, subject, generatedAt) {
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const font = await pdf.embedFont(fs.readFileSync(FONT_PATH), {subset: true});
  pdf.setTitle(title);
  pdf.setSubject(subject);
  pdf.setProducer("Hiro BKMV server generator");
  pdf.setCreator("Hiro");
  if (generatedAt instanceof Date && !Number.isNaN(generatedAt.getTime())) {
    pdf.setCreationDate(generatedAt);
    pdf.setModificationDate(generatedAt);
  }
  return {pdf, font};
}

async function buildPrintedSummaryPdf(summary, generatedAt = new Date()) {
  const {pdf, font} = await createPdf(
      `BKMV printed summary ${summary.businessNumber}`,
      "BKMV 1.31 printed document summary",
      generatedAt,
  );
  const page = pdf.addPage([A4.width, A4.height]);
  let y = A4.height - MARGIN - 8;
  drawDetailRow(page, font, {
    label: "מספר עוסק מורשה:", value: summary.businessNumber, y,
  });
  y -= 18;
  drawDetailRow(page, font, {
    label: "שם בית העסק:", value: summary.businessName, y,
  });
  y -= 18;
  drawDetailRow(page, font, {
    label: "טווח תאריכי הנתונים:",
    value: `${formatCompactDate(summary.fromDate)}-${formatCompactDate(summary.toDate)}`,
    y,
  });
  y -= 24;
  const columns = [155, 80, 190, 98.28];
  drawTableRow(page, font, {
    y,
    height: 28,
    columns,
    values: ["סה\"כ כספי כולל מע\"מ (1223)", "סה\"כ כמותי", "סוג המסמך", "מספר המסמך"],
    header: true,
  });
  y -= 28;
  for (const row of summary.rows || []) {
    drawTableRow(page, font, {
      y,
      height: 15,
      columns,
      values: [
        formatMoney(row.totalAmountIncludingVat),
        row.quantity,
        row.documentTypeLabel,
        row.documentTypeCode,
      ],
    });
    y -= 15;
  }
  const totalQuantity = (summary.rows || [])
      .reduce((total, row) => total + Number(row.quantity || 0), 0);
  const totalMoney = (summary.rows || [])
      .reduce((total, row) => total + Number(row.totalAmountIncludingVat || 0), 0);
  y -= 15;
  drawRight(page, font, `סה\"כ כמות: ${totalQuantity}`,
      A4.width - MARGIN, y, 9);
  y -= 14;
  drawRight(page, font, `סה\"כ כספי: ${formatMoney(totalMoney)}`,
      A4.width - MARGIN, y, 9);
  y -= 18;
  drawRight(page, font, "הנתונים הופקו באמצעות תוכנת",
      A4.width - MARGIN, y, 9);
  drawLeft(page, font, summary.softwareName, MARGIN, y, 9);
  y -= 14;
  drawRight(page, font, "מספר תעודת רישום:",
      A4.width - MARGIN, y, 9);
  drawLeft(page, font, summary.softwareRegistrationNumber, MARGIN, y, 9);
  y -= 14;
  drawRight(page, font, "תאריך הפקה:", A4.width - MARGIN, y, 9);
  drawLeft(page, font,
      `${formatCompactDate(summary.exportDate)} ${formatCompactTime(summary.exportTime)}`,
      MARGIN, y, 9);
  return Buffer.from(await pdf.save());
}

async function buildAnnex4Pdf(summary, generatedAt = new Date()) {
  const {pdf, font} = await createPdf(
      `BKMV Annex 4 ${summary.businessNumber}`,
      "BKMV 1.31 Annex 4 completion report",
      generatedAt,
  );
  const page = pdf.addPage([A4.width, A4.height]);
  let y = A4.height - 70;
  drawCentered(page, font, "הפקת קבצים במבנה אחיד", A4.width / 2, y, 20);
  y -= 45;
  drawRight(page, font, "עבור:", A4.width - MARGIN, y, 15);
  y -= 26;
  drawRight(page, font, `מספר עוסק מורשה: ${summary.businessNumber}`,
      A4.width - MARGIN, y, 14);
  y -= 24;
  drawRight(page, font, `שם בית העסק: ${summary.businessName}`,
      A4.width - MARGIN, y, 14);
  y -= 45;
  drawCentered(page, font, "** ביצוע ממשק פתוח הסתיים בהצלחה **",
      A4.width / 2, y, 15);
  y -= 38;
  drawRight(page, font, "הנתונים נשמרו בנתיב:", A4.width - MARGIN, y, 12);
  drawLeft(page, font, summary.exportDirectory, MARGIN, y, 10);
  y -= 28;
  drawRight(page, font,
      `טווח תאריכים: מתאריך ${formatCompactDate(summary.fromDate)} ועד ${formatCompactDate(summary.toDate)}`,
      A4.width - MARGIN, y, 12);
  y -= 35;
  drawRight(page, font, "פירוט סך סוגי הרשומות בקובץ BKMVDATA.TXT:",
      A4.width - MARGIN, y, 12);
  y -= 18;
  const columns = [120, 283.28, 120];
  drawTableRow(page, font, {
    y,
    height: 24,
    columns,
    values: ["סוג רשומה", "תיאור", "כמות"],
    header: true,
  });
  y -= 24;
  for (const row of summary.rows || []) {
    drawTableRow(page, font, {
      y,
      height: 22,
      columns,
      values: [row.recordCode, row.recordLabel, row.quantity],
    });
    y -= 22;
  }
  drawTableRow(page, font, {
    y,
    height: 24,
    columns,
    values: ["סה\"כ", "", summary.totalRecords],
    header: true,
  });
  y -= 55;
  page.drawLine({
    start: {x: MARGIN, y: y + 22},
    end: {x: A4.width - MARGIN, y: y + 22},
    thickness: 1.5,
    color: MUTED,
  });
  drawRight(page, font, `הנתונים הופקו באמצעות תוכנת ${summary.softwareName}`,
      A4.width - MARGIN, y, 11);
  y -= 20;
  drawRight(page, font,
      `מספר תעודת רישום: ${summary.softwareRegistrationNumber}`,
      A4.width - MARGIN, y, 11);
  y -= 20;
  drawRight(page, font,
      `תאריך הפקה: ${formatCompactDate(summary.exportDate)} ${formatCompactTime(summary.exportTime)}`,
      A4.width - MARGIN, y, 11);
  return Buffer.from(await pdf.save());
}

module.exports = {
  buildAnnex4Pdf,
  buildPrintedSummaryPdf,
  formatCompactDate,
  formatCompactTime,
  formatMoney,
};
