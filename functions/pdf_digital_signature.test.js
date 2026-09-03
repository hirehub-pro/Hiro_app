"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {execFileSync} = require("node:child_process");
const test = require("node:test");
const {PDFDocument} = require("pdf-lib");

const {
  decodeMasterKey,
  decryptSigningCredential,
  encryptSigningCredential,
  generateBusinessSigningCredential,
  inspectPdfDigitalSignature,
  isAccountingDocumentType,
  signPdfWithCredential,
} = require("./pdf_digital_signature");

const TEST_BUSINESS = {
  name: "עסק בדיקה בע״מ",
  businessId: "123456789",
  email: "owner@example.com",
};

async function samplePdf() {
  const pdf = await PDFDocument.create();
  const page = pdf.addPage([300, 200]);
  page.drawText("Invoice 42", {x: 30, y: 150, size: 18});
  return Buffer.from(await pdf.save());
}

function verifyCmsWithOpenSsl(inspection) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "hiro-pdf-signature-"));
  const signaturePath = path.join(directory, "signature.der");
  const contentPath = path.join(directory, "content.bin");
  const verifiedPath = path.join(directory, "verified.bin");
  try {
    fs.writeFileSync(signaturePath, inspection.signatureBytes);
    fs.writeFileSync(contentPath, inspection.signedData);
    execFileSync("openssl", [
      "cms",
      "-verify",
      "-inform", "DER",
      "-binary",
      "-noverify",
      "-in", signaturePath,
      "-content", contentPath,
      "-out", verifiedPath,
    ], {stdio: "pipe"});
    return true;
  } catch (error) {
    return false;
  } finally {
    fs.rmSync(directory, {recursive: true, force: true});
  }
}

test("recognizes only finalized accounting document types", () => {
  for (const docType of [
    "transaction_account",
    "invoice",
    "invoice_receipt",
    "credit_note",
    "receipt",
  ]) {
    assert.equal(isAccountingDocumentType(docType), true, docType);
  }
  assert.equal(isAccountingDocumentType("quote"), false);
  assert.equal(isAccountingDocumentType("work_order"), false);
});

test("requires an exact base64-encoded 32-byte master key", () => {
  const encoded = Buffer.alloc(32, 7).toString("base64");
  assert.deepEqual(decodeMasterKey(encoded), Buffer.alloc(32, 7));
  assert.throws(() => decodeMasterKey(""), /not configured/);
  assert.throws(() => decodeMasterKey(Buffer.alloc(31).toString("base64")),
      /32-byte/);
});

test("encrypts each business credential with authenticated business binding", () => {
  const masterKey = Buffer.alloc(32, 11);
  const credential = generateBusinessSigningCredential({
    businessId: TEST_BUSINESS.businessId,
    businessName: TEST_BUSINESS.name,
    generatedAt: new Date("2026-09-03T09:00:00Z"),
  });
  const encrypted = encryptSigningCredential({
    credential,
    masterKey,
    userId: "test-user-123456789012",
    businessId: TEST_BUSINESS.businessId,
  });
  assert.equal(encrypted.algorithm, "aes-256-gcm");
  assert.equal(JSON.stringify(encrypted).includes(credential.passphrase), false);

  const decrypted = decryptSigningCredential({
    encrypted,
    masterKey,
    userId: "test-user-123456789012",
    businessId: TEST_BUSINESS.businessId,
  });
  assert.deepEqual(decrypted.pkcs12Bytes, credential.pkcs12Bytes);
  assert.equal(decrypted.passphrase, credential.passphrase);
  assert.throws(() => decryptSigningCredential({
    encrypted,
    masterKey,
    userId: "different-user-123456789",
    businessId: TEST_BUSINESS.businessId,
  }), /could not be decrypted/);
});

test("creates a whole-document PAdES signature that OpenSSL verifies", async () => {
  const credential = generateBusinessSigningCredential({
    businessId: TEST_BUSINESS.businessId,
    businessName: TEST_BUSINESS.name,
    generatedAt: new Date("2026-09-03T09:00:00Z"),
  });
  const signed = await signPdfWithCredential({
    pdfBytes: await samplePdf(),
    credential,
    business: TEST_BUSINESS,
    documentNumber: "2026-0042",
    signingTime: new Date("2026-09-03T10:00:00Z"),
  });
  const inspection = inspectPdfDigitalSignature(signed);
  assert.equal(inspection.coversWholeDocument, true);
  assert.equal(inspection.hasPadesSubFilter, true);
  assert.ok(inspection.signatureBytes.length > 500);
  assert.equal(verifyCmsWithOpenSsl(inspection), true);

  const tampered = Buffer.from(signed);
  tampered[10] ^= 1;
  assert.equal(verifyCmsWithOpenSsl(inspectPdfDigitalSignature(tampered)), false);
});

test("rejects a PDF that already contains a signature", async () => {
  const credential = generateBusinessSigningCredential({
    businessId: TEST_BUSINESS.businessId,
    businessName: TEST_BUSINESS.name,
  });
  const signed = await signPdfWithCredential({
    pdfBytes: await samplePdf(),
    credential,
    business: TEST_BUSINESS,
    documentNumber: "42",
  });
  await assert.rejects(() => signPdfWithCredential({
    pdfBytes: signed,
    credential,
    business: TEST_BUSINESS,
    documentNumber: "42",
  }), /already contains/);
});
