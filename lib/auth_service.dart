import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Use the singleton instance provided by the package
  final _googleSignIn = GoogleSignIn.instance;
  bool _isGoogleInitialized = false;
  
  final DatabaseReference _dbRef = FirebaseDatabase.instanceFor(
    app: FirebaseAuth.instance.app,
    databaseURL: 'https://hire-hub-fe6c4-default-rtdb.firebaseio.com'
  ).ref();

  // 1. Google Sign In
  Future<User?> signInWithGoogle() async {
    try {
      // Ensure the instance is initialized before use
      if (!_isGoogleInitialized) {
        await _googleSignIn.initialize();
        _isGoogleInitialized = true;
      }

      // In version 7.2.0, signIn() is replaced by authenticate()
      final googleUser = await _googleSignIn.authenticate();
      
      // Obtain the auth details (primarily idToken for Firebase)
      final googleAuth = googleUser.authentication;

      // Create a new credential for Firebase
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        // accessToken is now handled via authorizationClient if needed for Google APIs,
        // but for Firebase Auth, the idToken is usually sufficient.
      );

      final userCredential = await _auth.signInWithCredential(credential);
      await _ensureUserInDatabase(userCredential.user);
      return userCredential.user;
    } catch (e) {
      // Handle cancellation or errors
      if (e is GoogleSignInException && e.code == GoogleSignInExceptionCode.canceled) {
        debugPrint("Google Sign In was canceled by the user.");
      } else {
        debugPrint("Google Sign In Error: $e");
      }
      return null;
    }
  }

  // 2. Facebook Sign In
  Future<User?> signInWithFacebook() async {
    try {
      final LoginResult result = await FacebookAuth.instance.login();
      if (result.status == LoginStatus.success) {
        final OAuthCredential credential = FacebookAuthProvider.credential(result.accessToken!.tokenString);
        final UserCredential userCredential = await _auth.signInWithCredential(credential);
        await _ensureUserInDatabase(userCredential.user);
        return userCredential.user;
      }
      return null;
    } catch (e) {
      debugPrint("Facebook Sign In Error: $e");
      return null;
    }
  }

  // 3. Apple Sign In
  Future<User?> signInWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final OAuthCredential credential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      await _ensureUserInDatabase(userCredential.user);
      return userCredential.user;
    } catch (e) {
      debugPrint("Apple Sign In Error: $e");
      return null;
    }
  }

  // 4. Anonymous Sign In
  Future<User?> signInAnonymously() async {
    try {
      final UserCredential userCredential = await _auth.signInAnonymously();
      await _ensureUserInDatabase(userCredential.user);
      return userCredential.user;
    } catch (e) {
      debugPrint("Anonymous Sign In Error: $e");
      return null;
    }
  }

  // 5. Ensure user exists in Realtime Database
  Future<void> _ensureUserInDatabase(User? user) async {
    if (user == null) return;
    
    final snapshot = await _dbRef.child('users').child(user.uid).get();
    if (!snapshot.exists) {
      await _dbRef.child('users').child(user.uid).set({
        'uid': user.uid,
        'name': user.displayName ?? (user.isAnonymous ? "Guest" : "User"),
        'email': user.email ?? "",
        'userType': 'normal',
        'createdAt': ServerValue.timestamp,
        'isAnonymous': user.isAnonymous,
        'profileImageUrl': user.photoURL ?? "",
      });
    }
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await FacebookAuth.instance.logOut();
    } catch (_) {}
    await _auth.signOut();
  }
}
