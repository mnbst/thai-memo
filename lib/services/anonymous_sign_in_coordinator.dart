import 'dart:async';

import 'package:flutter/foundation.dart';

/// 未認証の間だけサインインする。重複起動を避け、通信失敗は間隔を空けて再試行する。
class AnonymousSignInCoordinator {
  AnonymousSignInCoordinator({
    required this.canSignIn,
    required this.signIn,
    this.retryDelay = const Duration(seconds: 3),
  });

  final bool Function() canSignIn;
  final Future<void> Function() signIn;
  final Duration retryDelay;
  bool _running = false;
  bool _disposed = false;
  Timer? _retry;

  void ensureSignedIn() {
    if (_disposed || _running || _retry != null || !canSignIn()) return;
    _running = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      await signIn();
    } catch (error) {
      debugPrint('Anonymous sign-in failed: $error');
    } finally {
      _running = false;
      if (!_disposed && canSignIn()) {
        _retry = Timer(retryDelay, () {
          _retry = null;
          ensureSignedIn();
        });
      }
    }
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
  }
}
