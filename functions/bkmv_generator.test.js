"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  RECORD_LENGTHS,
  encodeIso88598,
  generateBkmvPackage,
  mapPaymentDetails,
  sanitizeIso88598Text,
  splitPaymentAmount,
} = require("./bkmv_generator");

function businessContext() {
  return {
    userId: "worker-1",
    businessNumber: "123456782",
    companyNumber: "",
    businessName: "עסק בדיקה",
    street: "רחוב העסק",
    houseNumber: "2",
    city: "תל אביב",
    postalCode: "6100000",
    hasBranches: false,
    branchNumber: "",
    softwareName: "הירו Hiro",
    softwareVersion: "1.2.3",
    softwareRegistrationNumber: "12345678",
    softwareMakerVatNumber: "514123454",
    softwareMakerName: "Hiro Software",
    vatPercent: 18,
  };
}

function invoiceReceiptFixture() {
  const invoiceDocId = "invoice_receipt_2026-0042";
  const paymentMethods = [{
    method: "credit",
    amount: 106.2,
    installments: "3",
    cardName: "CAL",
  }];
  return {
    logs: [{
      id: invoiceDocId,
      path: `users/worker-1/logs/invoice_tax_receipt/files/${invoiceDocId}`,
      data: {
        userId: "worker-1",
        bucket: "invoice_tax_receipt",
        invoiceDocId,
        documentNumber: 42,
        sequenceNumber: 42,
        date: "20260825",
        issueDate: "20260825",
        timestamp: new Date("2026-08-25T10:30:00+03:00"),
        subtotalBeforeTax: 90,
        subtotalAfterTax: 106.2,
        vatAmount: 16.2,
        discountAmount: -10,
        externalClientNumber: "1001",
        clientDetails: {
          id: "515555555",
          name: "לקוח בדיקה",
          address: "הרצל 10, תל אביב, 6100000",
          phone: "+972501234567",
        },
        items: [{
          description: "שירות בדיקה",
          quantity: 2,
          unitPriceWithoutTax: 50,
          discount: -10,
          total: 106.2,
        }],
        paymentMethods,
      },
    }],
    invoicesById: {
      [invoiceDocId]: {
        type: "invoice_receipt",
        invoiceNumber: "2026-0042",
        externalClientNumber: "1001",
        paymentMethods,
        authoritativeServerDocument: {
          docType: "invoice_receipt",
          documentNumber: "2026-0042",
          date: "2026-08-25",
          amountBeforeDiscount: 100,
          discount: 10,
          paymentAmount: 90,
          vatAmount: 16.2,
          beforeRounding: 106.2,
          finalTotal: 106.2,
          client: {
            id: "515555555",
            name: "לקוח בדיקה",
            address: "הרצל 10, תל אביב, 6100000",
            phone: "+972501234567",
            externalClientNumber: "1001",
          },
          items: [{
            description: "שירות בדיקה",
            quantity: 2,
            price_per_unit: 50,
            discount: 10,
            total_amount: 90,
          }],
          paymentMethods,
        },
      },
    },
  };
}

test("generates fixed-width 1.31 records from canonical server documents", () => {
  const fixture = invoiceReceiptFixture();
  const result = generateBkmvPackage({
    context: businessContext(),
    logs: fixture.logs,
    invoicesById: fixture.invoicesById,
    clients: [{
      id: "client-1",
      name: "לקוח בדיקה",
      externalClientNumber: "1001",
      taxId: "515555555",
      address: "הרצל 10, תל אביב, 6100000",
    }],
    fromDate: "2026-08-01",
    toDate: "2026-08-31",
    exportTimestamp: new Date("2026-08-25T14:30:00+03:00"),
    mainId: "123456789012345",
  });

  assert.deepEqual(result.recordCounts, {
    A100: 1,
    B110: 1,
    C100: 1,
    D110: 1,
    D120: 3,
    Z900: 1,
  });
  for (const record of result.records) {
    assert.equal(record.length, RECORD_LENGTHS[record.slice(0, 4)]);
    assert.equal(encodeIso88598(record).length, record.length);
  }
  assert.equal(result.records[0].slice(0, 4), "A100");
  assert.equal(result.records.at(-1).slice(0, 4), "Z900");
  assert.equal(result.logicalExportPath, "OPENFRMT\\12345678.26\\08251430");
  assert.equal(result.iniLines[0].length, 466);
  assert.equal(result.iniLines[0].slice(9, 24), "000000000000008");

  const c100 = result.records.find((record) => record.startsWith("C100"));
  assert.equal(c100.slice(25, 45).trim(), "2026-0042");
  assert.equal(c100.slice(287, 302), "+00000000010000");
  assert.equal(c100.slice(302, 317), "-00000000001000");
  assert.equal(c100.slice(317, 332), "+00000000009000");
  assert.equal(c100.slice(332, 347), "+00000000001620");
  assert.equal(c100.slice(347, 362), "+00000000010620");

  const payments = result.records.filter((record) => record.startsWith("D120"));
  assert.equal(payments.length, 3);
  assert.deepEqual(payments.map((record) => record.slice(103, 118)), [
    "+00000000003540",
    "+00000000003540",
    "+00000000003540",
  ]);
  assert.ok(payments.every((record) => record.slice(118, 119) === "2"));
  assert.ok(payments.every((record) => record.slice(139, 140) === "2"));
});

