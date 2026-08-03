import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/services/client_service.dart';

void main() {
  group('ClientService external client numbers', () {
    test('generates a valid nine-character default', () {
      final value = ClientService.generateExternalClientNumber();

      expect(value, hasLength(9));
      expect(value, matches(RegExp(r'^\d{9}$')));
      expect(ClientService.isValidExternalClientNumber(value), isTrue);
    });

    test('normalizes surrounding whitespace', () {
      expect(ClientService.normalizeExternalClientNumber('  12345  '), '12345');
    });

    test('accepts only one to ten digits', () {
      expect(ClientService.isValidExternalClientNumber('1'), isTrue);
      expect(ClientService.isValidExternalClientNumber('1234567890'), isTrue);
      expect(ClientService.isValidExternalClientNumber(''), isFalse);
      expect(ClientService.isValidExternalClientNumber('12345678901'), isFalse);
      expect(ClientService.isValidExternalClientNumber('ABC123'), isFalse);
    });
  });
}
