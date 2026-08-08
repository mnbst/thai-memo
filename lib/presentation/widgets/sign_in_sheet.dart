import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../services/firebase_auth_service.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';

/// Google/Apple サインインを促すボトムシート。
///
/// 匿名ユーザーの場合は `linkWith*`（uid・データ保持の昇格）を、
/// それ以外は通常の `signInWith*` を呼ぶ。
/// サインイン（昇格）に成功すると `true` を返す。キャンセル時は `false`。
Future<bool> showSignInSheet(
  BuildContext context, {
  String? title,
  String? message,
}) async {
  final l10n = L10n.of(context);
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SignInSheet(
      title: title ?? l10n.signIn,
      message: message ?? l10n.signInSheetMessage,
    ),
  );
  return result ?? false;
}

class _SignInSheet extends ConsumerWidget {
  const _SignInSheet({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset('assets/appicon.png', width: 80, height: 80),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
            ),
            const SizedBox(height: 24),
            if (authState.isLoading)
              const CircularProgressIndicator()
            else if (Platform.isIOS)
              SizedBox(
                width: double.infinity,
                child: SignInWithAppleButton(
                  onPressed: () => _authenticate(context, ref, apple: true),
                  style: Theme.of(context).brightness == Brightness.dark
                      ? SignInWithAppleButtonStyle.white
                      : SignInWithAppleButtonStyle.black,
                  text: L10n.of(context).signInWithApple,
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _authenticate(context, ref, apple: false),
                  icon: const Icon(Icons.g_mobiledata, size: 24),
                  label: Text(L10n.of(context).signInWithGoogle),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _authenticate(
    BuildContext context,
    WidgetRef ref, {
    required bool apple,
  }) async {
    final notifier = ref.read(authControllerProvider.notifier);
    final isAnonymous =
        FirebaseAuthService.instance.currentUser?.isAnonymous ?? true;

    final String? error;
    if (apple) {
      error = isAnonymous
          ? await notifier.linkWithApple()
          : await notifier.signInWithApple();
    } else {
      error = isAnonymous
          ? await notifier.linkWithGoogle()
          : await notifier.signInWithGoogle();
    }

    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    if (FirebaseAuthService.instance.isLinkedAccount) {
      // サインイン後にサブスク状態を再取得（premium復帰・自動復元）
      unawaited(
        ref.read(subscriptionControllerProvider.notifier).initialize(),
      );
      Navigator.pop(context, true);
    }
  }
}
