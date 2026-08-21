import 'package:cloud_firestore/cloud_firestore.dart';

/// Loads account-controlled fields together with the canonical worker profile.
/// For workers, public profile/contact fields override any legacy copies that
/// may still exist in users/{uid}. Customers continue to use users/{uid}.
class ProfileDocumentService {
  const ProfileDocumentService._();

  static Future<Map<String, dynamic>> load(String uid) async {
    final firestore = FirebaseFirestore.instance;
    Map<String, dynamic> accountData = <String, dynamic>{};
    Map<String, dynamic> publicData = <String, dynamic>{};

    try {
      final accountDoc = await firestore.collection('users').doc(uid).get();
      accountData = accountDoc.data() ?? <String, dynamic>{};
    } on FirebaseException catch (_) {
      // Cross-user account reads are intentionally denied. A visible worker's
      // public document can still supply all profile/contact information.
    }

    try {
      final publicDoc = await firestore
          .collection('publicWorkerProfiles')
          .doc(uid)
          .get();
      publicData = publicDoc.data() ?? <String, dynamic>{};
    } on FirebaseException catch (_) {
      // Customers have no public worker document, and hidden workers are only
      // readable by their owner or an administrator.
    }

    const publicFields = {
      'hideSchedule',
      'description',
      'email',
      'lat',
      'lng',
      'name',
      'optionalPhone',
      'phone',
      'professions',
      'profileImageUrl',
      'spokenLanguages',
      'town',
      'workRadius',
    };
    final isWorker =
        (accountData['role'] ?? publicData['role'] ?? '')
            .toString()
            .toLowerCase() ==
        'worker';
    if (isWorker) {
      accountData.removeWhere((key, _) => publicFields.contains(key));
    }
    if (publicData.isEmpty) return accountData;
    return <String, dynamic>{...accountData, ...publicData};
  }
}
