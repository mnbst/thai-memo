// =============================================================================
// guide_screen.dart
// アプリの使い方をまとめた1枚の説明書。
// 初回起動では先頭から全文を読ませ（スキップ可）、以後は設定からいつでも開ける。
// 画面の上に案内を重ねるコーチマークは持たない。読む場所はここ1つに集める。
//
// 並びは 概要 → それぞれの機能の役割 → 操作のしかた。
// 何のためのアプリかを先に置き、次に各機能が何のためにあるかを説明し、
// 最後に実際の手順へ降りる。手順から始めると、押し方は分かっても
// なぜ押すのかが残らない。
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';
import '../widgets/guide_figures.dart';

/// 説明書の1節。見出し＋本文の行。
class _GuideSection {
  const _GuideSection({
    required this.icon,
    required this.title,
    required this.lines,
    this.figure,
    this.figureAfterLine,
  });

  final IconData icon;
  final String title;
  final List<String> lines;

  /// 本文の下に置く図。文で書くと長くなる並び（学習の流れ・カードの構成・
  /// 判定の色）だけ図にする。
  final Widget? figure;

  /// 図を差し込む位置（この番号の行の直後）。指す先が特定の1行なら、
  /// その行の下に置く。null なら本文の最後に置く。
  final int? figureAfterLine;
}

/// 章。見出しの下に節を積む。
class _GuideChapter {
  const _GuideChapter({required this.title, required this.sections});

  final String title;
  final List<_GuideSection> sections;
}

class GuideScreen extends ConsumerStatefulWidget {
  static const routeName = 'guide';

  const GuideScreen({super.key, this.isFirstLaunch = false, this.onDone});

  /// 初回起動の導入として出しているか。
  /// 真なら「スキップ」と最後の「はじめる」を出し、閉じ方を [onDone] に任せる。
  final bool isFirstLaunch;

  final VoidCallback? onDone;

