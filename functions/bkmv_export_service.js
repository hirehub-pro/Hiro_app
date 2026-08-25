"use strict";

const crypto = require("crypto");

const {buildBkmvArchives} = require("./bkmv_archive");
const {
  BUCKET_NAMES,
  generateBkmvPackage,
  normalizeCompactDate,
} = require("./bkmv_generator");
const {buildAnnex4Pdf, buildPrintedSummaryPdf} = require("./bkmv_pdf");

const EXPORT_RETENTION_HOURS = 24;
const EXPORT_ID_PATTERN = /^[A-Za-z0-9_-]{12,180}$/;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function normalizeUniformExportRequest(value) {
  const data = value && typeof value === "object" ? value : {};
  const fromDate = String(data.fromDate || "").trim();
  const toDate = String(data.toDate || "").trim();
  const compactFrom = normalizeCompactDate(fromDate, "fromDate");
  const compactTo = normalizeCompactDate(toDate, "toDate");
  if (compactFrom > compactTo) throw new Error("The export date range is invalid.");
  const recipientEmail = String(data.recipientEmail || "").trim().toLowerCase();
  if (!EMAIL_PATTERN.test(recipientEmail) || recipientEmail.length > 254) {
    throw new Error("A valid recipient email address is required.");
  }
  return {
    fromDate: compactFrom,
    toDate: compactTo,
    fromDateIso: `${compactFrom.slice(0, 4)}-${compactFrom.slice(4, 6)}-${compactFrom.slice(6)}`,
    toDateIso: `${compactTo.slice(0, 4)}-${compactTo.slice(4, 6)}-${compactTo.slice(6)}`,
    recipientEmail,
  };
}

function splitAddress(value) {
  const parts = String(value || "").split(",").map((part) => part.trim());
  const streetWithNumber = parts[0] || "";
  const match = streetWithNumber.match(/(\d+[A-Za-z]?)/);
  const houseNumber = match ? match[1] : "";
  const street = houseNumber ? streetWithNumber.replace(houseNumber, "").trim() :
    streetWithNumber;
  return {
    street: street || streetWithNumber,
    houseNumber,
    city: parts[1] || "",
    postalCode: String(parts[2] || "").replace(/\D/g, ""),
  };
}

function buildBusinessContext({userId, userData, publicData, verificationData,
  metadata}) {
  const user = {...(userData || {}), ...(publicData || {})};
  const verification = verificationData || {};
  const status = String(verification.businessVerificationStatus ||
    verification.status || "").trim().toLowerCase();
  if (status !== "approved") {
    throw new Error("Approved business verification is required for BKMV export.");
  }
  const businessNumber = String(verification.businessId ||
    verification.businessNumber || user.businessNumber || "")
      .replace(/\D/g, "");
  const businessName = String(verification.businessName ||
    user.businessName || user.name || "").trim();
  const dealerType = String(verification.dealerType ||
    user.dealerType || "").trim().toLowerCase();
  if (!["exempt", "licensed", "company"].includes(dealerType)) {
    throw new Error("The verified dealer type is invalid.");
  }
  const legacyAddress = splitAddress(verification.address ||
    user.businessAddress || user.address);
  const structured = ["street", "houseNumber", "city", "postalCode"]
      .some((field) => verification[field] != null || user[field] != null);
  const addressValue = (field) => structured ?
    String(verification[field] ?? user[field] ?? "").trim() : legacyAddress[field];
  const hasBranches = verification.hasBranches === true;
  return {
    userId,
    businessNumber,
    companyNumber: dealerType === "company" ? businessNumber : "",
    businessName,
    street: addressValue("street"),
    houseNumber: addressValue("houseNumber"),
    city: addressValue("city"),
    postalCode: addressValue("postalCode").replace(/\D/g, ""),
    hasBranches,
    branchNumber: hasBranches ?
      String(verification.branchNumber || "").replace(/\D/g, "") : "",
    softwareName: String(metadata.softwareName || "הירו Hiro").trim(),
    softwareVersion: String(metadata.minRequiredVersion ||
      metadata.softwareVersion || "1.0.0").trim(),
    softwareRegistrationNumber: String(
        metadata.softwareRegistrationNumber || "",
    ).replace(/\D/g, ""),
    softwareMakerVatNumber: String(metadata.softwareMakerVatNumber || "")
        .replace(/\D/g, ""),
    softwareMakerName: String(metadata.softwareMakerName ||
      metadata.appName || "").trim(),
    vatPercent: Number(metadata.vatPercent),
  };
}

