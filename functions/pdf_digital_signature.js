"use strict";

const crypto = require("crypto");
const forge = require("node-forge");
const {PDFDocument} = require("pdf-lib");
const {pdflibAddPlaceholder} = require("@signpdf/placeholder-pdf-lib");
const {P12Signer} = require("@signpdf/signer-p12");
const {SignPdf} = require("@signpdf/signpdf");
const {
  SUBFILTER_ETSI_CADES_DETACHED,
  extractSignature,
} = require("@signpdf/utils");

const ACCOUNTING_DOCUMENT_TYPES = new Set([
  "transaction_account",
  "invoice",
  "invoice_receipt",
  "credit_note",
  "receipt",
]);
const CREDENTIAL_SCHEMA_VERSION = 1;
const ENCRYPTION_ALGORITHM = "aes-256-gcm";
const SIGNATURE_PLACEHOLDER_LENGTH = 16384;

function boundedText(value, maxLength, fallback = "") {
  const text = value == null ? "" : String(value).trim();
  return (text || fallback).slice(0, maxLength);
}

function normalizedBusinessId(value) {
  return String(value == null ? "" : value).replace(/\D/g, "").slice(0, 20);
}

function isAccountingDocumentType(docType) {
  return ACCOUNTING_DOCUMENT_TYPES.has(String(docType || "").trim());
}

function decodeMasterKey(value) {
  const encoded = String(value || "").trim();
  if (!encoded) {
    throw new Error("PDF_SIGNING_MASTER_KEY is not configured.");
  }
  const key = Buffer.from(encoded, "base64");
  if (key.length !== 32 || key.toString("base64").replace(/=+$/, "") !==
      encoded.replace(/=+$/, "")) {
    throw new Error("PDF_SIGNING_MASTER_KEY must be a base64-encoded 32-byte key.");
  }
  return key;
}

function credentialAad({userId, businessId}) {
  const uid = boundedText(userId, 128);
  const id = normalizedBusinessId(businessId);
  if (!uid || !id) {
    throw new Error("A user and verified business ID are required for PDF signing.");
  }
  return Buffer.from(`hiro-pdf-signing:v${CREDENTIAL_SCHEMA_VERSION}:${uid}:${id}`);
}

function encryptSigningCredential({credential, masterKey, userId, businessId}) {
  const key = Buffer.isBuffer(masterKey) ? masterKey : decodeMasterKey(masterKey);
  if (key.length !== 32) throw new Error("The PDF signing master key is invalid.");
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(ENCRYPTION_ALGORITHM, key, iv);
  cipher.setAAD(credentialAad({userId, businessId}));
  const plaintext = Buffer.from(JSON.stringify({
    pkcs12Base64: Buffer.from(credential.pkcs12Bytes).toString("base64"),
    passphrase: String(credential.passphrase || ""),
  }));
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return {
    schemaVersion: CREDENTIAL_SCHEMA_VERSION,
    algorithm: ENCRYPTION_ALGORITHM,
    iv: iv.toString("base64"),
    authenticationTag: cipher.getAuthTag().toString("base64"),
    ciphertext: ciphertext.toString("base64"),
  };
}

function decryptSigningCredential({encrypted, masterKey, userId, businessId}) {
  if (Number(encrypted?.schemaVersion) !== CREDENTIAL_SCHEMA_VERSION ||
      encrypted?.algorithm !== ENCRYPTION_ALGORITHM) {
    throw new Error("The stored PDF signing credential version is unsupported.");
  }
  const key = Buffer.isBuffer(masterKey) ? masterKey : decodeMasterKey(masterKey);
  if (key.length !== 32) throw new Error("The PDF signing master key is invalid.");
  try {
    const decipher = crypto.createDecipheriv(
        ENCRYPTION_ALGORITHM,
        key,
        Buffer.from(encrypted.iv, "base64"),
    );
    decipher.setAAD(credentialAad({userId, businessId}));
    decipher.setAuthTag(Buffer.from(encrypted.authenticationTag, "base64"));
    const plaintext = Buffer.concat([
      decipher.update(Buffer.from(encrypted.ciphertext, "base64")),
      decipher.final(),
    ]);
    const parsed = JSON.parse(plaintext.toString("utf8"));
    const pkcs12Bytes = Buffer.from(parsed.pkcs12Base64 || "", "base64");
    if (pkcs12Bytes.length < 1 || typeof parsed.passphrase !== "string") {
      throw new Error("The decrypted credential is incomplete.");
    }
    return {pkcs12Bytes, passphrase: parsed.passphrase};
  } catch (error) {
    throw new Error("The stored PDF signing credential could not be decrypted.");
  }
}

function positiveSerialNumber() {
  const bytes = crypto.randomBytes(16);
  bytes[0] &= 0x7f;
  if (bytes.every((value) => value === 0)) bytes[15] = 1;
  return bytes.toString("hex");
}

