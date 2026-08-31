import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';
import '../providers/remaining_quota_provider.dart';
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

  /// 文言は言語で変わるので、値ではなく引き方を持つ。
  final String Function(L10n) title;
  final String Function(L10n) body;
}

String _hint1Title(L10n l10n) => l10n.premiumHint1Title;
String _hint1Body(L10n l10n) => l10n.premiumHint1Body;
String _hint2Title(L10n l10n) => l10n.premiumHint2Title;
String _hint2Body(L10n l10n) => l10n.premiumHint2Body;
String _hint3Title(L10n l10n) => l10n.premiumHint3Title;
String _hint3Body(L10n l10n) => l10n.premiumHint3Body;

const List<PremiumPitch> _pitches = [
  PremiumPitch(
    source: 'learning_banner_topic',
    icon: Icons.local_offer_outlined,
    title: _hint1Title,
    body: _hint1Body,
  ),
  PremiumPitch(
    source: 'learning_banner_pronunciation',
    icon: Icons.record_voice_over,
    title: _hint2Title,
    body: _hint2Body,
  ),
  PremiumPitch(
    source: 'learning_banner_volume',
    icon: Icons.all_inclusive,
    title: _hint3Title,
    body: _hint3Body,
  ),
];

/// 訴求軸を均等ランダムで1つ選ぶ。
///
/// 日付や uid から決めると、軸が「その日に来た層」や「特定ユーザー」と結びついて
/// しまい、軸別の反応率を比べられなくなる。表示ごとに独立に引くことで、
/// source 別の CTR がそのまま軸の優劣になる。
PremiumPitch pickPitch(Random random) =>
    _pitches[random.nextInt(_pitches.length)];

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
    final dismissedAtMs = prefs.getInt(AppConfig.prefKeyPremiumHintDismissedAt);
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
    if (!_eligible) return const SizedBox.shrink();

    // お試し期間中は topic_picker のロックも外れているため、訴求すると
    // 「もう使える機能」を勧めることになる。判定が付くまでは出さない
    // （読み込み中に一瞬出して消えるより、遅れて出るほうが目障りでない）。
    final plan = ref.watch(planStatusProvider).valueOrNull;
    if (plan != PlanStatus.free) return const SizedBox.shrink();

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

    // 直下にクイズ導線（primaryContainer のカード）が並ぶため、こちらは
    // surface 系にして主役を譲る。学習の手を止めさせない程度の存在感に留める。
    final onSurface = cs.onSurfaceVariant;

    return Card(
      color: cs.surfaceContainerHighest,
      elevation: 0,
      // 非表示時（SizedBox.shrink）に余白が残らないよう、上マージンをここで持つ
      margin: const EdgeInsets.only(top: 12),
      child: InkWell(
        onTap: () => PaywallBottomSheet.show(context, source: _pitch.source),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Icon(_pitch.icon, size: 18, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pitch.title(L10n.of(context)),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _pitch.body(L10n.of(context)),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: onSurface,
                      ),
                      // 英語の body は日本語より長く、狭い端末で3行になる。
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: onSurface),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                color: onSurface,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                onPressed: _dismiss,
                tooltip: L10n.of(context).commonClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