function documentCandidateIds(log) {
  const candidates = new Set();
  const invoiceDocId = String(log.invoiceDocId || "").trim();
  if (invoiceDocId) candidates.add(invoiceDocId);
  const documentNumber = String(log.invoiceNumber || log.documentNumber || "").trim();
  const docType = String(log.docType || "").trim();
  if (documentNumber.includes("-") && docType) {
    candidates.add(`${docType}_${documentNumber}`);
  }
  return [...candidates];
}

async function getDocumentsInChunks(db, references, chunkSize = 100) {
  const snapshots = [];
  for (let index = 0; index < references.length; index += chunkSize) {
    snapshots.push(...await db.getAll(...references.slice(index, index + chunkSize)));
  }
  return snapshots;
}

async function loadBkmvSourceData({db, userId, fromDate, toDate}) {
  const userRef = db.collection("users").doc(userId);
  const queryPromises = BUCKET_NAMES.map((bucket) =>
    userRef.collection("logs").doc(bucket).collection("files")
        .where("date", ">=", fromDate)
        .where("date", "<=", toDate)
        .orderBy("date")
        .get());
  const [userSnap, publicSnap, verificationSnap, metadataSnap, clientSnap,
    ...logSnapshots] = await Promise.all([
    userRef.get(),
    db.collection("publicWorkerProfiles").doc(userId).get(),
    userRef.collection("verification_info").doc("latest").get(),
    db.collection("metadata").doc("system").get(),
    userRef.collection("clients").get(),
    ...queryPromises,
  ]);
  if (!userSnap.exists) throw new Error("The authenticated user profile was not found.");
  const context = buildBusinessContext({
    userId,
    userData: userSnap.data() || {},
    publicData: publicSnap.data() || {},
    verificationData: verificationSnap.data() || {},
    metadata: metadataSnap.data() || {},
  });
  const logs = logSnapshots.flatMap((snapshot) => snapshot.docs.map((doc) => ({
    id: doc.id,
    path: doc.ref.path,
    data: doc.data(),
  })));
  const invoiceIds = new Set();
  for (const entry of logs) {
    for (const id of documentCandidateIds(entry.data)) invoiceIds.add(id);
    if (entry.id) invoiceIds.add(entry.id);
  }
  const invoiceRefs = [...invoiceIds].map((id) =>
    userRef.collection("invoices").doc(id));
  const invoiceSnapshots = invoiceRefs.length ?
    await getDocumentsInChunks(db, invoiceRefs) : [];
  const invoicesById = {};
  for (const snapshot of invoiceSnapshots) {
    if (!snapshot.exists) continue;
    const data = snapshot.data() || {};
    invoicesById[snapshot.id] = data;
    const canonical = data.authoritativeServerDocument;
    for (const number of [data.invoiceNumber, data.documentNumber,
      canonical?.documentNumber]) {
      const key = String(number || "").trim();
      if (key && !invoicesById[key]) invoicesById[key] = data;
    }
  }
  const clients = clientSnap.docs.map((doc) => {
    const data = doc.data() || {};
    return {
      id: doc.id,
      name: String(data.name || "").trim(),
      externalClientNumber: String(data.externalClientNumber || "").trim(),
      taxId: String(data.taxId || "").trim(),
      address: String(data.address || "").trim(),
    };
  });
  return {context, logs, invoicesById, clients};
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

async function buildUniformArtifacts({source, fromDate, toDate,
  exportTimestamp = new Date(), mainId}) {
  const generated = generateBkmvPackage({
    ...source,
    fromDate,
    toDate,
    exportTimestamp,
    ...(mainId ? {mainId} : {}),
  });
  const [archives, printedSummaryPdf, annex4Pdf] = await Promise.all([
    buildBkmvArchives({generated, exportTimestamp}),
    buildPrintedSummaryPdf(generated.summary, exportTimestamp),
    buildAnnex4Pdf(generated.annex4Summary, exportTimestamp),
  ]);
  if (printedSummaryPdf.length > 1024 * 1024 || annex4Pdf.length > 1024 * 1024) {
    throw new Error("The sandbox PDF files must each be no larger than 1 MB.");
  }
  const stamp = `${generated.exportDate}_${generated.exportTime}`;
  const files = {
    bundle: {
      fileName: archives.outerZipFileName,
      contentType: "application/zip",
      bytes: archives.outerZipBytes,
    },
    printedSummary: {
      fileName: `BKMV_printed_summary_${stamp}.pdf`,
      contentType: "application/pdf",
      bytes: printedSummaryPdf,
    },
    annex4: {
      fileName: `BKMV_annex_4_${stamp}.pdf`,
      contentType: "application/pdf",
      bytes: annex4Pdf,
    },
    ini: {
      fileName: "INI.TXT",
      contentType: "text/plain",
      bytes: generated.iniBytes,
    },
    bkmv: {
      fileName: "BKMVDATA.TXT",
      contentType: "text/plain",
      bytes: generated.bkmvBytes,
    },
    bkmvZip: {
      fileName: archives.bkmvZipFileName,
      contentType: "application/zip",
      bytes: archives.bkmvZipBytes,
    },
  };
  return {
    generated,
    files,
    hashes: Object.fromEntries(Object.entries(files).map(([key, file]) => [
      key,
      sha256(file.bytes),
    ])),
  };
}

function firebaseDownloadUrl(bucketName, storagePath, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucketName)}` +
    `/o/${encodeURIComponent(storagePath)}?alt=media&token=${encodeURIComponent(token)}`;
}

async function saveUniformArtifacts({bucket, userId, exportId, artifacts,
  now = new Date()}) {
  if (!EXPORT_ID_PATTERN.test(exportId)) throw new Error("Invalid uniform export ID.");
  const root = `users/${userId}/uniform_exports/${exportId}`;
  const token = crypto.randomUUID();
  const descriptors = {
    bundle: {path: `${root}/${artifacts.files.bundle.fileName}`, token},
    printedSummary: {path: `${root}/${artifacts.files.printedSummary.fileName}`},
    annex4: {path: `${root}/${artifacts.files.annex4.fileName}`},
    ini: {path: `${root}/authority/INI.TXT`},
    bkmv: {path: `${root}/authority/BKMVDATA.TXT`},
    bkmvZip: {path: `${root}/authority/BKMVDATA.ZIP`},
  };
  await Promise.all(Object.entries(descriptors).map(async ([key, descriptor]) => {
    const artifact = artifacts.files[key];
    await bucket.file(descriptor.path).save(artifact.bytes, {
      resumable: false,
      validation: "crc32c",
      metadata: {
        contentType: artifact.contentType,
        cacheControl: "private, max-age=0, no-transform",
        contentDisposition: `attachment; filename="${artifact.fileName}"`,
        metadata: {
          ownerUid: userId,
          exportId,
          generatedBy: "server",
          sha256: artifacts.hashes[key],
          ...(descriptor.token ? {firebaseStorageDownloadTokens: descriptor.token} : {}),
        },
      },
    });
  }));
  return {
    root,
    paths: Object.fromEntries(Object.entries(descriptors)
        .map(([key, descriptor]) => [key, descriptor.path])),
    downloadUrl: firebaseDownloadUrl(bucket.name, descriptors.bundle.path, token),
    expiresAt: new Date(now.getTime() + EXPORT_RETENTION_HOURS * 60 * 60 * 1000),
  };
}

module.exports = {
  EXPORT_ID_PATTERN,
  EXPORT_RETENTION_HOURS,
  buildBusinessContext,
  buildUniformArtifacts,
  firebaseDownloadUrl,
  loadBkmvSourceData,
  normalizeUniformExportRequest,
  saveUniformArtifacts,
  sha256,
};
