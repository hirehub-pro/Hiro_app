import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

class ClientNumberConflictException implements Exception {
  const ClientNumberConflictException();
}

class ClientService {
  ClientService._();

  static const String _alphabet = '0123456789';
  static final RegExp _clientNumberPattern = RegExp(r'^\d{1,10}$');

  static String generateExternalClientNumber({int length = 9}) {
    if (length < 1 || length > 10) {
      throw RangeError.range(length, 1, 10, 'length');
    }
    final random = Random.secure();
    return List.generate(
      length,
      (_) => _alphabet[random.nextInt(_alphabet.length)],
    ).join();
  }

  static String normalizeExternalClientNumber(String value) =>
      value.trim().toUpperCase();

  static bool isValidExternalClientNumber(String value) =>
      _clientNumberPattern.hasMatch(normalizeExternalClientNumber(value));

  static Future<String> saveClient({
    required String userId,
    required Map<String, dynamic> clientData,
    required String externalClientNumber,
    String? clientId,
    FirebaseFirestore? firestore,
  }) async {
    final database = firestore ?? FirebaseFirestore.instance;
    final normalizedNumber = normalizeExternalClientNumber(
      externalClientNumber,
    );
    if (!isValidExternalClientNumber(normalizedNumber)) {
      throw const FormatException('Invalid external client number.');
    }

    final userRef = database.collection('users').doc(userId);
    final clientsRef = userRef.collection('clients');
    final clientRef = clientId == null
        ? clientsRef.doc()
        : clientsRef.doc(clientId);
    final newReservationRef = userRef
        .collection('clientNumbers')
        .doc(normalizedNumber);

    return database.runTransaction<String>((transaction) async {
      final clientSnapshot = await transaction.get(clientRef);
      final newReservationSnapshot = await transaction.get(newReservationRef);

      if (newReservationSnapshot.exists &&
          newReservationSnapshot.data()?['clientId'] != clientRef.id) {
        throw const ClientNumberConflictException();
      }

      final savedData = <String, dynamic>{
        ...clientData,
        'externalClientNumber': normalizedNumber,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!clientSnapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
      };
      transaction.set(clientRef, savedData, SetOptions(merge: true));

      transaction.set(newReservationRef, {
        'clientId': clientRef.id,
        'externalClientNumber': normalizedNumber,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!newReservationSnapshot.exists)
          'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return clientRef.id;
    });
  }

  static Future<void> deleteClient({
    required String userId,
    required String clientId,
    FirebaseFirestore? firestore,
  }) async {
    final database = firestore ?? FirebaseFirestore.instance;
    // The client-number reservation is intentionally retained so a number
    // that was assigned once can never be reused by another client.
    await database
        .collection('users')
        .doc(userId)
        .collection('clients')
        .doc(clientId)
        .delete();
  }
}
