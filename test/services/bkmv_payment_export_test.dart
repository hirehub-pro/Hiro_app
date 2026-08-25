import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/services/bkmv_export_service.dart';

void main() {
  group('BKMV payment export', () {
    test('expands credit-card installments and preserves the total', () {
      final mapping = BkmvExportService.mapPaymentDetailsForExport(
        logData: {
          'paymentMethods': [
            {
              'method': 'credit',
              'amount': 100,
              'installments': '3',
              'cardName': 'Visa',
            },
          ],
        },
        invoiceData: const {},
        defaultAmount: 100,
      );

      expect(mapping.details, hasLength(3));
      expect(mapping.details.map((entry) => entry.typeCode), everyElement(3));
      expect(
        mapping.details.map((entry) => entry.creditDealType),
        everyElement(2),
      );
      expect(mapping.details.map((entry) => entry.amount), [
        33.34,
        33.33,
        33.33,
      ]);
      expect(
        mapping.details.fold<double>(0, (sum, entry) => sum + entry.amount),
        closeTo(100, 0.001),
      );
    });

    test('maps Bit, PayBox, and other payments to D120 type 9', () {
      for (final method in ['bit', 'paybox', 'other']) {
        final mapping = BkmvExportService.mapPaymentDetailsForExport(
          logData: {
            'paymentMethods': [
              {'method': method, 'amount': 50},
            ],
          },
          invoiceData: const {},
          defaultAmount: 50,
        );

        expect(mapping.details.single.typeCode, 9, reason: method);
      }
    });

    test('does not place bank-transfer data in check-only D120 fields', () {
      final mapping = BkmvExportService.mapPaymentDetailsForExport(
        logData: {
          'paymentMethods': [
            {
              'method': 'transfer',
              'amount': 1000,
              'bank': '10',
              'branch': '123',
              'account': '456789',
              'paymentDate': '20260825',
            },
          ],
        },
        invoiceData: const {},
        defaultAmount: 1000,
      );

      final detail = mapping.details.single;
      expect(detail.typeCode, 4);
      expect(detail.amount, 1000);
      expect(detail.bankNumber, isEmpty);
      expect(detail.branchNumber, isEmpty);
      expect(detail.accountNumber, isEmpty);
      expect(detail.paymentDate, isEmpty);
    });

    test('maps a stored check due date to D120 field 1311', () {
      final mapping = BkmvExportService.mapPaymentDetailsForExport(
        logData: {
          'paymentMethods': [
            {
              'method': 'check',
              'amount': 1000,
              'checkNumber': '123456',
              'paymentDate': '2026-09-30',
            },
          ],
        },
        invoiceData: const {},
        defaultAmount: 1000,
      );

      final detail = mapping.details.single;
      expect(detail.typeCode, 2);
      expect(detail.chequeNumber, '123456');
      expect(detail.paymentDate, '2026-09-30');
    });

    test('maps stored clearing-company names to D120 field 1313', () {
      final expectedCodes = {
        'Isracard': 1,
        'CAL': 2,
        'Diners': 3,
        'American Express': 4,
        'Leumi Card': 6,
      };

      for (final entry in expectedCodes.entries) {
        final mapping = BkmvExportService.mapPaymentDetailsForExport(
          logData: {
            'paymentMethods': [
              {
                'method': 'credit',
                'amount': 50,
                'cardName': entry.key,
                'installments': '1',
              },
            ],
          },
          invoiceData: const {},
          defaultAmount: 50,
        );

        expect(
          mapping.details.single.creditCompanyCode,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('separates withholding tax from D120 payment rows', () {
      final mapping = BkmvExportService.mapPaymentDetailsForExport(
        logData: {
          'paymentMethods': [
            {'method': 'cash', 'amount': 1000},
            {'method': 'withholding_tax', 'amount': 250},
          ],
        },
        invoiceData: const {},
        defaultAmount: 1250,
      );

      expect(mapping.details, hasLength(1));
      expect(mapping.details.single.typeCode, 1);
      expect(mapping.details.single.amount, 1000);
      expect(mapping.withholdingAmount, 250);
    });
  });
}
