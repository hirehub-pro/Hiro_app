"use strict";

function money(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

function cancellationProgress({
  sourceAmount,
  previousCancelledAmount,
  cancellationAmount,
}) {
  const total = Math.abs(Number(sourceAmount) || 0);
  const previous = Math.max(0, Number(previousCancelledAmount) || 0);
  const added = Math.abs(Number(cancellationAmount) || 0);
  const cancelledAmount = money(total > 0 ?
    Math.min(total, previous + added) : previous + added);
  const isFullyCancelled = total > 0 && cancelledAmount + 0.01 >= total;
  return {
    cancelledAmount,
    isFullyCancelled,
    cancellationStatus: isFullyCancelled ?
      "cancelled" : "partially_cancelled",
  };
}

module.exports = {cancellationProgress};
