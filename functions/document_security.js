"use strict";

/**
 * Returns the canonical invoice PDF path when it is scoped to the owner.
 *
 * Invoice PDFs are stored as a single file directly under invoices/{uid}/.
 * Rejecting nested paths also prevents a caller from smuggling a different
 * storage namespace behind an otherwise valid prefix.
 *
 * @param {unknown} storagePath
 * @param {unknown} userId
 * @return {string|null}
 */
function ownedInvoicePdfPath(storagePath, userId) {
  if (typeof storagePath !== "string" || typeof userId !== "string") {
    return null;
  }

  const path = storagePath.trim();
  const uid = userId.trim();
  if (!path || !uid) return null;

  const prefix = `invoices/${uid}/`;
  if (!path.startsWith(prefix)) return null;

  const fileName = path.slice(prefix.length);
  if (!fileName || fileName.includes("/")) return null;
  if (!fileName.toLowerCase().endsWith(".pdf")) return null;

  return path;
}

module.exports = {ownedInvoicePdfPath};
