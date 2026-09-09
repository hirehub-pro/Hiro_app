import 'package:cloud_functions/cloud_functions.dart';

class DocumentSigningLink {
  const DocumentSigningLink({required this.url, this.accessCode});

  final String url;
  final String? accessCode;

  bool get isProtected => accessCode?.isNotEmpty == true;
}

class DocumentSigningService {
  const DocumentSigningService._();

  static Future<DocumentSigningLink> create({
    required String invoiceDocId,
    required bool secureWithCode,
    String? receiverId,
  }) async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('createDocumentSigningRequest');
    final result = await callable.call(<String, dynamic>{
      'invoiceDocId': invoiceDocId,
      'secureWithCode': secureWithCode,
      if (receiverId?.isNotEmpty == true) 'receiverId': receiverId,
    });
    final data = result.data as Map<Object?, Object?>?;
    final url = data?['url']?.toString().trim() ?? '';
    final accessCode = data?['accessCode']?.toString().trim();
    if (url.isEmpty || (secureWithCode && accessCode?.isNotEmpty != true)) {
      throw StateError('The signing link could not be created.');
    }
    return DocumentSigningLink(url: url, accessCode: accessCode);
  }
}
