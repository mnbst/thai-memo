// =============================================================================
// quick_guide_screen.dart
// 初回起動で出す、使い方の簡易版（1画面）。ヒアリングの後・語彙テストの前。
//
// 全文の使い方ガイド（GuideScreen）は初回に出すと英語で約870語あり、
// 英語の62%・日本語の43%が読まずに飛ばしていた（2026-11-14）。ここでは
// 学習の流れ3段（LearningFlowSteps。使い方ガイドの概要と共用）を見せる。
// 詳しくは全文の使い方ガイドへ案内する。
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';
import '../widgets/learning_flow_steps.dart';
import 'guide_screen.dart';

class QuickGuideScreen extends ConsumerStatefulWidget {
  static const routeName = 'quick_guide';

  const QuickGuideScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<QuickGuideScreen> createState() => _QuickGuideScreenState();
}

class _QuickGuideScreenState extends ConsumerState<QuickGuideScreen> {
  // 計測は全文のガイドと同じ guide イベント・source=first_launch に載せ、
  // 初回導線のファネル（ga4_funnel.py の guide_open）をそのまま使う。
  // 全文か簡易版かはアプリの版で分ける（1.4.33 以降が簡易版）。
  static const _source = 'first_launch';

  @override
  void initState() {
    super.initState();
    unawaited(ref
        .read(analyticsServiceProvider)
        .logGuide(action: 'open', source: _source));
  }

  void _done() {
    unawaited(ref
        .read(analyticsServiceProvider)
        .logGuide(action: 'completed', source: _source));
    widget.onDone();
  }

  void _openFullGuide() {
    unawaited(ref
        .read(analyticsServiceProvider)
        .logGuide(action: 'open_full', source: _source));
    Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: GuideScreen.routeName),
      builder: (_) => const GuideScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    // 戻るは置かない（初回導線の途中）。
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(l10n.quickGuideTitle),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppConfig.screenPadding,
                    8,
                    AppConfig.screenPadding,
                    8,
                  ),
                  children: const [LearningFlowSteps()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConfig.screenPadding,
                  0,
                  AppConfig.screenPadding,
                  AppConfig.screenPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextButton.icon(
                      onPressed: _openFullGuide,
                      icon: const Icon(Icons.menu_book_outlined, size: 18),
                      label: Text(
                        l10n.quickGuideMore,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FilledButton(
                      onPressed: _done,
                      child: Text(l10n.guideStart),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
