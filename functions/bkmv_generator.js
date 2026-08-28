"use strict";

const crypto = require("crypto");
const iconv = require("iconv-lite");

const BKMV_VERSION = "&OF1.31&";
const BKMV_TIME_ZONE = "Asia/Jerusalem";
const RECORD_LENGTHS = Object.freeze({
  A100: 95,
  B110: 376,
  C100: 444,
  D110: 339,
  D120: 222,
  Z900: 110,
});
const BUCKET_NAMES = Object.freeze([
  "invoices",
  "invoice_tax_receipt",
  "transaction_account",
  "receipts",
  "credit_notes",
]);
const ANNEX4_ROWS = Object.freeze([
  ["A100", "רשומת פתיחה"],
  ["B110", "חשבון בהנהלת חשבונות"],
  ["C100", "כותרת מסמך"],
  ["D110", "פרטי מסמך"],
  ["D120", "פרטי קבלה"],
  ["Z900", "רשומת סגירה"],
]);
const PRINTED_SUMMARY_ROWS = Object.freeze([
  [100, "הזמנה"],
  [200, "תעודת משלוח"],
  [205, "תעודת משלוח סוכן"],
  [210, "תעודת החזרה"],
  [300, "חשבונית/חשבונית עסקה"],
  [305, "חשבונית-מס"],
  [310, "חשבונית ריכוז"],
  [320, "חשבונית מס / קבלה"],
  [330, "חשבונית מס זיכוי"],
  [340, "חשבונית שריון"],
  [345, "חשבונית סוכן"],
  [400, "קבלה"],
  [405, "קבלה על תרומות"],
  [410, "יציאה מקופה"],
  [420, "הפקדת בנק"],
  [500, "הזמנת רכש"],
  [600, "תעודת משלוח רכש"],
  [610, "החזרת רכש"],
  [700, "חשבונית מס רכש"],
  [710, "זיכוי רכש"],
  [800, "יתרת פתיחה"],
  [810, "כניסה כללית למלאי"],
  [820, "יציאה כללית מהמלאי"],
  [830, "העברה בין מחסנים"],
  [840, "עדכון בעקבות ספירה"],
  [900, "דוח ייצור-כניסה"],
  [910, "דוח ייצור-יציאה"],
]);

function digitsOnly(value) {
  return String(value == null ? "" : value).replace(/[^0-9]/g, "");
}

function finiteNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function money(value) {
  return Math.round((finiteNumber(value) + Number.EPSILON) * 100) / 100;
}

function isValidIsraeliId(value) {
  const digits = String(value == null ? "" : value).trim();
  if (!/^\d{9}$/.test(digits)) return false;
  let sum = 0;
  for (let index = 0; index < digits.length; index += 1) {
    let product = Number(digits[index]) * ((index % 2) + 1);
    if (product > 9) product -= 9;
    sum += product;
  }
  return sum % 10 === 0;
}

function sanitizeIso88598Text(value) {
  let result = "";
  for (const character of String(value == null ? "" : value)) {
    const rune = character.codePointAt(0);
    if (rune <= 0x7f || rune === 0x00a0 || rune === 0x00a2 ||
        rune === 0x00a3 || rune === 0x00a4 || rune === 0x00a5 ||
        rune === 0x00a6 || rune === 0x00a7 || rune === 0x00a8 ||
        rune === 0x00a9 || rune === 0x00ab || rune === 0x00ac ||
        rune === 0x00ad || rune === 0x00ae || rune === 0x00af ||
        rune === 0x00b0 || rune === 0x00b1 || rune === 0x00b2 ||
        rune === 0x00b3 || rune === 0x00b4 || rune === 0x00b5 ||
        rune === 0x00b6 || rune === 0x00b7 || rune === 0x00b8 ||
        rune === 0x00b9 || rune === 0x00bb || rune === 0x00bc ||
        rune === 0x00bd || rune === 0x00be ||
        (rune >= 0x05d0 && rune <= 0x05ea)) {
      result += character;
    } else if (rune === 0x20aa) {
      result += "\u00a4";
    } else if ([0x05be, 0x2010, 0x2013, 0x2014].includes(rune)) {
      result += "-";
    } else if ([0x05f3, 0x2018, 0x2019].includes(rune)) {
      result += "'";
    } else if ([0x05f4, 0x201c, 0x201d].includes(rune)) {
      result += "\"";
    } else {
      result += "?";
    }
  }
  return result;
}

function encodeIso88598(value) {
  const sanitized = sanitizeIso88598Text(value);
  const encoded = iconv.encode(sanitized, "ISO-8859-8");
  if (encoded.length !== [...sanitized].length) {
    throw new Error("ISO-8859-8 encoding changed the fixed-width byte length.");
  }
  return encoded;
}

function fitAlpha(value, length) {
  if (length === 0) return "";
  const normalized = sanitizeIso88598Text(String(value == null ? "" : value)
      .replace(/\r\n|\n|\r/g, " ")
      .replace(/\s+/g, " ")
      .trim());
  const characters = [...normalized];
  if (characters.length >= length) return characters.slice(0, length).join("");
  return normalized.padEnd(length, " ");
}

function fitNumeric(value, length) {
  if (length === 0) return "";
  const digits = digitsOnly(value);
  if (!digits) return "".padStart(length, "0");
  if (digits.length >= length) return digits.slice(-length);
  return digits.padStart(length, "0");
}

