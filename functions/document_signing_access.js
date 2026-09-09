"use strict";

const crypto = require("crypto");

const ACCESS_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const ACCESS_CODE_LENGTH = 8;

function normalizeSigningAccessCode(value) {
  return String(value || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
}

function signingAccessCodeHash(code, salt) {
  const normalized = normalizeSigningAccessCode(code);
  if (normalized.length !== ACCESS_CODE_LENGTH || !salt) return "";
  return crypto.scryptSync(normalized, salt, 32).toString("hex");
}

function createSigningAccessCode() {
  let raw = "";
  for (let index = 0; index < ACCESS_CODE_LENGTH; index += 1) {
    raw += ACCESS_CODE_ALPHABET[crypto.randomInt(ACCESS_CODE_ALPHABET.length)];
  }
  const salt = crypto.randomBytes(16).toString("base64url");
  return {
    code: `${raw.slice(0, 4)}-${raw.slice(4)}`,
    salt,
    hash: signingAccessCodeHash(raw, salt),
  };
}

function signingAccessCodeMatches(code, salt, expectedHash) {
  const actualHash = signingAccessCodeHash(code, salt);
  if (!actualHash || !/^[a-f0-9]{64}$/.test(String(expectedHash || ""))) {
    return false;
  }
  return crypto.timingSafeEqual(
      Buffer.from(actualHash, "hex"),
      Buffer.from(expectedHash, "hex"),
  );
}

function signingAccessSessionHash(token) {
  return crypto.createHash("sha256").update(String(token || "")).digest("hex");
}

function signingAccessSessionMatches(token, expectedHash) {
  if (!/^[A-Za-z0-9_-]{43}$/.test(String(token || "")) ||
      !/^[a-f0-9]{64}$/.test(String(expectedHash || ""))) {
    return false;
  }
  return crypto.timingSafeEqual(
      Buffer.from(signingAccessSessionHash(token), "hex"),
      Buffer.from(expectedHash, "hex"),
  );
}

module.exports = {
  createSigningAccessCode,
  normalizeSigningAccessCode,
  signingAccessCodeMatches,
  signingAccessSessionHash,
  signingAccessSessionMatches,
};
