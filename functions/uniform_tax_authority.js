"use strict";

const UNIFORM_EXPORT_PREFIX = "uniform_exports";
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const EXPORT_ID_PATTERN = /^[A-Za-z0-9_-]{12,180}$/;

function normalizeUniformExportId(data) {
  const exportId = String(data?.exportId || "").trim();
  if (!EXPORT_ID_PATTERN.test(exportId)) {
    throw new Error("A valid server-generated export ID is required.");
  }
  return exportId;
}

function uniformSubmissionFromExport({data, userId, exportId}) {
  const exportData = data && typeof data === "object" ? data : {};
  if (exportData.userId !== userId ||
      !["ready", "submitted"].includes(exportData.status)) {
    throw new Error("The server-generated export is not ready for submission.");
  }
  const fromDate = String(exportData.fromDate || "").trim();
  const toDate = String(exportData.toDate || "").trim();
  if (!validIsoDate(fromDate) || !validIsoDate(toDate) || fromDate > toDate) {
    throw new Error("The server-generated export has an invalid period.");
  }
  const paths = exportData.paths && typeof exportData.paths === "object" ?
    exportData.paths : {};
  const allowedPrefix =
    `users/${userId}/${UNIFORM_EXPORT_PREFIX}/${exportId}/`;
  const requiredPaths = {
    iniPath: String(paths.ini || "").trim(),
    bkmvPath: String(paths.bkmv || "").trim(),
    printedSummaryPath: String(paths.printedSummary || "").trim(),
    annex4Path: String(paths.annex4 || "").trim(),
  };
  if (Object.values(requiredPaths).some((value) =>
    !value.startsWith(allowedPrefix))) {
    throw new Error("The export contains an invalid artifact path.");
  }
  if (requiredPaths.iniPath.split("/").pop().toUpperCase() !== "INI.TXT" ||
      requiredPaths.bkmvPath.split("/").pop().toUpperCase() !==
        "BKMVDATA.TXT" ||
      !requiredPaths.printedSummaryPath.toLowerCase().endsWith(".pdf") ||
      !requiredPaths.annex4Path.toLowerCase().endsWith(".pdf")) {
    throw new Error("The export contains invalid Tax Authority artifacts.");
  }
  return {
    exportId,
    fromDate,
    toDate,
    iniPath: requiredPaths.iniPath,
    bkmvPath: requiredPaths.bkmvPath,
    sandboxPdfPaths: [
      requiredPaths.printedSummaryPath,
      requiredPaths.annex4Path,
    ],
  };
}

function normalizeUniformSubmissionInput(data, userId) {
  const input = data && typeof data === "object" ? data : {};
  const fromDate = String(input.fromDate || "").trim();
  const toDate = String(input.toDate || "").trim();
  if (!validIsoDate(fromDate) || !validIsoDate(toDate) ||
      fromDate > toDate) {
    throw new Error("A valid export date range is required.");
  }

  const rawPaths = Array.isArray(input.filePaths) ? input.filePaths : [];
  if (rawPaths.length !== 2) {
    throw new Error("INI.txt and BKMVDATA.txt are required.");
  }

  const allowedPrefix = `users/${userId}/${UNIFORM_EXPORT_PREFIX}/`;
  const paths = rawPaths.map((value) => String(value || "").trim());
  if (paths.some((value) => !value.startsWith(allowedPrefix))) {
    throw new Error("Export files must belong to the signed-in user.");
  }

  const iniPath = paths.find((value) =>
    value.split("/").pop().toUpperCase() === "INI.TXT");
  const bkmvPath = paths.find((value) =>
    value.split("/").pop().toUpperCase() === "BKMVDATA.TXT");
  if (!iniPath || !bkmvPath) {
    throw new Error("The export must contain INI.txt and BKMVDATA.txt.");
  }

  return {fromDate, toDate, iniPath, bkmvPath};
}

function normalizeSandboxPdfPaths(data, userId) {
  const rawPaths = Array.isArray(data?.sandboxFilePaths) ?
    data.sandboxFilePaths : [];
  const allowedPrefix = `users/${userId}/${UNIFORM_EXPORT_PREFIX}/`;
  const paths = rawPaths.map((value) => String(value || "").trim());
  if (paths.length !== 2 || paths.some((value) =>
    !value.startsWith(allowedPrefix) || !value.toLowerCase().endsWith(".pdf"))) {
    throw new Error("Two user-owned sandbox PDF files are required.");
  }
  return paths;
}

