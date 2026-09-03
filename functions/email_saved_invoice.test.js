"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildInvoiceEmailDeliveries,
} = require("./email_saved_invoice");

test("sends a saved invoice only to the client", () => {
  assert.deepEqual(buildInvoiceEmailDeliveries({
    ownerEmail: "owner@example.com",
    clientEmail: " Client@Example.com ",
    clientName: "Client",
    businessName: "Business",
  }), [{
    email: "client@example.com",
    subjectName: "Business",
    subjectPreposition: "מ",
    type: "client",
  }]);
});

test("does not send to the owner when the client has no valid email", () => {
  assert.deepEqual(buildInvoiceEmailDeliveries({
    ownerEmail: "owner@example.com",
    clientEmail: "not-an-email",
    clientName: "Client",
    businessName: "Business",
  }), []);
  assert.deepEqual(buildInvoiceEmailDeliveries({
    ownerEmail: "owner@example.com",
    clientEmail: null,
    clientName: "Client",
    businessName: "Business",
  }), []);
});

test("still treats a shared owner and client address as a client delivery", () => {
  assert.deepEqual(buildInvoiceEmailDeliveries({
    ownerEmail: "shared@example.com",
    clientEmail: "shared@example.com",
    clientName: "Client",
    businessName: "Business",
  }), [{
    email: "shared@example.com",
    subjectName: "Business",
    subjectPreposition: "מ",
    type: "client",
  }]);
});
