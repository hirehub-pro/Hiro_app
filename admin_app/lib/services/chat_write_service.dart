import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

class ChatWriteService {
  ChatWriteService._();

  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'me-west1',
  );
  static final Random _random = Random.secure();

  static Future<void> ensureRoom({
    required String receiverId,
    required String receiverName,
  }) async {
    await _functions.httpsCallable('ensureChatRoom').call({
      'receiverId': receiverId,
      'receiverName': receiverName,
    });
  }

  static Future<void> send({
    required String receiverId,
    required String type,
    required String message,
    String? requestId,
    String? idempotencyKey,
  }) async {
    final generatedKey =
        '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
    await _functions.httpsCallable('sendChatMessage').call({
      'receiverId': receiverId,
      'type': type,
      'message': message,
      'clientMessageId': idempotencyKey ?? generatedKey,
      'requestId': ?requestId,
    });
  }
}
