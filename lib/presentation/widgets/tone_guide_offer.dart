import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';
import '../providers/quiz_provider.dart';
import '../screens/tone_guide_screen.dart';

/// ヒアリングで「声調が難しい」（interview.struggle = tone）と答えた人に、
/// 声調ガイドを1回だけ勧めるカード。
///
/// 初回導線には挟まない。例文を一度も見ていない段階の声調説明は掴みにくく、
/// 最初の例文までの画面も増える。確認クイズを1問解いた後から出すのは、
/// 初回の確認クイズのガイド（coach_mark quiz_offer）と同じ画面で重ねないため。
///
/// 開くか閉じるかしたら二度と出さない。計測は coach_mark（id=tone_guide_offer）
/// の shown / tapped / dismissed に載せる。
class ToneGuideOffer extends ConsumerStatefulWidget {
  const ToneGuideOffer({super.key});

  static const String coachId = 'tone_guide_offer';

  @override
  ConsumerState<ToneGuideOffer> createState() => _ToneGuideOfferState();
}

class _ToneGuideOfferState extends ConsumerState<ToneGuideOffer> {
  bool _eligible = false;
  bool _loggedShown = false;

  @override
  void initState() {
    super.initState();
    _loadEligibility();
  }

  Future<void> _loadEligibility() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConfig.prefKeyToneGuideOfferDone) ?? false) return;
    final struggle =
        prefs.getString('${AppConfig.prefKeyInterviewPrefix}struggle');
    if (struggle != 'tone') return;
    if (mounted) setState(() => _eligible = true);
  }

  Future<void> _finish(String action) async {
    setState(() => _eligible = false);
    unawaited(ref
        .read(analyticsServiceProvider)
        .logCoachMark(id: ToneGuideOffer.coachId, action: action));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConfig.prefKeyToneGuideOfferDone, true);
  }

  void _open() {
    unawaited(_finish('tapped'));
    Navigator.push(
      context,
      CupertinoPageRoute(
        settings: const RouteSettings(name: ToneGuideScreen.routeName),
        builder: (context) => const ToneGuideScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_eligible) return const SizedBox.shrink();
    final answered =
        ref.watch(quizStatsProvider).valueOrNull?.totalAnswered ?? 0;
    if (answered == 0) return const SizedBox.shrink();

    if (!_loggedShown) {
      _loggedShown = true;
      unawaited(ref
          .read(analyticsServiceProvider)
          .logCoachMark(id: ToneGuideOffer.coachId, action: 'shown'));
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = L10n.of(context);

    // 確認クイズの導線（翡翠の罫線）より一段控えめに、面の色で別物と分ける。
    // 非表示時（SizedBox.shrink）に余白が残らないよう、上マージンをここで持つ。
    return Card(
      key: const ValueKey('tone_guide_offer'),
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
              const Icon(Icons.graphic_eq, size: 22, color: AppColors.jade),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.toneGuideOfferTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.toneGuideOfferBody,
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
