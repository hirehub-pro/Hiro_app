import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/utils/document_chain_cancellation.dart';

void main() {
  test('a partial credit note does not fully cancel the chain', () {
    final progress = DocumentChainCancellation.calculate(
      invoiceTotal: 6900,
      creditNoteAmounts: const [3000],
      recordedCancelledAmounts: const [3000],
    );

    expect(progress.creditedAmount, 3000);
    expect(progress.status, DocumentChainCancellationStatus.partial);
    expect(progress.netInvoiceAmount(6900), 3900);
  });

  test(
    'one or more credit notes must cover the total for full cancellation',
    () {
      final progress = DocumentChainCancellation.calculate(
        invoiceTotal: 6900,
        creditNoteAmounts: const [3000, 3900],
        recordedCancelledAmounts: const [6900],
      );

      expect(progress.creditedAmount, 6900);
      expect(progress.status, DocumentChainCancellationStatus.full);
      expect(progress.netInvoiceAmount(6900), 0);
    },
  );

  test('duplicate stored progress does not double count credit documents', () {
    final progress = DocumentChainCancellation.calculate(
      invoiceTotal: 6900,
      creditNoteAmounts: const [3000],
      recordedCancelledAmounts: const [3000],
    );

    expect(progress.creditedAmount, 3000);
  });
}
