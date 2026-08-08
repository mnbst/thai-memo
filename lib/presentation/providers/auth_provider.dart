import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/l10n/l10n_provider.dart';
import '../../l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/local/database_helper.dart';
import '../../services/firebase_auth_service.dart';

// ==================== Auth State ====================

class AuthState {
  final String? displayName;
  final String? email;
  final bool isLoading;

  /// 正規アカウント（Google/Apple）でサインイン済みか。匿名・未認証なら false。
  final bool isLinked;

  const AuthState({
    this.displayName,
    this.email,
    this.isLoading = false,
    this.isLinked = false,
  });

  factory AuthState.fromService(FirebaseAuthService service) {
    return AuthState(
      displayName: service.displayName,
      email: service.email,
      isLinked: service.isLinkedAccount,
    );
  }

  AuthState copyWith({
    String? displayName,
    String? email,
    bool? isLoading,
    bool? isLinked,
  }) {
    return AuthState(
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      isLoading: isLoading ?? this.isLoading,
      isLinked: isLinked ?? this.isLinked,
    );
  }
}

// ==================== Auth Controller ====================

class AuthController extends StateNotifier<AuthState> {
  final FirebaseAuthService _authService;

  /// 文言は言語設定に追従させたいので、値ではなく都度引く関数を持つ。
  final L10n Function() _l10n;

  AuthController(this._authService, this._l10n)
      : super(AuthState.fromService(_authService));

  Future<String?> signInWithGoogle() async {
    state = state.copyWith(isLoading: true);
    try {
      await _authService.signInWithGoogle();
      state = AuthState.fromService(_authService);
      return null;
    } on FirebaseAuthServiceException catch (e) {
      // 例外の message は原因コードを含む診断用。UIには言語に沿った文言を出す。
      debugPrint('auth failed: ${e.message}');
      state = AuthState.fromService(_authService);
      return _l10n().errGoogleSignInFailed;
    } catch (e) {
      state = AuthState.fromService(_authService);
      return _l10n().errGoogleSignInFailed;
    }
  }

  Future<String?> signInWithApple() async {
    state = state.copyWith(isLoading: true);
    try {
      await _authService.signInWithApple();
      state = AuthState.fromService(_authService);
      return null;
    } on FirebaseAuthServiceException catch (e) {
      // 例外の message は原因コードを含む診断用。UIには言語に沿った文言を出す。
      debugPrint('auth failed: ${e.message}');
      state = AuthState.fromService(_authService);
      return _l10n().errAppleSignInFailed;
    } catch (e) {
      state = AuthState.fromService(_authService);
      return _l10n().errAppleSignInFailed;
    }
  }

  /// 匿名ユーザーを Google アカウントに昇格（uid・データ保持）
  Future<String?> linkWithGoogle() async {
    state = state.copyWith(isLoading: true);
    try {
      await _authService.linkWithGoogle();
      state = AuthState.fromService(_authService);
      return null;
    } on FirebaseAuthServiceException catch (e) {
      // 例外の message は原因コードを含む診断用。UIには言語に沿った文言を出す。
      debugPrint('auth failed: ${e.message}');
      state = AuthState.fromService(_authService);
      return _l10n().errGoogleSignInFailed;
    } catch (e) {
      state = AuthState.fromService(_authService);
      return _l10n().errGoogleSignInFailed;
    }
  }

  /// 匿名ユーザーを Apple アカウントに昇格（uid・データ保持）
  Future<String?> linkWithApple() async {
    state = state.copyWith(isLoading: true);
    try {
      await _authService.linkWithApple();
      state = AuthState.fromService(_authService);
      return null;
    } on FirebaseAuthServiceException catch (e) {
      // 例外の message は原因コードを含む診断用。UIには言語に沿った文言を出す。
      debugPrint('auth failed: ${e.message}');
      state = AuthState.fromService(_authService);
      return _l10n().errAppleSignInFailed;
    } catch (e) {
      state = AuthState.fromService(_authService);
      return _l10n().errAppleSignInFailed;
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
      return _l10n().errSignOutFailed;
    }
  }

  Future<String?> deleteAccount() async {
    state = state.copyWith(isLoading: true);
    try {
      await DatabaseHelper.instance.deleteDatabase();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await _authService.deleteAccount();
      state = AuthState.fromService(_authService);
      return null;
    } catch (e) {
      state = AuthState.fromService(_authService);
      return _l10n().errDeleteAccountFailed;
    }
  }
}

// ==================== Provider ====================

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    FirebaseAuthService.instance,
    () => ref.read(l10nProvider),
  );
});
