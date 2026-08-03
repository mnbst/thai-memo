import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../providers/auth_provider.dart';
import 'sign_in_sheet.dart';

/// 匿名ユーザーへ「3日間未使用で学習の進捗が削除される」ことを知らせ、
/// サインインを促すバナー。
///
/// 表示条件:
/// - 未サインイン（匿名）
/// - 初回まとめクイズ完了済み（＝守りたい進捗ができたタイミング）
/// - 閉じてから3日以上経過（初回は無条件）
class SignInReminderBanner extends ConsumerStatefulWidget {
  const SignInReminderBanner({super.key});

  /// 「閉じる」後に再表示するまでの期間。
  ///
  /// サーバー側の削除しきい値（ANON_INACTIVE_DAYS=3）と揃える。これより長いと
  /// 一度閉じたユーザーが警告を再度見ないまま削除されうる。
  static const Duration reshowInterval = Duration(days: 3);

  @override
  ConsumerState<SignInReminderBanner> createState() =>
      _SignInReminderBannerState();
}

class _SignInReminderBannerState extends ConsumerState<SignInReminderBanner> {
  bool _eligible = false;

  @override
  void initState() {
    super.initState();
    _loadEligibility();
  }

  Future<void> _loadEligibility() async {
    final prefs = await SharedPreferences.getInstance();
    final quizCompleted =
        prefs.getBool(AppConfig.prefKeyFirstSummaryQuizCompleted) ?? false;
    if (!quizCompleted) return;

    final dismissedAtMs =
        prefs.getInt(AppConfig.prefKeySignInReminderDismissedAt);
    if (dismissedAtMs != null) {
      final dismissedAt = DateTime.fromMillisecondsSinceEpoch(dismissedAtMs);
      if (DateTime.now().difference(dismissedAt) <
          SignInReminderBanner.reshowInterval) {
        return;
      }
    }

    if (mounted) setState(() => _eligible = true);
  }

  Future<void> _dismiss() async {
    setState(() => _eligible = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      AppConfig.prefKeySignInReminderDismissedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _signIn() async {
    await showSignInSheet(
      context,
      title: '学習の進捗を保護',
      message: 'サインインすると進捗が保存され、機種変更後も学習を続けられます。'
          'サインインしない場合、3日間ご利用がないと学習の進捗は削除されます。',
    );
    // サインイン成功時は isLinked の watch により自動で非表示になる
  }

  @override
  Widget build(BuildContext context) {
    final isLinked =
        ref.watch(authControllerProvider.select((s) => s.isLinked));
    if (!_eligible || isLinked) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.secondaryContainer,
      // 非表示時（SizedBox.shrink）に余白が残らないよう、下マージンをここで持つ
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_off, color: colorScheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '学習データを保護しましょう\nサインインしないと、3日間ご利用がない場合に学習の進捗が削除されます。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                        ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _dismiss,
                  child: const Text('あとで'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: _signIn,
                  child: const Text('サインイン'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
