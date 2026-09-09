import 'package:cloud_functions/cloud_functions.dart';

class DocumentChatAccessService {
  const DocumentChatAccessService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<String> create({
    required String invoiceDocId,
    required String receiverId,
  }) async {
    final result = await _functions
        .httpsCallable('createDocumentChatAccess')
        .call<Map<String, dynamic>>({
          'invoiceDocId': invoiceDocId,
          'receiverId': receiverId,
        });
    final accessId = result.data['accessId']?.toString().trim() ?? '';
    if (accessId.isEmpty) {
      throw StateError('The document access grant could not be created.');
    }
    return accessId;
  }

  static Future<String> createDownloadUrl(String accessId) async {
    final result = await _functions
        .httpsCallable('createDocumentDownloadSession')
        .call<Map<String, dynamic>>({'accessId': accessId});
    final url = result.data['url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      throw StateError('The temporary document URL could not be created.');
    }
    return url;
  }
}
