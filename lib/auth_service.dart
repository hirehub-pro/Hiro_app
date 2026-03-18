import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Ensure user exists in Firestore (Only for non-anonymous users)
  Future<void> ensureUserInDatabase(User? user) async {
    if (user == null || user.isAnonymous) return; // Don't save if guest

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (!userDoc.exists) {
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': "User",
        'phone': user.phoneNumber ?? "",
        'email': user.email ?? "",
        'userType': 'normal',
        'createdAt': FieldValue.serverTimestamp(),
        'profileImageUrl': user.photoURL ?? "",
      });
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