test("maps check dates, omits transfer bank fields, and separates withholding", () => {
  const mapping = mapPaymentDetails({
    logData: {
      paymentMethods: [
        {
          method: "check",
          amount: 50,
          bank: "12",
          branch: "345",
          account: "67890",
          checkNumber: "111222",
          paymentDate: "2026-09-30",
        },
        {
          method: "transfer",
          amount: 40,
          bank: "99",
          branch: "888",
          account: "777",
        },
        {method: "withholding_tax", amount: 10},
      ],
    },
    invoiceData: {},
    defaultAmount: 100,
  });
  assert.equal(mapping.withholdingAmount, 10);
  assert.deepEqual(mapping.details[0], {
    typeCode: 2,
    amount: 50,
    bankNumber: "12",
    branchNumber: "345",
    accountNumber: "67890",
    chequeNumber: "111222",
    paymentDate: "2026-09-30",
  });
  assert.deepEqual(mapping.details[1], {typeCode: 4, amount: 40});
});

test("maps modern payment methods and every supported clearing company", () => {
  for (const method of ["bit", "paybox", "other"]) {
    const mapping = mapPaymentDetails({
      logData: {paymentMethods: [{method, amount: 50}]},
      invoiceData: {},
      defaultAmount: 50,
    });
    assert.equal(mapping.details.length, 1);
    assert.equal(mapping.details[0].typeCode, 9, method);
  }

  const expectedCodes = new Map([
    ["Isracard", 1],
    ["CAL", 2],
    ["Diners", 3],
    ["American Express", 4],
    ["Leumi Card", 6],
  ]);
  for (const [cardName, expectedCode] of expectedCodes) {
    const mapping = mapPaymentDetails({
      logData: {paymentMethods: [{
        method: "credit",
        amount: 50,
        installments: "1",
        cardName,
      }]},
      invoiceData: {},
      defaultAmount: 50,
    });
    assert.equal(mapping.details.length, 1);
    assert.equal(mapping.details[0].creditCompanyCode, expectedCode, cardName);
  }
});

test("writes receipt withholding only to positive C100 field 1224", () => {
  const invoiceDocId = "receipt_2026-0043";
  const paymentMethods = [
    {method: "cash", amount: 1000},
    {method: "withholding_tax", amount: 250},
  ];
  const stored = {
    type: "receipt",
    invoiceNumber: "2026-0043",
    externalClientNumber: "1001",
    paymentMethods,
    authoritativeServerDocument: {
      docType: "receipt",
      documentNumber: "2026-0043",
      date: "2026-08-25",
      amountBeforeDiscount: 1250,
      discount: 0,
      paymentAmount: 1250,
      vatAmount: 0,
      beforeRounding: 1250,
      finalTotal: 1250,
      paymentMethods,
      client: {
        id: "515555555",
        name: "לקוח בדיקה",
        address: "הרצל 10, תל אביב, 6100000",
        phone: "0501234567",
        externalClientNumber: "1001",
      },
    },
  };
  const result = generateBkmvPackage({
    context: businessContext(),
    logs: [{
      id: invoiceDocId,
      path: `users/worker-1/logs/receipts/files/${invoiceDocId}`,
      data: {
        userId: "worker-1",
        bucket: "receipts",
        invoiceDocId,
        date: "2026-08-25",
        issueDate: "2026-08-25",
        timestamp: new Date("2026-08-25T10:30:00+03:00"),
        subtotalBeforeTax: 1250,
        subtotalAfterTax: 1250,
        vatAmount: 0,
        externalClientNumber: "1001",
        paymentMethods,
      },
    }],
    invoicesById: {[invoiceDocId]: stored},
    clients: [],
    fromDate: "2026-08-01",
    toDate: "2026-08-31",
    exportTimestamp: new Date("2026-08-25T14:30:00+03:00"),
    mainId: "123456789012345",
  });
  const c100 = result.records.find((record) => record.startsWith("C100"));
  assert.equal(c100.slice(287, 302), "+00000000100000");
  assert.equal(c100.slice(317, 332), "+00000000100000");
  assert.equal(c100.slice(347, 362), "+00000000100000");
  assert.equal(c100.slice(362, 374), "+00000025000");
  const payments = result.records.filter((record) => record.startsWith("D120"));
  assert.equal(payments.length, 1);
  assert.equal(payments[0].slice(103, 118), "+00000000100000");
});

test("splits installment cents without changing the payment total", () => {
  assert.deepEqual(splitPaymentAmount(100, 3), [33.34, 33.33, 33.33]);
  assert.equal(splitPaymentAmount(100, 3).reduce((sum, value) => sum + value, 0), 100);
});

test("encodes Hebrew as one ISO-8859-8 byte per fixed-width character", () => {
  const logical = sanitizeIso88598Text("שלום – ₪");
  const encoded = encodeIso88598(logical);
  assert.equal(logical, "שלום - ¤");
  assert.equal(encoded.length, logical.length);
  assert.deepEqual([...encoded.slice(0, 4)], [0xf9, 0xec, 0xe5, 0xed]);
});

test("rejects invalid registration metadata and blank accounting keys", () => {
  const fixture = invoiceReceiptFixture();
  assert.throws(() => generateBkmvPackage({
    context: {...businessContext(), softwareRegistrationNumber: ""},
    logs: fixture.logs,
    invoicesById: fixture.invoicesById,
    clients: [],
    fromDate: "20260801",
    toDate: "20260831",
  }), /registration number/);
  assert.throws(() => generateBkmvPackage({
    context: businessContext(),
    logs: fixture.logs,
    invoicesById: fixture.invoicesById,
    clients: [{id: "bad-client", name: "Missing key", externalClientNumber: ""}],
    fromDate: "20260801",
    toDate: "20260831",
  }), /accounting account key/);
});