function fitSignedAmount(value, wholeDigits, decimalDigits) {
  const factor = 10 ** decimalDigits;
  const numeric = finiteNumber(value);
  const scaled = Math.round((Math.abs(numeric) + Number.EPSILON) * factor)
      .toString();
  const digitLength = wholeDigits + decimalDigits;
  const padded = scaled.padStart(digitLength, "0").slice(-digitLength);
  return `${numeric < 0 ? "-" : "+"}${padded}`;
}

function joinFixed(parts, length, recordCode) {
  const line = parts.join("");
  if ([...line].length !== length) {
    throw new Error(
        `Invalid ${recordCode} length: expected ${length}, got ${[...line].length}.`,
    );
  }
  if (encodeIso88598(line).length !== length) {
    throw new Error(`Invalid ${recordCode} ISO-8859-8 byte length.`);
  }
  return line;
}

function normalizeCompactDate(value, label = "date") {
  const digits = digitsOnly(value);
  if (digits.length !== 8) {
    throw new Error(`${label} must contain exactly 8 digits in YYYYMMDD format.`);
  }
  const year = Number(digits.slice(0, 4));
  const month = Number(digits.slice(4, 6));
  const day = Number(digits.slice(6, 8));
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (parsed.getUTCFullYear() !== year || parsed.getUTCMonth() !== month - 1 ||
      parsed.getUTCDate() !== day) {
    throw new Error(`${label} is not a valid calendar date.`);
  }
  return digits;
}

function dateParts(value, timeZone = BKMV_TIME_ZONE) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) throw new Error("Invalid export timestamp.");
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date);
  return Object.fromEntries(parts.map((part) => [part.type, part.value]));
}

function formatCompactDate(value, timeZone = BKMV_TIME_ZONE) {
  const parts = dateParts(value, timeZone);
  return `${parts.year}${parts.month}${parts.day}`;
}

function formatTime(value, timeZone = BKMV_TIME_ZONE) {
  const parts = dateParts(value, timeZone);
  return `${parts.hour}${parts.minute}`;
}

function timestampToMillis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value && typeof value.toDate === "function") return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function timestampToTime(value) {
  const millis = timestampToMillis(value);
  return millis == null ? "0000" : formatTime(new Date(millis));
}

function randomDigits(length) {
  let result = "";
  for (let index = 0; index < length; index += 1) {
    result += crypto.randomInt(0, 10).toString();
  }
  return result;
}

function splitAddress(value) {
  const parts = String(value == null ? "" : value).split(",")
      .map((part) => part.trim()).filter(Boolean);
  const street = parts[0] || "";
  const city = parts[1] || "";
  const postalCode = parts.length > 2 ? digitsOnly(parts[2]) : "";
  const houseMatch = street.match(/(\d+[A-Za-z]?)/);
  const houseNumber = houseMatch ? houseMatch[1] : "";
  const cleanStreet = houseNumber ? street.replace(houseNumber, "").trim() : street;
  return {
    street: cleanStreet || street,
    houseNumber,
    city,
    postalCode,
  };
}

function normalizeIsraeliPhone(value) {
  const digits = digitsOnly(value);
  if (!digits) return "";
  if (digits.startsWith("972") && digits.length >= 11) {
    const local = digits.slice(3);
    return local.startsWith("0") ? local.slice(0, 10) : `0${local.slice(0, 9)}`;
  }
  if (digits.startsWith("0")) return digits.slice(0, 10);
  if (digits.length === 9 && digits.startsWith("5")) return `0${digits}`;
  return digits.slice(0, 10);
}

function mapDocumentType(value) {
  return {
    transaction_account: 300,
    invoice: 305,
    invoice_receipt: 320,
    credit_note: 330,
    receipt: 400,
  }[String(value || "").trim()] || null;
}

function mapCreditDealType(value) {
  return {installments: 2, credit: 3, other: 4}[value] || 1;
}

function mapCreditCompanyCode(value) {
  const name = String(value || "").trim().toLowerCase();
  if (["isracard", "ישראכרט"].includes(name)) return 1;
  if (["cal", "כאל"].includes(name)) return 2;
  if (["diners", "דיינרס"].includes(name)) return 3;
  if (["american express", "amex", "אמריקן אקספרס"].includes(name)) return 4;
  if (["leumi card", "max", "לאומי קארד", "מקס"].includes(name)) return 6;
  return null;
}

function installmentCount(value) {
  const parsed = Number.parseInt(String(value == null ? "" : value).trim(), 10);
  const count = Number.isFinite(parsed) ? parsed : 1;
  if (count < 1 || count > 999) {
    throw new Error("Credit-card installments must be from 1 through 999.");
  }
  return count;
}

function splitPaymentAmount(value, count) {
  const totalMinorUnits = Math.round((finiteNumber(value) + Number.EPSILON) * 100);
  const sign = totalMinorUnits < 0 ? -1 : 1;
  const absolute = Math.abs(totalMinorUnits);
  const base = Math.floor(absolute / count);
  const remainder = absolute % count;
  return Array.from({length: count}, (_, index) =>
    sign * (base + (index < remainder ? 1 : 0)) / 100);
}

function extractTransferPart(value, index) {
  const groups = String(value || "").match(/\d+/g) || [];
  return groups[index] || "";
}

