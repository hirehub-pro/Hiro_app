import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/utils/invoice_preview_cache.dart';

void main() {
  test('reuses an unchanged preview regardless of map key order', () {
    final cache = InvoicePreviewCache();
    final createdAt = DateTime.utc(2026, 9, 3, 8);
    final bytes = Uint8List.fromList(<int>[37, 80, 68, 70]);

    cache.store(
      <String, dynamic>{
        'docType': 'invoice',
        'client': <String, dynamic>{'name': 'Client', 'id': '123'},
      },
      bytes,
      now: createdAt,
    );

    expect(
      cache.lookup(<String, dynamic>{
        'client': <String, dynamic>{'id': '123', 'name': 'Client'},
        'docType': 'invoice',
      }, now: createdAt.add(const Duration(minutes: 2))),
      same(bytes),
    );
  });

  test('invalidates the preview when document data changes', () {
    final cache = InvoicePreviewCache();
    final createdAt = DateTime.utc(2026, 9, 3, 8);
    cache.store(
      <String, dynamic>{'amount': 100},
      Uint8List.fromList(<int>[37, 80, 68, 70]),
      now: createdAt,
    );

    expect(
      cache.lookup(<String, dynamic>{
        'amount': 101,
      }, now: createdAt.add(const Duration(minutes: 1))),
      isNull,
    );
  });

  test('expires previews after the configured maximum age', () {
    final cache = InvoicePreviewCache(maxAge: const Duration(minutes: 5));
    final createdAt = DateTime.utc(2026, 9, 3, 8);
    const payload = <String, dynamic>{'docType': 'quote'};
    cache.store(
      payload,
      Uint8List.fromList(<int>[37, 80, 68, 70]),
      now: createdAt,
    );

    expect(
      cache.lookup(payload, now: createdAt.add(const Duration(minutes: 6))),
      isNull,
    );
  });
}
