// =============================================================================
// pass_tier.dart
// 発音練習の到達段階（80点で合格、90点でタイ人レベル）。
//
// 段は画面に出す点数（四捨五入）で決める。89.6 を「90」と見せておきながら
// タイ人レベルにしないと、数字と称号が食い違うため。
// =============================================================================

import 'pronunciation_analyzer.dart';
import 'transcript_match.dart';

/// 合格の下限（この点数以上）。
const int kPassScore = 80;

/// タイ人レベルの下限（この点数以上）。
const int kNativeScore = 90;

enum PassTier { none, pass, native }

PassTier passTierOf(double score) {
  final shown = score.round();
  if (shown >= kNativeScore) return PassTier.native;
  if (shown >= kPassScore) return PassTier.pass;
  return PassTier.none;
}

/// 称号を出してよい結果か。
///
/// 音声認識が使えない端末では点数が声調だけになり、通じたかを見ないぶん
/// 伸びやすい。そこで「タイ人レベル」と言うのは言い過ぎなので出さない。
bool canEarnPassTier(
  PronunciationResult result,
  List<WordRecognition> recognition,
) =>
    result.isScored &&
    !result.isMonotone &&
    recognition.any((r) => r != WordRecognition.unavailable);