function generateBusinessSigningCredential({
  businessId,
  businessName,
  generatedAt = new Date(),
}) {
  const id = normalizedBusinessId(businessId);
  const name = boundedText(businessName, 120);
  if (!id || !name) {
    throw new Error("Verified business details are required to create a signer.");
  }

  const pair = crypto.generateKeyPairSync("rsa", {
    modulusLength: 2048,
    publicExponent: 0x10001,
  });
  const privateKey = forge.pki.privateKeyFromPem(pair.privateKey.export({
    format: "pem",
    type: "pkcs8",
  }));
  const publicKey = forge.pki.publicKeyFromPem(pair.publicKey.export({
    format: "pem",
    type: "spki",
  }));
  const certificate = forge.pki.createCertificate();
  certificate.publicKey = publicKey;
  certificate.serialNumber = positiveSerialNumber();
  certificate.validity.notBefore = new Date(generatedAt.getTime() - 5 * 60 * 1000);
  certificate.validity.notAfter = new Date(generatedAt);
  certificate.validity.notAfter.setUTCFullYear(
      certificate.validity.notAfter.getUTCFullYear() + 5,
  );
  const attributes = [
    {name: "countryName", value: "IL"},
    {name: "organizationName", value: "Hiro Verified Business"},
    {name: "commonName", value: `Hiro Business ${id}`},
    {name: "serialNumber", value: id},
  ];
  certificate.setSubject(attributes);
  certificate.setIssuer(attributes);
  certificate.setExtensions([
    {name: "basicConstraints", cA: false},
    {
      name: "keyUsage",
      digitalSignature: true,
      nonRepudiation: true,
    },
    {name: "subjectKeyIdentifier"},
  ]);
  certificate.sign(privateKey, forge.md.sha256.create());

  const passphrase = crypto.randomBytes(32).toString("base64url");
  const pkcs12 = forge.pkcs12.toPkcs12Asn1(
      privateKey,
      [certificate],
      passphrase,
      {algorithm: "aes256", generateLocalKeyId: true, friendlyName: `Hiro ${id}`},
  );
  const certificateDer = Buffer.from(
      forge.asn1.toDer(forge.pki.certificateToAsn1(certificate)).getBytes(),
      "binary",
  );
  return {
    pkcs12Bytes: Buffer.from(forge.asn1.toDer(pkcs12).getBytes(), "binary"),
    passphrase,
    metadata: {
      schemaVersion: CREDENTIAL_SCHEMA_VERSION,
      certificateType: "hiro_verified_business_self_signed",
      signatureFormat: "PAdES/CAdES detached",
      digestAlgorithm: "SHA-256",
      keyAlgorithm: "RSA-2048",
      businessId: id,
      businessName: name,
      certificateSerialNumber: certificate.serialNumber,
      certificateFingerprintSha256:
        crypto.createHash("sha256").update(certificateDer).digest("hex"),
      validFrom: certificate.validity.notBefore.toISOString(),
      validUntil: certificate.validity.notAfter.toISOString(),
    },
  };
}

function inspectPdfDigitalSignature(pdfBytes) {
  const pdf = Buffer.from(pdfBytes || []);
  if (!pdf.subarray(0, 5).equals(Buffer.from("%PDF-"))) {
    throw new Error("A valid PDF is required.");
  }
  const {ByteRange, signature, signedData} = extractSignature(pdf);
  const coversWholeDocument = ByteRange[0] === 0 &&
    ByteRange[2] + ByteRange[3] === pdf.length;
  const hasPadesSubFilter = pdf.includes(
      Buffer.from("/SubFilter /ETSI.CAdES.detached"),
  );
  return {
    byteRange: ByteRange,
    coversWholeDocument,
    hasPadesSubFilter,
    signatureBytes: Buffer.from(signature, "binary"),
    signedData,
  };
}

async function signPdfWithCredential({
  pdfBytes,
  credential,
  business,
  documentNumber,
  signingTime = new Date(),
}) {
  const input = Buffer.from(pdfBytes || []);
  if (!input.subarray(0, 5).equals(Buffer.from("%PDF-"))) {
    throw new Error("A valid PDF is required for digital signing.");
  }
  if (input.includes(Buffer.from("/ByteRange"))) {
    throw new Error("The PDF already contains a digital signature.");
  }
  const businessId = normalizedBusinessId(business?.businessId);
  const businessName = boundedText(business?.name, 120);
  if (!businessId || !businessName) {
    throw new Error("Verified business details are required for PDF signing.");
  }

  const pdf = await PDFDocument.load(input, {updateMetadata: false});
  pdflibAddPlaceholder({
    pdfDoc: pdf,
    reason: boundedText(
        `Computerized accounting document ${documentNumber || ""}`,
        200,
        "Computerized accounting document",
    ),
    contactInfo: boundedText(business.email, 200),
    name: `${businessName} (${businessId})`.slice(0, 200),
    location: "Israel",
    signingTime,
    signatureLength: SIGNATURE_PLACEHOLDER_LENGTH,
    subFilter: SUBFILTER_ETSI_CADES_DETACHED,
    appName: "Hiro",
  });
  const prepared = Buffer.from(await pdf.save({useObjectStreams: false}));
  const signer = new P12Signer(Buffer.from(credential.pkcs12Bytes), {
    passphrase: String(credential.passphrase || ""),
  });
  const signedPdf = await new SignPdf().sign(prepared, signer, signingTime);
  const inspection = inspectPdfDigitalSignature(signedPdf);
  if (!inspection.coversWholeDocument || !inspection.hasPadesSubFilter ||
      inspection.signatureBytes.length < 1) {
    throw new Error("The generated PDF digital signature failed verification.");
  }
  return Buffer.from(signedPdf);
}

module.exports = {
  ACCOUNTING_DOCUMENT_TYPES,
  CREDENTIAL_SCHEMA_VERSION,
  decodeMasterKey,
  decryptSigningCredential,
  encryptSigningCredential,
  generateBusinessSigningCredential,
  inspectPdfDigitalSignature,
  isAccountingDocumentType,
  signPdfWithCredential,
};
