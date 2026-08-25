"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const AdmZip = require("adm-zip");

const {
  buildBusinessContext,
  buildUniformArtifacts,
  normalizeUniformExportRequest,
} = require("./bkmv_export_service");

function sourceFixture() {
  const paymentMethods = [{method: "cash", amount: 118}];
  return {
    context: buildBusinessContext({
      userId: "worker-1",
      userData: {name: "Worker"},
      publicData: {},
      verificationData: {
        status: "approved",
        businessId: "123456782",
        businessName: "עסק בדיקה",
        dealerType: "licensed",
        address: "הרצל 10, תל אביב, 6100000",
      },
      metadata: {
        vatPercent: 18,
        softwareRegistrationNumber: "12345678",
        softwareMakerVatNumber: "514123454",
        softwareMakerName: "Hiro Software",
        minRequiredVersion: "1.2.3",
      },
    }),
    logs: [{
      id: "invoice_receipt_2026-0001",
      path: "users/worker-1/logs/invoice_tax_receipt/files/invoice_receipt_2026-0001",
      data: {
        userId: "worker-1",
        bucket: "invoice_tax_receipt",
        invoiceDocId: "invoice_receipt_2026-0001",
        documentNumber: 1,
        date: "20260825",
        issueDate: "20260825",
        timestamp: new Date("2026-08-25T10:00:00+03:00"),
        subtotalBeforeTax: 100,
        subtotalAfterTax: 118,
        vatAmount: 18,
        externalClientNumber: "1001",
        items: [{description: "Item", quantity: 1,
          unitPriceWithoutTax: 100, discount: 0}],
        paymentMethods,
      },
    }],
    invoicesById: {
      "invoice_receipt_2026-0001": {
        type: "invoice_receipt",
        invoiceNumber: "2026-0001",
        paymentMethods,
        authoritativeServerDocument: {
          docType: "invoice_receipt",
          documentNumber: "2026-0001",
          date: "2026-08-25",
          amountBeforeDiscount: 100,
          discount: 0,
          paymentAmount: 100,
          vatAmount: 18,
          beforeRounding: 118,
          finalTotal: 118,
          paymentMethods,
          client: {
            id: "515555555",
            name: "לקוח",
            address: "הרצל 1, תל אביב",
            phone: "0501234567",
            externalClientNumber: "1001",
          },
        },
      },
    },
    clients: [{
      id: "client-1",
      name: "לקוח",
      externalClientNumber: "1001",
      taxId: "515555555",
      address: "הרצל 1, תל אביב",
    }],
  };
}

test("normalizes the reusable server export request", () => {
  assert.deepEqual(normalizeUniformExportRequest({
    fromDate: "2026-08-01",
    toDate: "2026-08-31",
    recipientEmail: " OWNER@EXAMPLE.COM ",
  }), {
    fromDate: "20260801",
    toDate: "20260831",
    fromDateIso: "2026-08-01",
    toDateIso: "2026-08-31",
    recipientEmail: "owner@example.com",
  });
  assert.throws(() => normalizeUniformExportRequest({
    fromDate: "2026-08-31",
    toDate: "2026-08-01",
    recipientEmail: "owner@example.com",
  }), /date range/);
});

test("requires approved verification and manufacturer metadata", () => {
  assert.throws(() => buildBusinessContext({
    userId: "worker-1",
    userData: {},
    publicData: {},
    verificationData: {status: "pending"},
    metadata: {},
  }), /Approved business verification/);
});

test("builds all server artifacts from one canonical snapshot", async () => {
  const artifacts = await buildUniformArtifacts({
    source: sourceFixture(),
    fromDate: "20260801",
    toDate: "20260831",
    exportTimestamp: new Date("2026-08-25T14:30:00+03:00"),
    mainId: "123456789012345",
  });
  assert.ok(artifacts.files.ini.bytes.length > 466);
  assert.ok(artifacts.files.bkmv.bytes.length > 100);
  assert.ok(artifacts.files.printedSummary.bytes.subarray(0, 4)
      .equals(Buffer.from("%PDF")));
  assert.ok(artifacts.files.annex4.bytes.subarray(0, 4)
      .equals(Buffer.from("%PDF")));
  const outer = new AdmZip(artifacts.files.bundle.bytes);
  assert.ok(outer.getEntry(
      "OPENFRMT/12345678.26/08251430/BKMVDATA.ZIP",
  ));
  assert.match(artifacts.hashes.ini, /^[a-f0-9]{64}$/);
  assert.match(artifacts.hashes.bundle, /^[a-f0-9]{64}$/);
});
