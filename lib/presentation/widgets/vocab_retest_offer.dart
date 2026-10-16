import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/vocab_stats_provider.dart';
import '../screens/vocab_test_screen.dart';

/// 30日以上あけて戻ってきた人に、語彙テストの受け直しを勧めるカード。
///
/// 休眠中は日次バッチの P 減衰で境界付近の語が既知から外れ、
/// estimated_vocab が実力より下がる（4か月半の休眠で 58→37 の実例）。
/// 測り直せば測定値が床になり、減衰した語は母数から外れる。
///
/// 受け直しはプレミアム限定（サーバーの canStartVocabTest）なので free には
/// 出さない。free は上限100で頭打ちのため、測っても意味が無い。
/// 間隔（vocabTestInterval = 30日）は休眠が30日以上なら必ず満たすが、
/// 念のため前回受験日も見る。
///
/// 復帰の判定は端末に残した前回表示日で行う。users doc の last_active_at は
/// 復帰後の最初の生成で今日に書き換わるため使えない。再インストール直後は
/// 前回表示日が無いので出さない。
///
/// 開くか閉じるかしたら、次に30日あくまで出さない。計測は coach_mark
/// （id=vocab_retest_offer）の shown / tapped / dismissed に載せる。
class VocabRetestOffer extends ConsumerStatefulWidget {
  const VocabRetestOffer({super.key});

  static const String coachId = 'vocab_retest_offer';
  static const Duration idleThreshold = Duration(days: 30);

  @override
  ConsumerState<VocabRetestOffer> createState() => _VocabRetestOfferState();
}

class _VocabRetestOfferState extends ConsumerState<VocabRetestOffer> {
  bool _pending = false;
  bool _loggedShown = false;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastSeen = prefs.getInt(AppConfig.prefKeyLastTodayVisitAt);
    var pending =
        prefs.getBool(AppConfig.prefKeyVocabRetestOfferPending) ?? false;
    if (lastSeen != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastSeen)) >=
            VocabRetestOffer.idleThreshold) {
      pending = true;
      await prefs.setBool(AppConfig.prefKeyVocabRetestOfferPending, true);
    }
    await prefs.setInt(
        AppConfig.prefKeyLastTodayVisitAt, now.millisecondsSinceEpoch);
    if (pending && mounted) setState(() => _pending = true);
  }

  Future<void> _finish(String action) async {
    setState(() => _pending = false);
    unawaited(ref
        .read(analyticsServiceProvider)
        .logCoachMark(id: VocabRetestOffer.coachId, action: action));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConfig.prefKeyVocabRetestOfferPending, false);
  }

  void _open() {
    unawaited(_finish('tapped'));
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: VocabTestScreen.routeName),
        builder: (context) => VocabTestScreen(
          source: VocabRetestOffer.coachId,
          onFinished: (_) => Navigator.pop(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_pending) return const SizedBox.shrink();
    if (!ref.watch(effectivePremiumProvider)) return const SizedBox.shrink();
    final testedAt = ref.watch(vocabStatsProvider).valueOrNull?.testedAt;
    if (testedAt != null &&
        DateTime.now().difference(testedAt) < VocabRetestOffer.idleThreshold) {
      return const SizedBox.shrink();
    }

    if (!_loggedShown) {
      _loggedShown = true;
      unawaited(ref
          .read(analyticsServiceProvider)
          .logCoachMark(id: VocabRetestOffer.coachId, action: 'shown'));
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = L10n.of(context);

    // 声調ガイドの勧め（ToneGuideOffer）と同じ面・形に揃える。
    return Card(
      key: const ValueKey('vocab_retest_offer'),
      margin: const EdgeInsets.only(top: 12),
      color: colors.secondaryContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
      ),
      child: InkWell(
        onTap: _open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
          child: Row(
            children: [
              const Icon(Icons.insights, size: 22, color: AppColors.jade),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.vocabRetestOfferTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.vocabRetestOfferBody,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSecondaryContainer),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.commonClose,
                icon: const Icon(Icons.close, size: 18),
                color: colors.onSecondaryContainer,
                onPressed: () => _finish('dismissed'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
