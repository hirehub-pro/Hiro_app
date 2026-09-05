"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {cancellationProgress} = require("./cancellation_progress");

test("keeps a source document active after a partial credit", () => {
  assert.deepEqual(cancellationProgress({
    sourceAmount: 10000,
    previousCancelledAmount: 0,
    cancellationAmount: 1000,
  }), {
    cancelledAmount: 1000,
    isFullyCancelled: false,
    cancellationStatus: "partially_cancelled",
  });
});

test("fully cancels only after cumulative credits reach the source total", () => {
  assert.deepEqual(cancellationProgress({
    sourceAmount: 10000,
    previousCancelledAmount: 1000,
    cancellationAmount: 9000,
  }), {
    cancelledAmount: 10000,
    isFullyCancelled: true,
    cancellationStatus: "cancelled",
  });
});

test("caps the cumulative cancelled amount at the source total", () => {
  assert.equal(cancellationProgress({
    sourceAmount: 10000,
    previousCancelledAmount: 9000,
    cancellationAmount: 2000,
  }).cancelledAmount, 10000);
});