function extractTransferDate(value) {
  const digits = digitsOnly(value);
  return digits.length === 8 ? normalizeCompactDate(digits, "paymentDate") : "";
}

function paymentDetailsFromEntry(entry, defaultAmount) {
  const method = String(entry.method || "cash");
  const amount = finiteNumber(entry.amount, defaultAmount);
  if (method === "credit") {
    const installments = installmentCount(entry.installments);
    const installmentDates = Array.isArray(entry.installmentDates) ?
      entry.installmentDates : [];
    if (installments > 1 && installmentDates.length !== installments) {
      return [{
        typeCode: 3,
        amount,
        paymentDate: String(entry.paymentDate || ""),
        creditCompanyCode: mapCreditCompanyCode(entry.cardName),
        cardName: String(entry.cardName || "CREDIT"),
        creditDealType: 2,
      }];
    }
    return splitPaymentAmount(amount, installments).map((installmentAmount,
        index) => ({
      typeCode: 3,
      amount: installmentAmount,
      paymentDate: String(installmentDates[index] || entry.paymentDate || ""),
      creditCompanyCode: mapCreditCompanyCode(entry.cardName),
      cardName: String(entry.cardName || "CREDIT"),
      creditDealType: installments > 1 ? 2 : mapCreditDealType(entry.dealType),
    }));
  }
  if (method === "transfer") return [{typeCode: 4, amount}];
  if (method === "check") {
    return [{
      typeCode: 2,
      amount,
      bankNumber: String(entry.bank || ""),
      branchNumber: String(entry.branch || ""),
      accountNumber: String(entry.account || ""),
      chequeNumber: String(entry.checkNumber || ""),
      paymentDate: String(entry.paymentDate || ""),
    }];
  }
  if (["bit", "paybox", "other"].includes(method)) {
    return [{typeCode: 9, amount}];
  }
  if (method === "cash") return [{typeCode: 1, amount}];
  return [{typeCode: 9, amount}];
}

function paymentDetailsFromLegacy(methodValue, invoiceData, defaultAmount) {
  const method = String(methodValue || "cash");
  const checkNumber = String(invoiceData.checkNumber || "");
  if (method === "credit") {
    return {
      typeCode: 3,
      amount: defaultAmount,
      creditCompanyCode: mapCreditCompanyCode(invoiceData.cardName),
      cardName: String(invoiceData.cardName || "CREDIT"),
      creditDealType: 1,
    };
  }
  if (method === "transfer") return {typeCode: 4, amount: defaultAmount};
  if (method === "check") {
    return {
      typeCode: 2,
      amount: defaultAmount,
      bankNumber: extractTransferPart(checkNumber, 0),
      branchNumber: extractTransferPart(checkNumber, 1),
      accountNumber: "",
      chequeNumber: digitsOnly(checkNumber),
      paymentDate: extractTransferDate(checkNumber),
    };
  }
  if (["bit", "paybox", "other"].includes(method)) {
    return {typeCode: 9, amount: defaultAmount};
  }
  return {typeCode: method === "cash" ? 1 : 9, amount: defaultAmount};
}

function mapPaymentDetails({logData, invoiceData, defaultAmount}) {
  const rawMethods = logData.paymentMethods || invoiceData.paymentMethods;
  if (Array.isArray(rawMethods)) {
    const details = [];
    let withholdingAmount = 0;
    let foundMethod = false;
    for (const rawEntry of rawMethods) {
      if (!rawEntry || typeof rawEntry !== "object" || Array.isArray(rawEntry)) {
        continue;
      }
      foundMethod = true;
      if (String(rawEntry.method || "") === "withholding_tax") {
        withholdingAmount += Math.abs(finiteNumber(rawEntry.amount, defaultAmount));
      } else {
        details.push(...paymentDetailsFromEntry(rawEntry, defaultAmount));
      }
    }
    if (foundMethod) return {details, withholdingAmount: money(withholdingAmount)};
  }
  const legacyMethod = invoiceData.paymentMethod || logData.paymentMethod || "cash";
  if (legacyMethod === "withholding_tax") {
    return {details: [], withholdingAmount: Math.abs(defaultAmount)};
  }
  return {
    details: [paymentDetailsFromLegacy(legacyMethod, invoiceData, defaultAmount)],
    withholdingAmount: 0,
  };
}

function originalCreditNumber(invoiceData) {
  const legal = invoiceData.creditNoteLegal;
  const number = legal && typeof legal === "object" ?
    String(legal.originalInvoiceNumber || "").trim() : "";
  return number || null;
}

function creditBaseDocumentType(invoiceData) {
  const originalNumber = originalCreditNumber(invoiceData);
  const sourceDocumentId = String(invoiceData.sourceInvoiceDocId ||
    invoiceData.cancellationSourceDocumentId || "").trim();
  const linkedDocuments = Array.isArray(invoiceData.linkedDocuments) ?
    invoiceData.linkedDocuments : [];
  let fallback = null;
  for (const linked of linkedDocuments) {
    if (!linked || typeof linked !== "object") continue;
    const mappedType = mapDocumentType(linked.docType || linked.type);
    if (![305, 320].includes(mappedType)) continue;
    fallback ||= linked;
    const linkedNumber = String(linked.documentNumber ||
      linked.invoiceNumber || "").trim();
    const linkedId = String(linked.invoiceDocId || linked.id || "").trim();
    if ((originalNumber && linkedNumber === originalNumber) ||
        (sourceDocumentId && linkedId === sourceDocumentId)) return mappedType;
  }
  return fallback ? mapDocumentType(fallback.docType || fallback.type) : null;
}

