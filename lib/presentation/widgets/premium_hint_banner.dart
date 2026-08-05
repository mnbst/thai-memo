import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../providers/analytics_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/subscription_provider.dart';
import '../screens/paywall_screen.dart';

/// 例文タブの例文カード直下に常設する、free 向けのプレミアム訴求バナー。
///
/// ペイウォールの導線がこれまで設定画面とクイズ画面配下にしか無く、クイズ画面は
/// ほとんど開かれないため実質「設定を開いた人だけ」が到達できる状態だった。
/// 例文タブはアクティブユーザーのほぼ全員が毎日通るので、ここに置くことで
/// 割り込みなしに目に入るようにする。
///
/// 表示条件:
/// - free（premium には出さない）
/// - プレミアムお試し期間中でない（既に使える機能を「選べます」と訴求しないため）
/// - 閉じてから [reshowInterval] 以上経過（初回は無条件）
class PremiumHintBanner extends ConsumerStatefulWidget {
  const PremiumHintBanner({super.key});

  /// 「×」で閉じた後に再表示するまでの期間。
  ///
  /// 常設バナーなので閉じた直後に出し直すと邪魔になるが、長く隠しすぎるのも効かない。
  /// W1リテンションが2割程度のため、1週間隠すと閉じた人の大半は二度と見ないまま
  /// 離脱する。まだ開いている層に戻ってくる長さとして3日を採る
  /// （SignInReminderBanner と同じ間隔）。
  static const Duration reshowInterval = Duration(days: 3);

  @override
  ConsumerState<PremiumHintBanner> createState() => _PremiumHintBannerState();
}

/// 訴求の1パターン。文言は paywall_screen の比較表と揃えている。
class PremiumPitch {
  const PremiumPitch({
    required this.source,
    required this.icon,
    required this.title,
    required this.body,
  });

  /// tap_paywall / paywall_banner の source。軸ごとの反応率を比較するために分ける。
  final String source;
  final IconData icon;
  final String title;
  final String body;
}

const List<PremiumPitch> _pitches = [
  PremiumPitch(
    source: 'learning_banner_topic',
    icon: Icons.auto_awesome,
    title: 'タイ例文のテーマを選べます',
    body: 'タイドラマ・恋愛・旅行など、学びたいテーマから出題',
  ),
  PremiumPitch(
    source: 'learning_banner_quality',
    icon: Icons.record_voice_over,
    title: 'ネイティブが使う言い回しで学べます',
    body: '教科書的な基礎文から、実際の会話で使われる表現へ',
  ),
  PremiumPitch(
    source: 'learning_banner_vocab',
    icon: Icons.all_inclusive,
    title: '学べる単語数が無制限に',
    body: '基礎100語の先へ。ドラマのセリフも聞き取れるように',
  ),
];

/// 訴求軸を均等ランダムで1つ選ぶ。
///
/// 日付や uid から決めると、軸が「その日に来た層」や「特定ユーザー」と結びついて
/// しまい、軸別の反応率を比べられなくなる。表示ごとに独立に引くことで、
/// source 別の CTR がそのまま軸の優劣になる。
PremiumPitch pickPitch(Random random) => _pitches[random.nextInt(_pitches.length)];

/// 訴求軸の総数（テストと、配分が均等かの確認用）。
int get pitchCount => _pitches.length;

class _PremiumHintBannerState extends ConsumerState<PremiumHintBanner> {
  bool _eligible = false;

  /// shown を二重に送らないためのフラグ。build は再描画のたびに走る。
  bool _impressionLogged = false;

  /// 表示する訴求。build のたびに引き直すと再描画で文面が変わってしまうので、
  /// State の生存期間中は固定する（＝アプリ起動ごとに引き直す）。
  late final PremiumPitch _pitch;

  @override
  void initState() {
    super.initState();
    _pitch = pickPitch(Random());
    _loadEligibility();
  }

  Future<void> _loadEligibility() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissedAtMs =
        prefs.getInt(AppConfig.prefKeyPremiumHintDismissedAt);
    if (dismissedAtMs != null) {
      final dismissedAt = DateTime.fromMillisecondsSinceEpoch(dismissedAtMs);
      if (DateTime.now().difference(dismissedAt) <
          PremiumHintBanner.reshowInterval) {
        return;
      }
    }

    if (mounted) setState(() => _eligible = true);
  }

  Future<void> _dismiss() async {
    setState(() => _eligible = false);
    unawaited(
      ref.read(analyticsServiceProvider).logPaywallBanner(
            action: 'dismissed',
            source: _pitch.source,
          ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      AppConfig.prefKeyPremiumHintDismissedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(isPremiumProvider);
    if (!_eligible || isPremium) return const SizedBox.shrink();

    // お試し期間中は topic_picker のロックも外れているため、訴求すると
    // 「もう使える機能」を勧めることになる。判定が付くまでは出さない
    // （読み込み中に一瞬出して消えるより、遅れて出るほうが目障りでない）。
    final trial = ref.watch(premiumTrialRemainingProvider);
    if (trial.isLoading) return const SizedBox.shrink();
    if ((trial.valueOrNull ?? 0) > 0) return const SizedBox.shrink();

    if (!_impressionLogged) {
      _impressionLogged = true;
      unawaited(
        ref.read(analyticsServiceProvider).logPaywallBanner(
              action: 'shown',
              source: _pitch.source,
            ),
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      color: cs.primaryContainer,
      elevation: 0,
      // 非表示時（SizedBox.shrink）に余白が残らないよう、上マージンをここで持つ
      margin: const EdgeInsets.only(top: 12),
      child: InkWell(
        onTap: () => PaywallBottomSheet.show(context, source: _pitch.source),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_pitch.icon, size: 20, color: cs.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pitch.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _pitch.body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'プレミアムを見る →',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                visualDensity: VisualDensity.compact,
                onPressed: _dismiss,
                tooltip: '閉じる',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
