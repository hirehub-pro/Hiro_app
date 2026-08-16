import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/services/movein_generator.dart';

void main() {
  group('MoveinGenerator', () {
    test('creates the Invoice4U fixed-width invoice layout', () {
      final result = MoveinGenerator.generate(
        settings: MoveinAccountingSettings.defaults(),
        documents: const [
          MoveinSourceDocument(
            documentType: 'invoice',
            reference: '10001',
            issueDate: '20260802',
            dueDate: '20260802',
            clientAccountKey: '7952169',
            clientTaxId: '777777715',
            totalAmount: 27652,
            vatAmount: 4218.12,
            allocationNumber: '123456789',
            payments: [],
          ),
        ],
      );

      expect(result.recordCount, 1);
      expect(result.documentBytes.length, 526);
      expect(result.documentBytes.sublist(0, 3), [0xec, 0xe7, 0x20]);
      expect(_ascii(result.documentBytes, 5, 13).trim(), '10001');
      expect(_ascii(result.documentBytes, 25, 34), '02/08/26  ');
      expect(_ascii(result.documentBytes, 104, 118).trim(), '7952169');
      expect(_ascii(result.documentBytes, 136, 150).trim(), '3000');
      expect(_ascii(result.documentBytes, 152, 166).trim(), '2001');
      expect(_ascii(result.documentBytes, 168, 178).trim(), '27652.00');
      expect(_ascii(result.documentBytes, 192, 202).trim(), '23433.88');
      expect(_ascii(result.documentBytes, 204, 214).trim(), '4218.12');
      expect(_ascii(result.documentBytes, 264, 272).trim(), '777777715');
      expect(_ascii(result.documentBytes, 274, 523).trim(), '123456789');
      expect(result.documentBytes.sublist(524), [13, 10]);
    });

    test('creates balanced invoice-receipt and payment records', () {
      final result = MoveinGenerator.generate(
        settings: MoveinAccountingSettings.defaults(),
        documents: const [
          MoveinSourceDocument(
            documentType: 'invoice_receipt',
            reference: '70001',
            issueDate: '20260731',
            dueDate: '20260731',
            clientAccountKey: '7945435',
            clientTaxId: '777777723',
            totalAmount: 5900,
            vatAmount: 900,
            allocationNumber: '',
            payments: [
              MoveinPayment(method: 'cash', amount: 5000),
              MoveinPayment(method: 'cash', amount: 900),
            ],
          ),
        ],
      );

      expect(result.recordCount, 4);
      expect(result.documentBytes.length, 4 * 526);
      expect(_recordAscii(result.documentBytes, 0, 168, 178).trim(), '5900.00');
      expect(_recordAscii(result.documentBytes, 0, 192, 202).trim(), '5000.00');
      expect(_recordAscii(result.documentBytes, 0, 204, 214).trim(), '900.00');
      expect(_recordAscii(result.documentBytes, 1, 104, 118).trim(), '1002');
      expect(_recordAscii(result.documentBytes, 1, 168, 178).trim(), '5000.00');
      expect(_recordAscii(result.documentBytes, 2, 168, 178).trim(), '900.00');
      expect(_recordAscii(result.documentBytes, 3, 136, 150).trim(), '7945435');
      expect(_recordAscii(result.documentBytes, 3, 192, 202).trim(), '5900.00');
    });

    test('creates a PRM with the supplied 526-byte layout', () {
      final result = MoveinGenerator.generate(
        settings: MoveinAccountingSettings.defaults(),
        documents: const [
          MoveinSourceDocument(
            documentType: 'receipt',
            reference: '1',
            issueDate: '20260801',
            dueDate: '20260801',
            clientAccountKey: '4000',
            clientTaxId: '',
            totalAmount: 10,
            vatAmount: 0,
            allocationNumber: '',
            payments: [MoveinPayment(method: 'cash', amount: 10)],
          ),
        ],
      );

      final bytes = result.parameterBytes;
      expect(String.fromCharCodes(bytes.take(4)), '526 ');
      expect(bytes.where((byte) => byte == 10).length, 35);
      expect(
        String.fromCharCodes(bytes.skip(bytes.length - 30)),
        contains('274 523'),
      );
    });
  });
}

String _ascii(List<int> bytes, int start, int end) =>
    String.fromCharCodes(bytes.sublist(start - 1, end));

String _recordAscii(List<int> bytes, int record, int start, int end) {
  final offset = record * MoveinGenerator.recordLengthWithCrlf;
  return String.fromCharCodes(bytes.sublist(offset + start - 1, offset + end));
}