function mapAuthorityUploadFiles(files) {
  if (!Array.isArray(files) || files.length !== 2) {
    throw new Error("The Tax Authority did not return two upload targets.");
  }
  const normalized = files.map((file) => {
    let signUrl;
    try {
      signUrl = new URL(String(file?.signUrl || ""));
    } catch (_) {
      signUrl = null;
    }
    if (!file || typeof file !== "object" ||
        !signUrl || signUrl.protocol !== "https:" ||
        signUrl.hostname !== "storage.googleapis.com" ||
        typeof file.fileUniqueId !== "string" || !file.fileUniqueId ||
        typeof file.fileName !== "string" || !file.fileName) {
      throw new Error("The Tax Authority returned an invalid upload target.");
    }
    return file;
  });

  const ini = normalized.find((file) => file.fileName.toUpperCase().includes("INI"));
  const bkmv = normalized.find((file) =>
    file.fileName.toUpperCase().includes("BKM"));
  const resolvedIni = ini || normalized[0];
  const resolvedBkmv = bkmv || normalized.find((file) => file !== resolvedIni);
  if (!resolvedBkmv || resolvedIni === resolvedBkmv) {
    throw new Error("The Tax Authority returned duplicate upload targets.");
  }
  return {ini: resolvedIni, bkmv: resolvedBkmv};
}

function safeSignedUploadHeaders(headers) {
  if (!headers || typeof headers !== "object" || Array.isArray(headers)) {
    return {};
  }
  const allowed = new Set([
    "x-goog-content-length-range",
    "x-goog-resumable",
  ]);
  return Object.fromEntries(Object.entries(headers)
      .map(([key, value]) => [String(key).toLowerCase(), String(value)])
      .filter(([key]) => allowed.has(key)));
}

function maximumUploadBytes(headers) {
  const safeHeaders = safeSignedUploadHeaders(headers);
  const parts = (safeHeaders["x-goog-content-length-range"] || "").split(",");
  const maximum = Number(parts[1]);
  return Number.isSafeInteger(maximum) && maximum > 0 ? maximum : null;
}

function uniformOverallStatus(files) {
  const normalizedFiles = Array.isArray(files) ? files : [];
  if (normalizedFiles.some((file) =>
    file?.errorCode != null || String(file?.errorMessage || "").trim())) {
    return "rejected";
  }
  const statuses = normalizedFiles
      .map((file) => String(file?.status || "").trim().toLowerCase());
  if (statuses.some((status) => status === "rejected")) return "rejected";
  if (statuses.length === 2 && statuses.every((status) => status === "approved")) {
    return "approved";
  }
  return "processing";
}

function validateUniformFileContents({
  iniBytes,
  bkmvBytes,
  businessId,
  fromDate,
  toDate,
}) {
  const iniLine = Buffer.from(iniBytes).toString("latin1").split(/\r?\n/, 1)[0];
  const bkmvLines = Buffer.from(bkmvBytes).toString("latin1")
      .split(/\r?\n/).filter(Boolean);
  const compactFrom = fromDate.replaceAll("-", "");
  const compactTo = toDate.replaceAll("-", "");
  // The second identifier in A000 is a company number.  It is optional for
  // licensed/exempt dealers and is correctly represented by nine zeroes.
  const companyNumber = iniLine.slice(186, 195);
  const hasCompanyNumber = /[1-9]/.test(companyNumber);
  if (iniLine.length < 382 || !iniLine.startsWith("A000") ||
      iniLine.slice(24, 33) !== businessId ||
      (hasCompanyNumber && companyNumber !== businessId) ||
      iniLine.slice(366, 374) !== compactFrom ||
      iniLine.slice(374, 382) !== compactTo) {
    throw new Error("INI.txt does not match the verified business and period.");
  }
  const firstRecord = bkmvLines[0] || "";
  const finalRecord = bkmvLines[bkmvLines.length - 1] || "";
  const mainId = iniLine.slice(33, 48);
  if (!firstRecord.startsWith("A100") || firstRecord.length < 37 ||
      firstRecord.slice(13, 22) !== businessId ||
      firstRecord.slice(22, 37) !== mainId ||
      !finalRecord.startsWith("Z900") || finalRecord.length < 37 ||
      finalRecord.slice(13, 22) !== businessId ||
      finalRecord.slice(22, 37) !== mainId) {
    throw new Error("BKMVDATA.txt does not match INI.txt or the verified business.");
  }
}

function validateSandboxPdf(bytes) {
  const buffer = Buffer.from(bytes);
  if (!buffer.length || buffer.length > 1024 * 1024 ||
      buffer.subarray(0, 5).toString("ascii") !== "%PDF-") {
    throw new Error("Sandbox test files must be PDFs no larger than 1 MB.");
  }
}

function validIsoDate(value) {
  if (!DATE_PATTERN.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

module.exports = {
  mapAuthorityUploadFiles,
  maximumUploadBytes,
  normalizeUniformExportId,
  normalizeSandboxPdfPaths,
  normalizeUniformSubmissionInput,
  safeSignedUploadHeaders,
  uniformSubmissionFromExport,
  uniformOverallStatus,
  validateUniformFileContents,
  validateSandboxPdf,
};
