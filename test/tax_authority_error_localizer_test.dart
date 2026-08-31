import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/utils/tax_authority_error_localizer.dart';

void main() {
  test('provides a plain-language business ID mismatch message per locale', () {
    final messages = <String>{
      for (final languageCode in const ['en', 'he', 'ar', 'ru', 'am'])
        taxAuthorityBusinessIdMismatchMessage(languageCode),
    };

    expect(messages, hasLength(5));
    for (final message in messages) {
      expect(message, isNotEmpty);
      expect(message, isNot(contains('Reconnect the Tax Authority account')));
    }
  });

  test('falls back to English for an unsupported locale', () {
    expect(
      taxAuthorityBusinessIdMismatchMessage('fr'),
      taxAuthorityBusinessIdMismatchMessage('en'),
    );
  });
}
