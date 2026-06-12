import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/utils/israeli_id_validator.dart';

void main() {
  group('isValidIsraeliId', () {
    test('accepts valid Israeli identity numbers', () {
      expect(isValidIsraeliId('123456782'), isTrue);
      expect(isValidIsraeliId('039284286'), isTrue);
    });

    test('accepts surrounding whitespace', () {
      expect(isValidIsraeliId(' 123456782 '), isTrue);
    });

    test('rejects an invalid checksum', () {
      expect(isValidIsraeliId('123456789'), isFalse);
    });

    test('rejects values that are not exactly nine digits', () {
      expect(isValidIsraeliId('12345678'), isFalse);
      expect(isValidIsraeliId('12345678a'), isFalse);
    });
  });
}
