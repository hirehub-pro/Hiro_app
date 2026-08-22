"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  mapAuthorityUploadFiles,
  maximumUploadBytes,
  normalizeSandboxPdfPaths,
  normalizeUniformSubmissionInput,
  safeSignedUploadHeaders,
  uniformOverallStatus,
  validateUniformFileContents,
  validateSandboxPdf,
} = require("./uniform_tax_authority");

test("normalizes a user-owned uniform export", () => {
  assert.deepEqual(normalizeUniformSubmissionInput({
    fromDate: "2026-01-01",
    toDate: "2026-01-31",
    filePaths: [
      "users/u1/uniform_exports/run/BKMVDATA.txt",
      "users/u1/uniform_exports/run/INI.txt",
    ],
  }, "u1"), {
    fromDate: "2026-01-01",
    toDate: "2026-01-31",
    iniPath: "users/u1/uniform_exports/run/INI.txt",
    bkmvPath: "users/u1/uniform_exports/run/BKMVDATA.txt",
  });
});

test("rejects cross-user paths and invalid dates", () => {
  assert.throws(() => normalizeUniformSubmissionInput({
    fromDate: "2026-02-01",
    toDate: "2026-01-01",
    filePaths: [
      "users/u2/uniform_exports/run/INI.txt",
      "users/u2/uniform_exports/run/BKMVDATA.txt",
    ],
  }, "u1"));
  assert.throws(() => normalizeUniformSubmissionInput({
    fromDate: "2026-02-30",
    toDate: "2026-03-01",
    filePaths: [
      "users/u1/uniform_exports/run/INI.txt",
      "users/u1/uniform_exports/run/BKMVDATA.txt",
    ],
  }, "u1"));
});

test("maps upload targets by the Tax Authority file names", () => {
  const ini = {fileName: "INI_N2026.pdf", signUrl: "https://storage.googleapis.com/ini", fileUniqueId: "ini.txt"};
  const bkmv = {fileName: "FROMBKM_BKMVDATA.pdf", signUrl: "https://storage.googleapis.com/bkmv", fileUniqueId: "bkmv.txt"};
  assert.deepEqual(mapAuthorityUploadFiles([bkmv, ini]), {ini, bkmv});
});

test("allows only documented signed-upload headers", () => {
  const headers = safeSignedUploadHeaders({
    "X-Goog-Resumable": "start",
    "x-goog-content-length-range": "0,1048576",
    authorization: "should-not-pass",
  });
  assert.deepEqual(headers, {
    "x-goog-resumable": "start",
    "x-goog-content-length-range": "0,1048576",
  });
  assert.equal(maximumUploadBytes(headers), 1048576);
});

test("derives an overall processing result", () => {
  assert.equal(uniformOverallStatus([
    {status: "Approved"}, {status: "Approved"},
  ]), "approved");
  assert.equal(uniformOverallStatus([
    {status: "Approved"}, {status: "Rejected"},
  ]), "rejected");
  assert.equal(uniformOverallStatus([
    {status: "Uploaded"}, {status: "Approved"},
  ]), "processing");
  assert.equal(uniformOverallStatus([
    {status: ""}, {status: "Approved", errorCode: 400},
  ]), "rejected");
});

test("validates the business, period, and main ID inside uniform files", () => {
  const businessId = "123456789";
  const mainId = "123456789012345";
  const ini = [
    "A000",
    " ".repeat(5),
    "1".padStart(15, "0"),
    businessId,
    mainId,
    "&OF1.31&",
    "1".padStart(8, "0"),
    " ".repeat(122),
    businessId,
    " ".repeat(171),
    "20260101",
    "20260131",
  ].join("");
  const bkmv = [
    `A100${"1".padStart(9, "0")}${businessId}${mainId}`,
    `Z900${"2".padStart(9, "0")}${businessId}${mainId}`,
  ].join("\r\n");
  assert.doesNotThrow(() => validateUniformFileContents({
    iniBytes: Buffer.from(ini, "latin1"),
    bkmvBytes: Buffer.from(bkmv, "latin1"),
    businessId,
    fromDate: "2026-01-01",
    toDate: "2026-01-31",
  }));
  assert.throws(() => validateUniformFileContents({
    iniBytes: Buffer.from(ini, "latin1"),
    bkmvBytes: Buffer.from(bkmv, "latin1"),
    businessId: "987654321",
    fromDate: "2026-01-01",
    toDate: "2026-01-31",
  }));
});

test("accepts only two small owned PDFs for the sandbox transport", () => {
  assert.deepEqual(normalizeSandboxPdfPaths({
    sandboxFilePaths: [
      "users/u1/uniform_exports/run/summary.pdf",
      "users/u1/uniform_exports/run/annex.pdf",
    ],
  }, "u1"), [
    "users/u1/uniform_exports/run/summary.pdf",
    "users/u1/uniform_exports/run/annex.pdf",
  ]);
  assert.doesNotThrow(() => validateSandboxPdf(Buffer.from("%PDF-test")));
  assert.throws(() => validateSandboxPdf(Buffer.from("plain text")));
});
