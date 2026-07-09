import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Service for managing Firebase Authentication
class FirebaseAuthService {
  static final FirebaseAuthService instance = FirebaseAuthService._internal();
  static const String _googleServerClientId =
      '147810088545-4921rt150m9jtjate82nbol5q8hgoj3l.apps.googleusercontent.com';

  factory FirebaseAuthService() => instance;

  FirebaseAuthService._internal();

  /// テスト時に FirebaseAuth を差し替えるためのフック
  @visibleForTesting
  static FirebaseAuth? authOverride;

  FirebaseAuth get _auth => authOverride ?? FirebaseAuth.instance;
  bool _googleSignInInitialized = false;

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Check if user is authenticated
  bool get isAuthenticated => _auth.currentUser != null;

  /// Get display name
  String? get displayName => _auth.currentUser?.displayName;

  /// Get email
  String? get email => _auth.currentUser?.email;

  /// 正規アカウント（匿名でない）でサインイン済みか
  bool get isLinkedAccount =>
      currentUser != null && !currentUser!.isAnonymous;

  /// Ensure user is authenticated (anonymous も許可)
  Future<User> ensureAuthenticated() async {
    final user = currentUser;
    if (user == null) {
      throw FirebaseAuthServiceException('認証が必要です');
    }
    return user;
  }

  /// 匿名サインイン（起動時に自動で呼び、即座に利用開始できるようにする）
  Future<User?> signInAnonymously() async {
    try {
      final result = await _auth.signInAnonymously();
      return result.user;
    } on FirebaseAuthException catch (e) {
      throw FirebaseAuthServiceException('認証に失敗しました: ${e.message}');
    }
  }

  /// Sign in with Google（既存アカウントへのサインイン）
  Future<User?> signInWithGoogle() => _googleAuth(link: false);

  /// 匿名ユーザーを Google アカウントに昇格（uid・データを保持）
  Future<User?> linkWithGoogle() => _googleAuth(link: true);

  Future<User?> _googleAuth({required bool link}) async {
    try {
      await _ensureGoogleSignInInitialized();
      final googleUser = await GoogleSignIn.instance.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: googleUser.authentication.idToken,
      );
      return authenticateWithCredential(credential, link: link);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// Sign in with Apple（既存アカウントへのサインイン）
  Future<User?> signInWithApple() => _appleAuth(link: false);

  /// 匿名ユーザーを Apple アカウントに昇格（uid・データを保持）
  Future<User?> linkWithApple() => _appleAuth(link: true);

  Future<User?> _appleAuth({required bool link}) async {
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

    final user = await authenticateWithCredential(oauthCredential, link: link);

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

  /// credential でサインイン。link=true かつ現ユーザーが匿名なら昇格(link)する。
  @visibleForTesting
  Future<User?> authenticateWithCredential(
    AuthCredential credential, {
    required bool link,
  }) async {
    try {
      final current = _auth.currentUser;
      if (link && current != null && current.isAnonymous) {
        final result = await current.linkWithCredential(credential);
        return result.user;
      }
      final result = await _auth.signInWithCredential(credential);
      return result.user;
    } on FirebaseAuthException catch (e) {
      // 既にその Google/Apple アカウントが存在する場合は、そのアカウントでサインイン
      // （匿名 uid は破棄される）
      if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use') {
        final result = await _auth.signInWithCredential(credential);
        return result.user;
      }
      throw FirebaseAuthServiceException('サインインに失敗しました: ${e.message}');
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      if (_googleSignInInitialized) {
        await GoogleSignIn.instance.signOut();
      }
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
          await _ensureGoogleSignInInitialized();
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

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: _googleServerClientId,
    );
    _googleSignInInitialized = true;
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
