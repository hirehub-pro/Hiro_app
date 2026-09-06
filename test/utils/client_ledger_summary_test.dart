import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/utils/client_ledger_summary.dart';

void main() {
  test('cancelled receipts reduce net payments instead of increasing debt', () {
    final summary = ClientLedgerSummary.fromEntries([
      (
        documentKind: 'invoice',
        debitAgorot: 690000,
        creditAgorot: 0,
        reversalOf: '',
      ),
      (
        documentKind: 'receipt',
        debitAgorot: 0,
        creditAgorot: 690000,
        reversalOf: '',
      ),
      (
        documentKind: 'receipt',
        debitAgorot: 300000,
        creditAgorot: 0,
        reversalOf: 'receipt_2009',
      ),
    ]);

    expect(summary.netDebtAgorot, 690000);
    expect(summary.netPaymentsAgorot, 390000);
    expect(summary.outstandingAgorot, 300000);
  });

  test('credit notes reduce net debt instead of increasing payments', () {
    final summary = ClientLedgerSummary.fromEntries([
      (
        documentKind: 'invoice',
        debitAgorot: 990000,
        creditAgorot: 0,
        reversalOf: '',
      ),
      (
        documentKind: 'credit_note',
        debitAgorot: 0,
        creditAgorot: 300000,
        reversalOf: '',
      ),
      (
        documentKind: 'receipt',
        debitAgorot: 0,
        creditAgorot: 200000,
        reversalOf: '',
      ),
    ]);

    expect(summary.netDebtAgorot, 690000);
    expect(summary.netPaymentsAgorot, 200000);
    expect(summary.outstandingAgorot, 490000);
  });
}
