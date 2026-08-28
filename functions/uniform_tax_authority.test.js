"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  mapAuthorityUploadFiles,
  maximumUploadBytes,
  normalizeUniformExportId,
  normalizeUniformSubmissionInput,
  safeSignedUploadHeaders,
  uniformSubmissionFromExport,
  uniformUploadEntries,
  uniformOverallStatus,
  validateUniformFileContents,
} = require("./uniform_tax_authority");

test("resolves Tax Authority files from a server-owned export", () => {
  const exportId = normalizeUniformExportId({
    exportId: "12345678-1234-1234-1234-123456789012",
  });
  const root = `users/u1/uniform_exports/${exportId}`;
  assert.deepEqual(uniformSubmissionFromExport({
    userId: "u1",
    exportId,
    data: {
      userId: "u1",
      status: "ready",
      fromDate: "2026-01-01",
      toDate: "2026-01-31",
      paths: {
        ini: `${root}/authority/INI.TXT`,
        bkmv: `${root}/authority/BKMVDATA.TXT`,
      },
    },
  }), {
    exportId,
    fromDate: "2026-01-01",
    toDate: "2026-01-31",
    iniPath: `${root}/authority/INI.TXT`,
    bkmvPath: `${root}/authority/BKMVDATA.TXT`,
  });
});

test("rejects cross-user or client-selected server export artifacts", () => {
  const exportId = "12345678-1234-1234-1234-123456789012";
  assert.throws(() => uniformSubmissionFromExport({
    userId: "u1",
    exportId,
    data: {
      userId: "u2",
      status: "ready",
      fromDate: "2026-01-01",
      toDate: "2026-01-31",
      paths: {},
    },
  }), /not ready/);
  assert.throws(() => uniformSubmissionFromExport({
    userId: "u1",
    exportId,
    data: {
      userId: "u1",
      status: "ready",
      fromDate: "2026-01-01",
      toDate: "2026-01-31",
      paths: {
        ini: "users/u2/uniform_exports/run/INI.TXT",
        bkmv: "users/u2/uniform_exports/run/BKMVDATA.TXT",
      },
    },
  }), /invalid artifact path/);
});

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

test("maps upload targets in the Tax Authority documented order", () => {
  const ini = {fileName: "first", signUrl: "https://storage.googleapis.com/ini", fileUniqueId: "ini.txt"};
  const bkmv = {fileName: "second", signUrl: "https://storage.googleapis.com/bkmv", fileUniqueId: "bkmv.txt"};
  assert.deepEqual(mapAuthorityUploadFiles([ini, bkmv]), {ini, bkmv});
});

test("uploads the actual uniform TXT bytes instead of PDF reports", () => {
  const ini = {fileName: "first"};
  const bkmv = {fileName: "second"};
  const iniBytes = Buffer.from("A000 uniform data", "latin1");
  const bkmvBytes = Buffer.from("A100\r\nZ900\r\n", "latin1");
  const entries = uniformUploadEntries({
    targets: {ini, bkmv},
    iniBytes,
    bkmvBytes,
    iniPath: "exports/INI.TXT",
    bkmvPath: "exports/BKMVDATA.TXT",
  });
  assert.equal(entries[0].bytes, iniBytes);
  assert.equal(entries[1].bytes, bkmvBytes);
  assert.equal(entries.some((entry) =>
    entry.bytes.subarray(0, 5).toString("ascii") === "%PDF-"), false);
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
  const licensedDealerIni = `${ini.slice(0, 186)}${"0".repeat(9)}${ini.slice(195)}`;
  assert.doesNotThrow(() => validateUniformFileContents({
    iniBytes: Buffer.from(licensedDealerIni, "latin1"),
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