function extractItems(logData, invoiceData, subtotal, vatAmount) {
  const rawItems = logData.items || invoiceData.items;
  if (Array.isArray(rawItems)) {
    const items = rawItems.filter((item) => item && typeof item === "object")
        .map((item) => {
          const quantity = finiteNumber(item.quantity, 1);
          const unitPrice = finiteNumber(item.unitPriceWithoutTax ??
            item.price_per_unit ?? item.unitPrice ?? item.price);
          return {
            description: String(item.description || "Item"),
            quantity,
            unitPrice,
            discountAmount: 0,
            lineTotal: money(quantity * unitPrice),
          };
        }).filter((item) => item.quantity > 0);
    if (items.length) return items;
  }
  const fallbackSubtotal = vatAmount > 0 ? subtotal :
    Math.abs(finiteNumber(invoiceData.amount));
  return [{
    description: "General item",
    quantity: 1,
    unitPrice: fallbackSubtotal,
    discountAmount: 0,
    lineTotal: fallbackSubtotal,
  }];
}

function sumBeforeTaxAmount(logData, invoiceData) {
  const rawItems = logData.items || invoiceData.items;
  if (Array.isArray(rawItems)) {
    return rawItems.filter((item) => item && typeof item === "object")
        .reduce((total, item) => total +
          finiteNumber(item.quantity, 1) * finiteNumber(
              item.unitPriceWithoutTax ?? item.price_per_unit ??
              item.unitPrice ?? item.price,
          ), 0);
  }
  return finiteNumber(logData.subtotalBeforeTax ??
    invoiceData.subtotalBeforeTax ?? invoiceData.paymentAmount ??
    invoiceData.amount);
}

function amountExcludingWithholding(amount, withholdingAmount) {
  return amount < 0 ? amount + withholdingAmount : amount - withholdingAmount;
}

function buildA000({totalRecords, context, mainId, logicalExportPath,
  fromDate, toDate, exportDate, exportTime}) {
  return joinFixed([
    fitAlpha("A000", 4), fitAlpha("", 5), fitNumeric(totalRecords, 15),
    fitNumeric(context.businessNumber, 9), fitNumeric(mainId, 15),
    fitAlpha(BKMV_VERSION, 8),
    fitNumeric(context.softwareRegistrationNumber, 8),
    fitAlpha(context.softwareName, 20), fitAlpha(context.softwareVersion, 20),
    fitNumeric(context.softwareMakerVatNumber, 9),
    fitAlpha(context.softwareMakerName, 20), fitNumeric("2", 1),
    fitAlpha(logicalExportPath, 50), fitNumeric("0", 1), fitNumeric("0", 1),
    fitNumeric(context.companyNumber, 9), fitNumeric("", 9), fitAlpha("", 10),
    fitAlpha(context.businessName, 50), fitAlpha(context.street, 50),
    fitAlpha(context.houseNumber, 10), fitAlpha(context.city, 30),
    fitAlpha(context.postalCode, 8), fitNumeric("", 4),
    fitNumeric(fromDate, 8), fitNumeric(toDate, 8), fitNumeric(exportDate, 8),
    fitNumeric(exportTime, 4), fitNumeric("0", 1), fitNumeric("1", 1),
    fitAlpha("zip", 20), fitAlpha("ILS", 3),
    fitNumeric(context.hasBranches ? "1" : "0", 1), fitAlpha("", 46),
  ], 466, "A000");
}

function buildA100({recordNumber, businessNumber, mainId}) {
  return joinFixed([
    fitAlpha("A100", 4), fitNumeric(recordNumber, 9),
    fitNumeric(businessNumber, 9), fitNumeric(mainId, 15),
    fitAlpha(BKMV_VERSION, 8), fitAlpha("", 50),
  ], RECORD_LENGTHS.A100, "A100");
}

function buildZ900({recordNumber, businessNumber, mainId, totalRecords}) {
  return joinFixed([
    fitAlpha("Z900", 4), fitNumeric(recordNumber, 9),
    fitNumeric(businessNumber, 9), fitNumeric(mainId, 15),
    fitAlpha(BKMV_VERSION, 8), fitNumeric(totalRecords, 15), fitAlpha("", 50),
  ], RECORD_LENGTHS.Z900, "Z900");
}

function buildB110({recordNumber, businessNumber, branchNumber, client}) {
  const address = splitAddress(client.address);
  return joinFixed([
    fitAlpha("B110", 4), fitNumeric(recordNumber, 9),
    fitNumeric(businessNumber, 9), fitNumeric(client.externalClientNumber, 15),
    fitAlpha(client.name, 50), fitAlpha(client.externalClientNumber, 15),
    fitAlpha(client.name, 30), fitAlpha(address.street, 50),
    fitAlpha(address.houseNumber, 10), fitAlpha(address.city, 30),
    fitAlpha(address.postalCode, 8), fitAlpha("", 30), fitAlpha("IL", 2),
    fitAlpha("", 15), fitSignedAmount(client.openingBalance, 12, 2),
    fitSignedAmount(client.periodDebits, 12, 2),
    fitSignedAmount(client.periodCredits, 12, 2), fitNumeric("0", 4),
    fitNumeric(client.taxId, 9), fitAlpha(branchNumber, 7),
    fitSignedAmount(0, 12, 2), fitAlpha("ILS", 3), fitAlpha("", 16),
  ], RECORD_LENGTHS.B110, "B110");
}

