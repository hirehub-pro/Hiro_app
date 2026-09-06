typedef ClientLedgerSummaryEntry = ({
  String documentKind,
  int debitAgorot,
  int creditAgorot,
  String reversalOf,
});

class ClientLedgerSummary {
  const ClientLedgerSummary({
    required this.netDebtAgorot,
    required this.netPaymentsAgorot,
  });

  factory ClientLedgerSummary.fromEntries(
    Iterable<ClientLedgerSummaryEntry> entries,
  ) {
    var netDebt = 0;
    var netPayments = 0;

    for (final entry in entries) {
      final isCreditNote = entry.documentKind == 'credit_note';
      final isPaymentReversal = entry.reversalOf.isNotEmpty;

      if (isCreditNote) {
        netDebt -= entry.creditAgorot;
        continue;
      }
      if (isPaymentReversal) {
        netPayments -= entry.debitAgorot;
        continue;
      }

      netDebt += entry.debitAgorot;
      netPayments += entry.creditAgorot;
    }

    return ClientLedgerSummary(
      netDebtAgorot: netDebt,
      netPaymentsAgorot: netPayments,
    );
  }

  final int netDebtAgorot;
  final int netPaymentsAgorot;

  int get outstandingAgorot => netDebtAgorot - netPaymentsAgorot;
}
