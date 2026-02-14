import 'package:firebase_auth/firebase_auth.dart';

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

  /// Sign in anonymously
  Future<User?> signInAnonymously() async {
    try {
      final userCredential = await _auth.signInAnonymously();
      return userCredential.user;
    } catch (e) {
      throw FirebaseAuthServiceException('Failed to authenticate: $e');
    }
  }

  /// Ensure user is authenticated (sign in if needed)
  Future<User> ensureAuthenticated() async {
    final user = currentUser;
    if (user != null) {
      return user;
    }

    final newUser = await signInAnonymously();
    if (newUser == null) {
      throw FirebaseAuthServiceException('Failed to authenticate user');
    }

    return newUser;
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw FirebaseAuthServiceException('Failed to sign out: $e');
    }
  }

  /// Listen to auth state changes
  Stream<User?> authStateChanges() {
    return _auth.authStateChanges();
  }
}

/// Custom exception for Firebase Auth Service
class FirebaseAuthServiceException implements Exception {
  final String message;

  FirebaseAuthServiceException(this.message);

  @override
  String toString() => 'FirebaseAuthServiceException: $message';
}
