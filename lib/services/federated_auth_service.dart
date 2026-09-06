import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class FederatedAuthSelection {
  const FederatedAuthSelection({
    required this.credential,
    required this.email,
    required this.providerId,
  });

  final AuthCredential credential;
  final String email;
  final String providerId;
}

class FederatedAuthService {
  FederatedAuthService._();

  static Future<void>? _googleInitialization;

  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get usesApple =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static String get methodName => usesApple ? 'apple' : 'google';

  static Future<FederatedAuthSelection> requestCredential() async {
    if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
      return _requestGoogleCredential();
    }
    if (defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb) {
      return _requestAppleCredential();
    }
    throw UnsupportedError(
      'Federated sign-in is unavailable on this platform.',
    );
  }

  static Future<FederatedAuthSelection> _requestGoogleCredential() async {
    final googleSignIn = GoogleSignIn.instance;
    _googleInitialization ??= googleSignIn.initialize();
    await _googleInitialization;

    try {
      final account = await googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Google did not return an ID token.');
      }
      return FederatedAuthSelection(
        credential: GoogleAuthProvider.credential(idToken: idToken),
        email: account.email.trim(),
        providerId: GoogleAuthProvider.PROVIDER_ID,
      );
    } finally {
      // Clear only the Google SDK's local selection so the chooser is shown
      // again next time. This does not sign out Firebase Authentication.
      try {
        await googleSignIn.signOut();
      } catch (error) {
        debugPrint('Could not clear Google account selection: $error');
      }
    }
  }

  static Future<FederatedAuthSelection> _requestAppleCredential() async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
    final identityToken = appleCredential.identityToken;
    if (identityToken == null || identityToken.isEmpty) {
      throw StateError('Apple did not return an identity token.');
    }

    final email =
        appleCredential.email ?? _emailFromIdentityToken(identityToken);
    if (email == null || email.trim().isEmpty) {
      throw StateError('Apple did not return an email address.');
    }

    return FederatedAuthSelection(
      credential: AppleAuthProvider.credentialWithIDToken(
        identityToken,
        rawNonce,
        AppleFullPersonName(
          givenName: appleCredential.givenName,
          familyName: appleCredential.familyName,
        ),
      ),
      email: email.trim(),
      providerId: AppleAuthProvider.PROVIDER_ID,
    );
  }

  static String _generateNonce([int length = 32]) {
    const characters =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
  }

  static String? _emailFromIdentityToken(String identityToken) {
    try {
      final parts = identityToken.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map<String, dynamic>) return null;
      return payload['email'] is String ? payload['email'] as String : null;
    } catch (error) {
      debugPrint('Could not read Apple identity token: $error');
      return null;
    }
  }

  static bool isCancellation(Object error) =>
      error is GoogleSignInException &&
          error.code == GoogleSignInExceptionCode.canceled ||
      error is SignInWithAppleAuthorizationException &&
          error.code == AuthorizationErrorCode.canceled;
}
