import 'dart:math' as math;

enum DocumentChainCancellationStatus { none, partial, full }

class DocumentChainCancellation {
  const DocumentChainCancellation({
    required this.creditedAmount,
    required this.status,
  });

  factory DocumentChainCancellation.calculate({
    required double invoiceTotal,
    required Iterable<double> creditNoteAmounts,
    required Iterable<double> recordedCancelledAmounts,
  }) {
    final creditDocumentsTotal = creditNoteAmounts.fold<double>(
      0,
      (total, amount) => total + amount.abs(),
    );
    final recordedTotal = recordedCancelledAmounts.fold<double>(
      0,
      (total, amount) => total + amount.abs(),
    );
    final creditedAmount = math.max(creditDocumentsTotal, recordedTotal);
    final status = creditedAmount <= 0.005
        ? DocumentChainCancellationStatus.none
        : invoiceTotal > 0 && creditedAmount + 0.01 >= invoiceTotal
        ? DocumentChainCancellationStatus.full
        : DocumentChainCancellationStatus.partial;

    return DocumentChainCancellation(
      creditedAmount: creditedAmount,
      status: status,
    );
  }

  final double creditedAmount;
  final DocumentChainCancellationStatus status;
}
