import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Service for managing Firebase Authentication
class FirebaseAuthService {
  static final FirebaseAuthService instance = FirebaseAuthService._internal();

  factory FirebaseAuthService() => instance;

  FirebaseAuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Check if user is authenticated
  bool get isAuthenticated => _auth.currentUser != null;

  /// Get display name
  String? get displayName => _auth.currentUser?.displayName;

  /// Get email
  String? get email => _auth.currentUser?.email;

  /// Ensure user is authenticated
  /// Throws if not signed in (anonymous auth is no longer supported)
  Future<User> ensureAuthenticated() async {
    final user = currentUser;
    if (user == null || user.isAnonymous) {
      throw FirebaseAuthServiceException('サインインが必要です');
    }
    return user;
  }

  /// Sign in with Google
  Future<User?> signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn.instance.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: googleUser.authentication.idToken,
      );
      return _signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// Sign in with Apple
  Future<User?> signInWithApple() async {
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
      accessToken: appleCredential.authorizationCode,
    );

    final user = await _signInWithCredential(oauthCredential);

    // Apple only returns name on first sign-in, so update profile if available
    if (user != null && appleCredential.givenName != null) {
      final name =
          '${appleCredential.givenName ?? ''} ${appleCredential.familyName ?? ''}'
              .trim();
      if (name.isNotEmpty) {
        await user.updateDisplayName(name);
        await user.reload();
      }
    }

    return _auth.currentUser;
  }

  /// Sign in with credential
  Future<User?> _signInWithCredential(AuthCredential credential) async {
    try {
      final result = await _auth.signInWithCredential(credential);
      return result.user;
    } on FirebaseAuthException catch (e) {
      throw FirebaseAuthServiceException(
          'サインインに失敗しました: ${e.message}');
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
      await _auth.signOut();
    } catch (e) {
      throw FirebaseAuthServiceException('Failed to sign out: $e');
    }
  }

  /// Delete account (re-authenticates before deletion)
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw FirebaseAuthServiceException('ユーザーが見つかりません');
      }

      // Re-authenticate before deletion
      final providerIds = user.providerData.map((p) => p.providerId).toList();

      if (providerIds.contains('apple.com')) {
        final rawNonce = _generateNonce();
        final nonce = _sha256ofString(rawNonce);
        final appleCredential = await SignInWithApple.getAppleIDCredential(
          scopes: [],
          nonce: nonce,
        );
        final oauthCredential = OAuthProvider('apple.com').credential(
          idToken: appleCredential.identityToken,
          rawNonce: rawNonce,
          accessToken: appleCredential.authorizationCode,
        );
        await user.reauthenticateWithCredential(oauthCredential);
      } else if (providerIds.contains('google.com')) {
        try {
          final googleUser = await GoogleSignIn.instance.authenticate();
          final credential = GoogleAuthProvider.credential(
            idToken: googleUser.authentication.idToken,
          );
          await user.reauthenticateWithCredential(credential);
          await GoogleSignIn.instance.signOut();
        } on GoogleSignInException catch (e) {
          if (e.code == GoogleSignInExceptionCode.canceled) {
            throw FirebaseAuthServiceException('再認証がキャンセルされました');
          }
          rethrow;
        }
      }

      await user.delete();
    } catch (e) {
      if (e is FirebaseAuthServiceException) rethrow;
      throw FirebaseAuthServiceException('アカウント削除に失敗しました: $e');
    }
  }

  /// Listen to auth state changes
  Stream<User?> authStateChanges() {
    return _auth.authStateChanges();
  }

  /// Generate a random nonce for Apple Sign-in
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  /// SHA256 hash for Apple Sign-in nonce
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

/// Custom exception for Firebase Auth Service
class FirebaseAuthServiceException implements Exception {
  final String message;

  FirebaseAuthServiceException(this.message);

  @override
  String toString() => 'FirebaseAuthServiceException: $message';
}
