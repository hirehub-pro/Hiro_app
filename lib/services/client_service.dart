import 'dart:math';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';

class ClientNumberConflictException implements Exception {
  const ClientNumberConflictException();
}

class ClientTaxIdConflictException implements Exception {
  const ClientTaxIdConflictException();
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
    final normalizedTaxId = (clientData['taxId'] ?? '').toString().trim();
    final normalizedClientData = <String, dynamic>{
      ...clientData,
      'taxId': normalizedTaxId,
    };

    // Older clients may predate tax-ID reservations, so check their stored
    // values before relying on the atomic reservation below.
    if (normalizedTaxId.isNotEmpty) {
      final existingClients = await clientsRef
          .where('taxId', isEqualTo: normalizedTaxId)
          .get();
      if (existingClients.docs.any((document) => document.id != clientRef.id)) {
        throw const ClientTaxIdConflictException();
      }
    }

    final newReservationRef = userRef
        .collection('clientNumbers')
        .doc(normalizedNumber);
    final newTaxIdReservationRef = normalizedTaxId.isEmpty
        ? null
        : userRef
              .collection('clientTaxIds')
              .doc(Uri.encodeComponent(normalizedTaxId));

    return database.runTransaction<String>((transaction) async {
      final clientSnapshot = await transaction.get(clientRef);
      final newReservationSnapshot = await transaction.get(newReservationRef);
      final oldTaxId = (clientSnapshot.data()?['taxId'] ?? '')
          .toString()
          .trim();
      final oldTaxIdReservationRef =
          oldTaxId.isNotEmpty && oldTaxId != normalizedTaxId
          ? userRef
                .collection('clientTaxIds')
                .doc(Uri.encodeComponent(oldTaxId))
          : null;
      final newTaxIdReservationSnapshot = newTaxIdReservationRef == null
          ? null
          : await transaction.get(newTaxIdReservationRef);
      final oldTaxIdReservationSnapshot = oldTaxIdReservationRef == null
          ? null
          : await transaction.get(oldTaxIdReservationRef);

      if (newReservationSnapshot.exists &&
          newReservationSnapshot.data()?['clientId'] != clientRef.id) {
        throw const ClientNumberConflictException();
      }
      if (newTaxIdReservationSnapshot?.exists == true &&
          newTaxIdReservationSnapshot?.data()?['clientId'] != clientRef.id) {
        throw const ClientTaxIdConflictException();
      }

      final savedData = <String, dynamic>{
        ...normalizedClientData,
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

      if (newTaxIdReservationRef != null) {
        transaction.set(newTaxIdReservationRef, {
          'clientId': clientRef.id,
          'taxId': normalizedTaxId,
          'updatedAt': FieldValue.serverTimestamp(),
          if (newTaxIdReservationSnapshot?.exists != true)
            'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      if (oldTaxIdReservationRef != null &&
          oldTaxIdReservationSnapshot?.data()?['clientId'] == clientRef.id) {
        transaction.delete(oldTaxIdReservationRef);
      }

      return clientRef.id;
    });
  }

  static Future<String> saveClientWithGeneratedExternalNumber({
    required String userId,
    required Map<String, dynamic> clientData,
    String? clientId,
    FirebaseFirestore? firestore,
    int maxAttempts = 8,
  }) async {
    if (maxAttempts < 1) {
      throw RangeError.range(maxAttempts, 1, null, 'maxAttempts');
    }

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await saveClient(
          userId: userId,
          clientData: clientData,
          externalClientNumber: generateExternalClientNumber(),
          clientId: clientId,
          firestore: firestore,
        );
      } on ClientNumberConflictException {
        if (attempt == maxAttempts - 1) rethrow;
      }
    }

    throw StateError('Could not reserve an external client number.');
  }

  static Future<void> deleteClient({
    required String userId,
    required String clientId,
    FirebaseFirestore? firestore,
  }) async {
    final database = firestore ?? FirebaseFirestore.instance;
    // The client-number reservation is intentionally retained so a number
    // that was assigned once can never be reused by another client.
    final clientRef = database
        .collection('users')
        .doc(userId)
        .collection('clients')
        .doc(clientId);
    final clientSnapshot = await clientRef.get();
    final taxId = (clientSnapshot.data()?['taxId'] ?? '').toString().trim();

    // Delete the client independently. Auxiliary reservation cleanup must not
    // prevent this operation (for example, when older security rules allow
    // deleting clients but not clientTaxIds). Firestore has no foreign-key
    // constraint between saved documents and their client record.
    await clientRef.delete();

    if (taxId.isEmpty) return;
    final taxIdReservationRef = database
        .collection('users')
        .doc(userId)
        .collection('clientTaxIds')
        .doc(Uri.encodeComponent(taxId));
    try {
      await database.runTransaction((transaction) async {
        final reservationSnapshot = await transaction.get(taxIdReservationRef);
        if (reservationSnapshot.data()?['clientId'] == clientId) {
          transaction.delete(taxIdReservationRef);
        }
      });
    } on FirebaseException catch (error, stackTrace) {
      dev.log(
        'Client deleted, but its tax-ID reservation could not be cleaned up.',
        name: 'ClientService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
