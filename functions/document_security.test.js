"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {ownedInvoicePdfPath} = require("./document_security");

test("accepts an invoice PDF directly inside the owner's folder", () => {
  assert.equal(
      ownedInvoicePdfPath(
          "invoices/alice123/invoice_alice123_123456.pdf",
          "alice123",
      ),
      "invoices/alice123/invoice_alice123_123456.pdf",
  );
});

test("trims a valid owned invoice path", () => {
  assert.equal(
      ownedInvoicePdfPath("  invoices/alice123/quote.pdf  ", "alice123"),
      "invoices/alice123/quote.pdf",
  );
});

test("rejects another user's invoice PDF", () => {
  assert.equal(
      ownedInvoicePdfPath("invoices/bob456/invoice.pdf", "alice123"),
      null,
  );
});

test("rejects nested, non-PDF, URL, empty, and non-string paths", () => {
  const invalidPaths = [
    "invoices/alice123/private/invoice.pdf",
    "invoices/alice123/invoice.exe",
    "https://example.com/invoice.pdf",
    "",
    null,
    12345,
  ];

  for (const invalidPath of invalidPaths) {
    assert.equal(ownedInvoicePdfPath(invalidPath, "alice123"), null);
  }
});
