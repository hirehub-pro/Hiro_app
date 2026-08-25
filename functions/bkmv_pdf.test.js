"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {PDFDocument} = require("pdf-lib");

const {buildAnnex4Pdf, buildPrintedSummaryPdf} = require("./bkmv_pdf");

const generatedAt = new Date("2026-08-25T11:30:00Z");

test("generates the printed BKMV summary on the server", async () => {
  const bytes = await buildPrintedSummaryPdf({
    businessNumber: "123456782",
    businessName: "עסק בדיקה",
    fromDate: "20260801",
    toDate: "20260831",
    exportDate: "20260825",
    exportTime: "1430",
    softwareName: "הירו Hiro",
    softwareRegistrationNumber: "12345678",
    rows: [
      {documentTypeCode: 305, documentTypeLabel: "חשבונית-מס", quantity: 2,
        totalAmountIncludingVat: 236},
      {documentTypeCode: 400, documentTypeLabel: "קבלה", quantity: 1,
        totalAmountIncludingVat: 100},
    ],
  }, generatedAt);
  assert.equal(bytes.subarray(0, 4).toString("ascii"), "%PDF");
  assert.ok(bytes.length < 1024 * 1024);
  const pdf = await PDFDocument.load(bytes);
  assert.equal(pdf.getPageCount(), 1);
  assert.match(pdf.getTitle(), /123456782/);
});

test("generates Annex 4 on the server", async () => {
  const bytes = await buildAnnex4Pdf({
    businessNumber: "123456782",
    businessName: "עסק בדיקה",
    fromDate: "20260801",
    toDate: "20260831",
    exportDate: "20260825",
    exportTime: "1430",
    exportDirectory: "OPENFRMT\\12345678.26\\08251430",
    softwareName: "הירו Hiro",
    softwareRegistrationNumber: "12345678",
    totalRecords: 8,
    rows: [
      {recordCode: "A100", recordLabel: "רשומת פתיחה", quantity: 1},
      {recordCode: "C100", recordLabel: "כותרת מסמך", quantity: 1},
      {recordCode: "Z900", recordLabel: "רשומת סגירה", quantity: 1},
    ],
  }, generatedAt);
  assert.equal(bytes.subarray(0, 4).toString("ascii"), "%PDF");
  assert.ok(bytes.length < 1024 * 1024);
  const pdf = await PDFDocument.load(bytes);
  assert.equal(pdf.getPageCount(), 1);
  assert.match(pdf.getSubject(), /Annex 4/);
});