function buildC100(data) {
  const address = splitAddress(data.clientAddress);
  return joinFixed([
    fitAlpha("C100", 4), 
    fitNumeric(data.recordNumber, 9),
    fitNumeric(data.businessNumber, 9),
     fitNumeric(data.documentType, 3),
    fitAlpha(data.documentNumber, 20), 
    fitNumeric(data.issueDate, 8),
    fitNumeric(data.issueTime, 4), 
    fitAlpha(data.clientName, 50),
    fitAlpha(address.street, 50), 
    fitAlpha(address.houseNumber, 10),
    fitAlpha(address.city, 30),
     fitAlpha(address.postalCode, 8),
    fitAlpha("", 30), fitAlpha("", 2),
     fitAlpha(data.clientPhone, 15),
    fitNumeric(data.clientVatNumber, 9), 
    fitNumeric(data.valueDate, 8),
    fitAlpha("", 15),
    fitAlpha("", 3),
    fitSignedAmount(data.amountBeforeDiscount, 12, 2),
    fitSignedAmount(data.discountAmount, 12, 2),
    fitSignedAmount(data.beforeTaxAmount, 12, 2),
    fitSignedAmount(data.vatAmount, 12, 2),
    fitSignedAmount(data.totalAmount, 12, 2),
    fitSignedAmount(data.withholdingAmount, 9, 2),
    fitAlpha(data.customerKey, 15), fitAlpha("", 10), fitAlpha("", 1),
    fitNumeric(data.documentDate, 8), fitAlpha(data.branchNumber, 7),
    fitAlpha("", 9), fitNumeric(data.linkId, 7), fitAlpha("", 13),
  ], RECORD_LENGTHS.C100, "C100");
}

function buildD110(data) {
  return joinFixed([
    fitAlpha("D110", 4), fitNumeric(data.recordNumber, 9),
    fitNumeric(data.businessNumber, 9), fitNumeric(data.documentType, 3),
    fitAlpha(data.documentNumber, 20), fitNumeric(data.lineNumber, 4),
    fitNumeric(data.baseDocumentType || "", 3),
    fitAlpha(data.baseDocumentNumber || "", 20), fitNumeric("1", 1),
    fitAlpha("", 20), fitAlpha(data.description, 30), fitAlpha("", 50),
    fitAlpha("", 30), fitAlpha("יחידה", 20),
    fitSignedAmount(data.quantity, 12, 4), fitSignedAmount(data.unitPrice, 12, 2),
    fitSignedAmount(data.discountAmount, 12, 2),
    fitSignedAmount(data.lineTotal, 12, 2),
    fitNumeric(Math.round(data.vatRate * 100), 4),
    fitAlpha(data.branchNumber, 7), fitNumeric(data.documentDate, 8),
    fitNumeric(data.linkId, 7), fitAlpha(data.baseBranchNumber, 7),
    fitAlpha("", 21),
  ], RECORD_LENGTHS.D110, "D110");
}

function buildD120(data) {
  return joinFixed([
    fitAlpha("D120", 4), fitNumeric(data.recordNumber, 9),
    fitNumeric(data.businessNumber, 9), fitNumeric(data.documentType, 3),
    fitAlpha(data.documentNumber, 20), fitNumeric(data.lineNumber, 4),
    fitNumeric(data.paymentType, 1), fitNumeric(data.bankNumber || "", 10),
    fitNumeric(data.branchNumber || "", 10),
    fitNumeric(data.accountNumber || "", 15),
    fitNumeric(data.chequeNumber || "", 10),
    fitNumeric(data.paymentDate || "", 8), fitSignedAmount(data.amount, 12, 2),
    fitNumeric(data.creditCompany || "", 1), fitAlpha(data.cardName || "", 20),
    fitNumeric(data.creditDealType || "", 1),
    fitAlpha(data.businessBranchNumber, 7), fitNumeric(data.documentDate, 8),
    fitNumeric(data.linkId, 7), fitAlpha("", 60),
  ], RECORD_LENGTHS.D120, "D120");
}

function logEntryData(entry) {
  return entry && entry.data && typeof entry.data === "object" ? entry.data : entry;
}

function logEntryPath(entry) {
  return String(entry?.path || entry?.reference?.path || entry?.id || "");
}

function mergeAndSortLogs(entries) {
  const merged = new Map();
  for (const entry of entries || []) {
    const data = logEntryData(entry) || {};
    const bucket = String(data.bucket || "").trim();
    if (!BUCKET_NAMES.includes(bucket)) continue;
    const userId = String(data.userId || "").trim();
    const invoiceDocId = String(data.invoiceDocId || "").trim();
    const counter = String(data.counter || data.sequenceNumber || "").trim();
    const path = logEntryPath(entry);
    const key = invoiceDocId || counter ?
      `${userId}|${bucket}|${invoiceDocId}|${counter}` : path;
    if (!merged.has(key)) merged.set(key, {...entry, data, path});
  }
  return [...merged.values()].sort((left, right) => {
    const leftData = logEntryData(left) || {};
    const rightData = logEntryData(right) || {};
    const dateCompare = String(leftData.date || "")
        .localeCompare(String(rightData.date || ""));
    if (dateCompare) return dateCompare;
    const leftMillis = timestampToMillis(leftData.timestamp);
    const rightMillis = timestampToMillis(rightData.timestamp);
    if (leftMillis == null && rightMillis != null) return -1;
    if (leftMillis != null && rightMillis == null) return 1;
    if (leftMillis !== rightMillis) return (leftMillis || 0) - (rightMillis || 0);
    return logEntryPath(left).localeCompare(logEntryPath(right));
  });
}

