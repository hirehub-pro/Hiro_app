import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Keeps the most recent server-generated preview in memory while its input
/// remains unchanged. The cache is deliberately short-lived so server-owned
/// business details can refresh during a long builder session.
class InvoicePreviewCache {
  InvoicePreviewCache({this.maxAge = const Duration(minutes: 10)});

  final Duration maxAge;

  String? _payloadFingerprint;
  Uint8List? _bytes;
  DateTime? _storedAt;

  Uint8List? lookup(Map<String, dynamic> payload, {DateTime? now}) {
    final bytes = _bytes;
    final storedAt = _storedAt;
    if (bytes == null || storedAt == null) return null;

    final checkedAt = now ?? DateTime.now();
    if (checkedAt.difference(storedAt) > maxAge ||
        _payloadFingerprint != fingerprint(payload)) {
      clear();
      return null;
    }
    return bytes;
  }

  void store(Map<String, dynamic> payload, Uint8List bytes, {DateTime? now}) {
    _payloadFingerprint = fingerprint(payload);
    _bytes = bytes;
    _storedAt = now ?? DateTime.now();
  }

  void clear() {
    _payloadFingerprint = null;
    _bytes = null;
    _storedAt = null;
  }

  static String fingerprint(Map<String, dynamic> payload) {
    final canonicalJson = jsonEncode(_canonicalize(payload));
    return sha256.convert(utf8.encode(canonicalJson)).toString();
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) {
      return value.map(_canonicalize).toList(growable: false);
    }
    return value;
  }
}
