import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/database_helper.dart';
import '../../services/fcm_service.dart';
import '../../services/firebase_auth_service.dart';

// ==================== Auth State ====================

class AuthState {
  final String? displayName;
  final String? email;
  final bool isLoading;

  const AuthState({
    this.displayName,
    this.email,
    this.isLoading = false,
  });

  factory AuthState.fromService(FirebaseAuthService service) {
    return AuthState(
      displayName: service.displayName,
      email: service.email,
    );
  }

  AuthState copyWith({
    String? displayName,
    String? email,
    bool? isLoading,
  }) {
    return AuthState(
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// ==================== Auth Controller ====================

class AuthController extends StateNotifier<AuthState> {
  final FirebaseAuthService _authService;

  AuthController(this._authService)
      : super(AuthState.fromService(_authService));

  Future<void> _initializeFcm() async {
    try {
      await FcmService.instance.initialize();
    } catch (_) {}
  }

  Future<String?> signInWithGoogle() async {
    state = state.copyWith(isLoading: true);
    try {
      await _authService.signInWithGoogle();
      state = AuthState.fromService(_authService);
      await _initializeFcm();
      return null;
    } on FirebaseAuthServiceException catch (e) {
      state = AuthState.fromService(_authService);
      return e.message;
    } catch (e) {
      state = AuthState.fromService(_authService);
      return 'Googleサインインに失敗しました';
    }
  }

  Future<String?> signInWithApple() async {
    state = state.copyWith(isLoading: true);
    try {
      await _authService.signInWithApple();
      state = AuthState.fromService(_authService);
      await _initializeFcm();
      return null;
    } on FirebaseAuthServiceException catch (e) {
      state = AuthState.fromService(_authService);
      return e.message;
    } catch (e) {
      state = AuthState.fromService(_authService);
      return 'Appleサインインに失敗しました';
    }
  }

  Future<String?> signOut() async {
    state = state.copyWith(isLoading: true);
    try {
      await _authService.signOut();
      state = AuthState.fromService(_authService);
      return null;
    } catch (e) {
      state = AuthState.fromService(_authService);
      return 'サインアウトに失敗しました';
    }
  }

  Future<String?> deleteAccount() async {
    state = state.copyWith(isLoading: true);
    try {
      await DatabaseHelper.instance.deleteDatabase();
      await _authService.deleteAccount();
      state = AuthState.fromService(_authService);
      return null;
    } catch (e) {
      state = AuthState.fromService(_authService);
      return 'アカウント削除に失敗しました';
    }
  }
}

// ==================== Provider ====================

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(FirebaseAuthService.instance);
});