function resolveInvoice(logData, invoicesById) {
  const candidates = [logData.invoiceDocId, logData.documentNumber,
    logData.invoiceNumber].map((value) => String(value || "").trim())
      .filter(Boolean);
  for (const candidate of candidates) {
    if (invoicesById[candidate]) return invoicesById[candidate];
  }
  return logData;
}

function authoritativeDocument(invoiceData) {
  const authoritative = invoiceData.authoritativeServerDocument;
  return authoritative && typeof authoritative === "object" ?
    {...invoiceData, ...authoritative, client: authoritative.client || {}} :
    invoiceData;
}

function validateContext(context) {
  if (!context || typeof context !== "object") {
    throw new Error("Business export context is missing.");
  }
  if (!isValidIsraeliId(context.businessNumber)) {
    throw new Error("The verified business number must be a valid 9-digit Israeli ID.");
  }
  if (!String(context.businessName || "").trim()) {
    throw new Error("The verified business name is required.");
  }
  if (!/^\d{8}$/.test(String(context.softwareRegistrationNumber || ""))) {
    throw new Error("The software registration number must contain exactly 8 digits.");
  }
  if (!isValidIsraeliId(context.softwareMakerVatNumber)) {
    throw new Error("The software maker VAT number must be a valid Israeli VAT number.");
  }
  if (!String(context.softwareMakerName || "").trim()) {
    throw new Error("The software maker name is required.");
  }
  if (context.hasBranches && !/^\d{1,7}$/.test(String(context.branchNumber || ""))) {
    throw new Error("The branch number must contain 1 through 7 digits.");
  }
  const vatPercent = finiteNumber(context.vatPercent, -1);
  if (vatPercent < 0 || vatPercent > 99.99) {
    throw new Error("The VAT percentage must be from 0 through 99.99.");
  }
}

function validateClients(clients) {
  for (const client of clients) {
    if (!/^\d{1,15}$/.test(String(client.externalClientNumber || "").trim())) {
      throw new Error(`Client ${client.id || client.name || "unknown"} is missing a valid accounting account key.`);
    }
  }
}