  @override
  ConsumerState<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends ConsumerState<GuideScreen> {
  String get _source => widget.isFirstLaunch ? 'first_launch' : 'settings';

  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(analyticsServiceProvider).logGuide(
            action: 'open',
            source: _source,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.guideTitle),
        // 初回は読み物として出しているだけなので、戻る先を作らない。
        automaticallyImplyLeading: !widget.isFirstLaunch,
        actions: [
          if (widget.isFirstLaunch)
            TextButton(
              onPressed: () => _close(context, skipped: true),
              child: Text(l10n.guideSkip),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppConfig.screenPadding,
            AppConfig.defaultPadding,
            AppConfig.screenPadding,
            AppConfig.screenPadding,
          ),
          children: [
            Text(
              l10n.guideLead,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            for (final chapter in _chapters(l10n)) ...[
              _buildChapterHeading(context, chapter.title),
              for (final section in chapter.sections)
                _buildSection(context, section),
            ],
            const SizedBox(height: 24),
            if (widget.isFirstLaunch)
              FilledButton(
                onPressed: () => _close(context, skipped: false),
                child: Text(l10n.guideStart),
              )
            else
              OutlinedButton(
                onPressed: () => _close(context, skipped: false),
                child: Text(l10n.guideClose),
              ),
          ],
        ),
      ),
    );
  }

  void _close(BuildContext context, {required bool skipped}) {
    unawaited(
      ref.read(analyticsServiceProvider).logGuide(
            action: skipped ? 'skipped' : 'completed',
            source: _source,
          ),
    );
    final onDone = widget.onDone;
    if (onDone != null) {
      onDone();
      return;
    }
    Navigator.of(context).maybePop();
  }

  /// 章の見出し。字だけだと節のカードに埋もれるので、右へ罫線を伸ばす。
  Widget _buildChapterHeading(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 2),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 0.08 * 14,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, _GuideSection section) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppConfig.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    section.icon,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      section.title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < section.lines.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          section.lines[i],
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                if (section.figure != null && section.figureAfterLine == i)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: section.figure,
                  ),
              ],
              if (section.figure != null && section.figureAfterLine == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: section.figure,
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<_GuideChapter> _chapters(L10n l10n) {
    return [
      _GuideChapter(
        title: l10n.guideChapterOverview,
        sections: [
          _GuideSection(
            icon: Icons.auto_awesome,
            title: l10n.guideOverviewTitle,
            lines: [
              l10n.guideOverviewBody1,
              l10n.guideOverviewBody2,
              l10n.guideOverviewSummaryQuiz,
              l10n.guideOverviewBody3,
            ],
            figure: const GuideLoopFigure(),
          ),
        ],
      ),
      _GuideChapter(
        title: l10n.guideChapterRoles,
        sections: [
          _GuideSection(
            icon: Icons.article_outlined,
            title: l10n.guideRoleSentenceTitle,
            lines: [l10n.guideRoleSentenceBody],
          ),
          _GuideSection(
            icon: Icons.record_voice_over,
            title: l10n.guideRoleSoundTitle,
            lines: [l10n.guideRoleSoundBody],
          ),
          _GuideSection(
            icon: Icons.quiz_outlined,
            title: l10n.guideRoleQuizTitle,
            lines: [l10n.guideRoleQuizBody],
          ),
          _GuideSection(
            icon: Icons.trending_up,
            title: l10n.guideRoleScoreTitle,
            lines: [l10n.guideRoleScoreBody],
          ),
          _GuideSection(
            icon: Icons.straighten,
            title: l10n.guideRoleVocabTestTitle,
            lines: [l10n.guideRoleVocabTestBody],
          ),
          _GuideSection(
            icon: Icons.leaderboard_outlined,
            title: l10n.guideRoleRankingTitle,
            lines: [l10n.guideRoleRankingBody],
          ),
          _GuideSection(
            icon: Icons.palette_outlined,
            title: l10n.guideRoleTopicTitle,
            lines: [l10n.guideRoleTopicBody],
          ),
          _GuideSection(
            icon: Icons.notifications_none,
            title: l10n.guideRoleNotificationTitle,
            lines: [l10n.guideRoleNotificationBody],
          ),
          _GuideSection(
            icon: Icons.bolt,
            title: l10n.guideRolePremiumTitle,
            lines: [l10n.guideRolePremiumBody],
            figure: const GuidePlanCompareFigure(),
          ),
        ],
      ),
      _GuideChapter(
        title: l10n.guideChapterHowTo,
        sections: [
          _GuideSection(
            icon: Icons.today_outlined,
            title: l10n.guideHowSentenceTitle,
            lines: [
              l10n.guideHowSentenceStep1,
              l10n.guideHowSentenceStep3,
              l10n.guideHowSentenceStep4,
            ],
            figure: const GuideSentenceCardFigure(),
          ),
          _GuideSection(
            icon: Icons.list_alt,
            title: l10n.guideHowDetailTitle,
            lines: [l10n.guideHowDetailLead],
          ),
          _GuideSection(
            icon: Icons.mic_none,
            title: l10n.guideHowSoundTitle,
            lines: [
              l10n.guideHowSoundStep1,
              l10n.guideHowSoundStep2,
              l10n.guideHowSoundStep3,
            ],
            figure: const GuideVerdictFigure(),
          ),
          _GuideSection(
            icon: Icons.check_circle_outline,
            title: l10n.guideHowQuizTitle,
            lines: [
              l10n.guideHowQuizStep1,
              l10n.guideHowQuizStep2,
              l10n.guideHowQuizStep3,
              l10n.guideHowQuizStep4,
            ],
            figure: const GuideQuizOfferFigure(),
            // 指しているのは1行目の「例文の下の導線」。最後に置くと、
            // どの話の図なのか分からなくなる。
            figureAfterLine: 0,
          ),
          _GuideSection(
            icon: Icons.settings_outlined,
            title: l10n.guideHowSettingsTitle,
            lines: [
              l10n.guideHowSettingsStep1,
              l10n.guideHowSettingsStep2,
              l10n.guideHowSettingsStep3,
            ],
          ),
        ],
      ),
    ];
  }
}
