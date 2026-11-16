// =============================================================================
// onboarding_paywall.dart
// 初回のペイウォールを、最初のまとめクイズを終えたあとに一度だけ出す。
//
// 以前は語彙テストの直後（最初の例文より前）に出していたが、何も体験する前に
// 値段を見せることになり、生成まで届かずに閉じる人がいた（2026-11）。
// 1セット読んでまとめクイズを終え「次のセットへ」を押したところで出し、
// 見出しの上にそのクイズの結果を一言添える（スコアが上がった／上がらなかった）。
//
// 初回導線を終えた時点で「保留」を端末に立て、出したら消す。初回導線を
// このビルドより前に済ませた人には立たないので出ない。
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../presentation/providers/remaining_quota_provider.dart';
import '../presentation/screens/paywall_screen.dart';
import '../presentation/screens/quiz_screen.dart';
import 'onboarding_progress_reporter.dart';

const String _pendingKey = 'onboarding_paywall_pending';

/// 初回導線を終えたときに呼ぶ。最初のまとめクイズのあとで出す。
Future<void> markOnboardingPaywallPending() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_pendingKey, true);
}

/// まとめクイズの「次のセットへ」で呼ぶ。保留があれば一度だけ出す。
/// プレミアム（体験中・テスター含む）には出さず、保留だけ消す。
Future<void> maybeShowOnboardingPaywall(
  BuildContext context,
  WidgetRef ref,
) async {
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool(_pendingKey) ?? false)) return;
  await prefs.remove(_pendingKey);
  if (!context.mounted || ref.read(effectivePremiumProvider)) return;

  final gain = await summaryQuizVocabGain(ref);
  if (!context.mounted) return;
  final l10n = L10n.of(context);
  const progress = OnboardingProgressReporter();
  unawaited(progress.mark('paywall_open'));
  await PaywallScreen.show(
    context,
    source: 'onboarding',
    lead: gain > 0 ? l10n.paywallLeadScoreUp(gain) : l10n.paywallLeadFirstSet,
  );
  unawaited(progress.mark('paywall_done'));
}
