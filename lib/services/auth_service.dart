import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:untitled1/services/notification_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // New unified collection name
  static const String usersCollection = 'users';

  // Ensure user exists in Firestore
  Future<void> ensureUserInDatabase(User? user) async {
    if (user == null || user.isAnonymous) return;

    final doc = await _firestore
        .collection(usersCollection)
        .doc(user.uid)
        .get();

    if (!doc.exists) {
      // Default new users to 'customer' role
      await _firestore.collection(usersCollection).doc(user.uid).set({
        'uid': user.uid,
        'name': "User",
        'phone': user.phoneNumber ?? "",
        'email': user.email ?? "",
        'role': 'customer', // Default role
        'createdAt': FieldValue.serverTimestamp(),
        'profileImageUrl': user.photoURL ?? "",
      });
    }
  }

  // Helper to get user document
  Future<DocumentSnapshot?> getUserDoc(String uid) async {
    final doc = await _firestore.collection(usersCollection).doc(uid).get();
    return doc.exists ? doc : null;
  }

  // Sign Out
  Future<void> signOut() async {
    await NotificationService.removeCurrentDeviceToken();
    await _auth.signOut();
  }
}
