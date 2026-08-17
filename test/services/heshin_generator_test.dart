import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/services/heshin_generator.dart';

void main() {
  group('HeshinGenerator', () {
    test('creates a fixed-width customer account record', () {
      final result = HeshinGenerator.generate(
        accounts: const [
          HeshinAccount(
            accountKey: '7952169',
            name: 'לקוח לדוגמה',
            taxId: '777777715',
            phone: '03-1234567',
            mobile: '050-1234567',
            address: 'הרצל 1',
            city: 'תל אביב',
            zipCode: '61000',
            email: 'client@example.com',
            fax: '03-7654321',
            country: 'ישראל',
            bankCode: '10',
            bankBranch: '800',
            bankAccountNumber: '123456',
          ),
        ],
      );

      expect(result.accountCount, 1);
      expect(result.dataBytes.length, HeshinGenerator.recordLengthWithCrlf);
      expect(_ascii(result.dataBytes, 1, 15).trim(), '7952169');
      expect(_ascii(result.dataBytes, 66, 95).trim(), '03-1234567');
      expect(_ascii(result.dataBytes, 166, 170), '61000');
      expect(_ascii(result.dataBytes, 171, 185).trim(), 'Customer');
      expect(_ascii(result.dataBytes, 186, 194), '777777715');
      expect(_ascii(result.dataBytes, 195, 244).trim(), 'client@example.com');
      expect(_ascii(result.dataBytes, 325, 326), '10');
      expect(_ascii(result.dataBytes, 327, 331).trim(), '800');
      expect(_ascii(result.dataBytes, 332, 351).trim(), '123456');
      expect(result.dataBytes.sublist(351), [13, 10]);
    });

    test('creates the matching 69-line HESHIN parameter file', () {
      final result = HeshinGenerator.generate(accounts: const []);
      final text = String.fromCharCodes(result.parameterBytes);

      expect(text.startsWith('353 '), isTrue);
      expect(result.parameterBytes.where((byte) => byte == 10).length, 69);
      expect(text, contains('1 15 '));
      expect(text, contains('186 194 '));
      expect(result.dataBytes, isEmpty);
    });

    test('rejects duplicate accounting card numbers', () {
      const account = HeshinAccount(
        accountKey: '12345',
        name: 'Client',
        taxId: '',
        phone: '',
        mobile: '',
        address: '',
        city: '',
        zipCode: '',
        email: '',
        fax: '',
        country: '',
        bankCode: '',
        bankBranch: '',
        bankAccountNumber: '',
      );

      expect(
        () => HeshinGenerator.generate(accounts: const [account, account]),
        throwsA(isA<HeshinGenerationException>()),
      );
    });
  });
}

String _ascii(List<int> bytes, int start, int end) =>
    String.fromCharCodes(bytes.sublist(start - 1, end));
