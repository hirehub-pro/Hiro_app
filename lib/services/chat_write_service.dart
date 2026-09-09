import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

class ChatWriteService {
  ChatWriteService._();

  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'me-west1',
  );
  static final Random _random = Random.secure();

  static Future<String> send({
    required String receiverId,
    required String type,
    String? message,
    String? url,
    String? fileUrl,
    String? fileName,
    int? durationSeconds,
    List<Map<String, dynamic>>? mediaItems,
    String? invoiceDocId,
    String? documentAccessId,
    String? requestId,
    String? requestOwnerId,
    String? workerNotificationId,
    bool? isSystem,
    bool? signingRequest,
    String? idempotencyKey,
  }) async {
    final generatedKey =
        '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
    final response = await _functions.httpsCallable('sendChatMessage').call({
      'receiverId': receiverId,
      'type': type,
      'clientMessageId': idempotencyKey ?? generatedKey,
      'message': ?message,
      'url': ?url,
      'fileUrl': ?fileUrl,
      'fileName': ?fileName,
      'durationSeconds': ?durationSeconds,
      'mediaItems': ?mediaItems,
      'invoiceDocId': ?invoiceDocId,
      'documentAccessId': ?documentAccessId,
      'requestId': ?requestId,
      'requestOwnerId': ?requestOwnerId,
      'workerNotificationId': ?workerNotificationId,
      'isSystem': ?isSystem,
      'signingRequest': ?signingRequest,
    });
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['messageId'] as String;
  }

  static Future<void> deleteMessages({
    required String receiverId,
    required List<String> messageIds,
  }) async {
    await _functions.httpsCallable('deleteChatMessages').call<void>({
      'receiverId': receiverId,
      'messageIds': messageIds,
    });
  }
}