function generateBkmvPackage({context, logs, invoicesById = {}, clients = [],
  fromDate, toDate, exportTimestamp = new Date(), mainId = randomDigits(15)}) {
  validateContext(context);
  validateClients(clients);
  const compactFrom = normalizeCompactDate(fromDate, "fromDate");
  const compactTo = normalizeCompactDate(toDate, "toDate");
  if (compactFrom > compactTo) throw new Error("The export date range is invalid.");
  if (!/^\d{15}$/.test(String(mainId))) {
    throw new Error("The BKMV main identifier must contain exactly 15 digits.");
  }

  const sortedLogs = mergeAndSortLogs(logs);
  if (!sortedLogs.length) throw new Error("No documents found for the selected range.");
  const exportDate = formatCompactDate(exportTimestamp);
  const exportTime = formatTime(exportTimestamp);
  const businessKey = context.businessNumber.slice(0, 8);
  const timestampKey = `${exportDate.slice(4)}${exportTime}`;
  const logicalExportPath = `OPENFRMT\\${businessKey}.${exportDate.slice(2, 4)}\\${timestampKey}`;
  const records = [];
  const recordCounts = {};
  let recordNumber = 1;
  let linkNumber = 1;
  const linkIds = new Map();
  const typeCounts = {};
  const typeAmounts = {};
  let c100RecordCount = 0;

  const addRecord = (code, line) => {
    records.push(line);
    recordCounts[code] = (recordCounts[code] || 0) + 1;
    recordNumber += 1;
  };

  addRecord("A100", buildA100({
    recordNumber,
    businessNumber: context.businessNumber,
    mainId,
  }));

  const sortedClients = [...clients].sort((left, right) =>
    String(left.externalClientNumber).localeCompare(
        String(right.externalClientNumber), "en", {numeric: true},
    ) || String(left.id || "").localeCompare(String(right.id || "")));
  for (const client of sortedClients) {
    addRecord("B110", buildB110({
      recordNumber,
      businessNumber: context.businessNumber,
      branchNumber: context.branchNumber || "",
      client,
    }));
  }

  for (const entry of sortedLogs) {
    const logData = logEntryData(entry) || {};
    const storedInvoice = resolveInvoice(logData, invoicesById);
    const invoiceData = authoritativeDocument(storedInvoice || logData);
    const documentNumber = String(invoiceData.documentNumber ||
      storedInvoice.invoiceNumber || logData.invoiceNumber ||
      logData.documentNumber || "").trim();
    if (!documentNumber) continue;
    const docType = String(invoiceData.docType || invoiceData.type ||
      storedInvoice.type || logData.docType || "");
    const bucket = String(logData.bucket || "");
    const documentType = mapDocumentType(docType);
    if (!documentType) continue;

    const canonicalBeforeDiscount = invoiceData.amountBeforeDiscount;
    const rawDiscountAmount = finiteNumber(logData.discountAmount);
    const discountAmount = rawDiscountAmount === 0 ?
      0 : -Math.abs(rawDiscountAmount);
    const beforeTaxAmount = finiteNumber(logData.subtotalBeforeTax ??
      storedInvoice.subtotalBeforeTax ?? invoiceData.paymentAmount ??
      sumBeforeTaxAmount(logData, storedInvoice));
    const amountBeforeDiscount = finiteNumber(canonicalBeforeDiscount,
        beforeTaxAmount - discountAmount);
    const vatAmount = finiteNumber(logData.vatAmount ?? storedInvoice.vatAmount ??
      invoiceData.vatAmount);
    const totalAmount = finiteNumber(invoiceData.finalTotal ??
      logData.grandTotal ?? storedInvoice.amount ??
      logData.subtotalAfterTax ?? storedInvoice.subtotalAfterTax ??
      invoiceData.beforeRounding);
    const itemSubtotal = amountBeforeDiscount;
    const rawDate = logData.issueDate || storedInvoice.date ||
      invoiceData.date || logData.date;
    const documentDate = normalizeCompactDate(rawDate, "documentDate");
    const productionTimestamp = storedInvoice.createdAt ||
      invoiceData.createdAt || logData.timestamp;
    const productionMillis = timestampToMillis(productionTimestamp);
    const productionDate = productionMillis == null ? documentDate :
      formatCompactDate(new Date(productionMillis));
    const documentTime = timestampToTime(productionTimestamp);
    const clientDetails = logData.clientDetails &&
      typeof logData.clientDetails === "object" ? logData.clientDetails : {};
    const canonicalClient = invoiceData.client && typeof invoiceData.client === "object" ?
      invoiceData.client : {};
    const clientName = String(clientDetails.name || canonicalClient.name ||
      storedInvoice.clientName || logData.clientName || "");
    const clientAddress = String(clientDetails.address || canonicalClient.address ||
      storedInvoice.clientAddress || logData.clientAddress || "");
    const clientPhone = normalizeIsraeliPhone(clientDetails.phone ||
      canonicalClient.phone || storedInvoice.clientPhone || logData.clientPhone);
    const clientVatNumber = canonicalClient.id || storedInvoice.customerVatNumber ||
      storedInvoice.clientTaxId || "";
    const customerKey = String(logData.externalClientNumber ||
      canonicalClient.externalClientNumber || storedInvoice.externalClientNumber || "");
    if (!/^\d{1,15}$/.test(customerKey)) {
      throw new Error(`Document ${documentNumber} is missing a valid customer account key.`);
    }
    const linkKey = `${documentNumber}|${documentDate}`;
    if (!linkIds.has(linkKey)) linkIds.set(linkKey, linkNumber++);
    const linkId = linkIds.get(linkKey);
    const includesHeader = ["invoices", "invoice_tax_receipt",
      "transaction_account", "credit_notes"].includes(bucket) ||
      (bucket === "receipts" && docType === "receipt");
    const paymentMapping = ["receipts", "invoice_tax_receipt"].includes(bucket) ?
      mapPaymentDetails({logData, invoiceData: storedInvoice,
        defaultAmount: totalAmount}) : {details: [], withholdingAmount: 0};
    const isCancellationReceipt = documentType === 400 &&
      (invoiceData.isNegativeReceipt === true ||
        storedInvoice.isCancellationDocument === true ||
        logData.isCancellationDocument === true);
    let c100Total = documentType === 400 ?
      amountExcludingWithholding(totalAmount, paymentMapping.withholdingAmount) :
      totalAmount;
    let c100BeforeTax = documentType === 400 ?
      amountExcludingWithholding(beforeTaxAmount,
          paymentMapping.withholdingAmount) : beforeTaxAmount;
    let c100BeforeDiscount = documentType === 400 ?
      amountExcludingWithholding(amountBeforeDiscount,
          paymentMapping.withholdingAmount) : amountBeforeDiscount;
    const paymentDetails = paymentMapping.details.map((detail) => ({
      ...detail,
      amount: isCancellationReceipt ? -Math.abs(detail.amount) : detail.amount,
    }));
    if (isCancellationReceipt) {
      c100Total = -Math.abs(c100Total);
      c100BeforeTax = -Math.abs(c100BeforeTax);
      c100BeforeDiscount = -Math.abs(c100BeforeDiscount);
    }

    if (includesHeader) {
      addRecord("C100", buildC100({
        recordNumber,
        businessNumber: context.businessNumber,
        documentType,
        documentNumber,
        issueDate: productionDate,
        issueTime: documentTime,
        clientName,
        clientAddress,
        clientPhone,
        clientVatNumber,
        valueDate: documentDate,
        amountBeforeDiscount: c100BeforeDiscount,
        discountAmount,
        vatAmount,
        beforeTaxAmount: c100BeforeTax,
        totalAmount: c100Total,
        withholdingAmount: paymentMapping.withholdingAmount,
        customerKey,
        documentDate,
        linkId,
        branchNumber: context.branchNumber || "",
      }));
      c100RecordCount += 1;
      typeCounts[documentType] = (typeCounts[documentType] || 0) + 1;
      typeAmounts[documentType] = money((typeAmounts[documentType] || 0) + c100Total);
    }

    if (["invoices", "invoice_tax_receipt", "transaction_account",
      "credit_notes"].includes(bucket)) {
      const items = extractItems(logData, storedInvoice, itemSubtotal, vatAmount);
      for (const [index, item] of items.entries()) {
        addRecord("D110", buildD110({
          recordNumber,
          businessNumber: context.businessNumber,
          documentType,
          documentNumber,
          lineNumber: index + 1,
          baseDocumentType: docType === "credit_note" ?
            creditBaseDocumentType(storedInvoice) : null,
          baseDocumentNumber: originalCreditNumber(storedInvoice),
          description: item.description,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          discountAmount: item.discountAmount,
          lineTotal: item.lineTotal,
          vatRate: vatAmount !== 0 ? context.vatPercent : 0,
          documentDate,
          linkId,
          branchNumber: context.branchNumber || "",
          baseBranchNumber: docType === "credit_note" ?
            context.branchNumber || "" : "",
        }));
      }
    }

    if (["receipts", "invoice_tax_receipt"].includes(bucket)) {
      for (const [index, detail] of paymentDetails.entries()) {
        addRecord("D120", buildD120({
          recordNumber,
          businessNumber: context.businessNumber,
          documentType,
          documentNumber,
          lineNumber: index + 1,
          paymentType: detail.typeCode,
          bankNumber: detail.bankNumber,
          branchNumber: detail.branchNumber,
          accountNumber: detail.accountNumber,
          chequeNumber: detail.chequeNumber,
          paymentDate: detail.paymentDate,
          amount: detail.amount,
          creditCompany: detail.creditCompanyCode,
          cardName: detail.cardName,
          creditDealType: detail.creditDealType,
          documentDate,
          linkId,
          businessBranchNumber: context.branchNumber || "",
        }));
      }
    }
  }

  const totalRecords = records.length + 1;
  records.push(buildZ900({
    recordNumber: totalRecords,
    businessNumber: context.businessNumber,
    mainId,
    totalRecords,
  }));
  recordCounts.Z900 = 1;
  if (records.length < 2 || c100RecordCount < 1) {
    throw new Error("No supported BKMV documents were generated.");
  }
  const iniLines = [buildA000({
    totalRecords: records.length,
    context,
    mainId,
    logicalExportPath,
    fromDate: compactFrom,
    toDate: compactTo,
    exportDate,
    exportTime,
  })];
  for (const code of ["B110", "C100", "D110", "D120"]) {
    if (recordCounts[code]) {
      iniLines.push(fitAlpha(code, 4) + fitNumeric(recordCounts[code], 15));
    }
  }
  const bkmvText = `${records.join("\r\n")}\r\n`;
  const iniText = `${iniLines.join("\r\n")}\r\n`;
  const summary = {
    userId: context.userId,
    businessName: context.businessName,
    businessNumber: context.businessNumber,
    fromDate: compactFrom,
    toDate: compactTo,
    exportDate,
    exportTime,
    softwareName: context.softwareName,
    softwareRegistrationNumber: context.softwareRegistrationNumber,
    c100RecordCount,
    rows: PRINTED_SUMMARY_ROWS.map(([documentTypeCode, documentTypeLabel]) => ({
      documentTypeCode,
      documentTypeLabel,
      quantity: typeCounts[documentTypeCode] || 0,
      totalAmountIncludingVat: typeAmounts[documentTypeCode] || 0,
    })),
  };
  const annex4Summary = {
    userId: context.userId,
    businessName: context.businessName,
    businessNumber: context.businessNumber,
    softwareName: context.softwareName,
    softwareRegistrationNumber: context.softwareRegistrationNumber,
    exportDirectory: logicalExportPath,
    fromDate: compactFrom,
    toDate: compactTo,
    exportDate,
    exportTime,
    rows: ANNEX4_ROWS.map(([recordCode, recordLabel]) => ({
      recordCode,
      recordLabel,
      quantity: recordCounts[recordCode] || 0,
    })),
    totalRecords: records.length,
  };
  return {
    mainId,
    exportDate,
    exportTime,
    logicalExportPath,
    bkmvText,
    iniText,
    bkmvBytes: encodeIso88598(bkmvText),
    iniBytes: encodeIso88598(iniText),
    records,
    iniLines,
    recordCounts,
    summary,
    annex4Summary,
  };
}

module.exports = {
  ANNEX4_ROWS,
  BKMV_TIME_ZONE,
  BKMV_VERSION,
  BUCKET_NAMES,
  PRINTED_SUMMARY_ROWS,
  RECORD_LENGTHS,
  buildA000,
  buildA100,
  buildB110,
  buildC100,
  buildD110,
  buildD120,
  buildZ900,
  encodeIso88598,
  fitAlpha,
  fitNumeric,
  fitSignedAmount,
  formatCompactDate,
  formatTime,
  generateBkmvPackage,
  isValidIsraeliId,
  mapCreditCompanyCode,
  mapPaymentDetails,
  mergeAndSortLogs,
  normalizeCompactDate,
  sanitizeIso88598Text,
  splitPaymentAmount,
  validateContext,
};
