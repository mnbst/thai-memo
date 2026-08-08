import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 例文から1問確認クイズへ進む導線の種類。
///
/// v1のA/Bテストは inline カードで確定したため、現在は全端末が
/// [QuizOfferVariant.inlineOneQuestion]。他のvariantは実験を再開するときの
/// 比較対象として残している。実験を再開する場合は、保存キーとanalytics source
/// の双方をv2へ更新して過去の結果と混ぜないこと。
enum QuizOfferVariant {
  controlBottom(
    analyticsSource: 'learning_quiz_control_v1',
    isInline: false,
  ),
  inlineOneQuestion(
    analyticsSource: 'learning_quiz_inline_v1',
    isInline: true,
  ),

  /// 割り当てを決められない場合の安全な表示。
  /// controlと同じUIだが、分析対象の群には含めない。
  unassignedControl(
    analyticsSource: 'learning_quiz_unassigned_v1',
    isInline: false,
    participatesInExperiment: false,
  );

  const QuizOfferVariant({
    required this.analyticsSource,
    required this.isInline,
    this.participatesInExperiment = true,
  });

  final String analyticsSource;
  final bool isInline;
  final bool participatesInExperiment;
}

final quizOfferVariantProvider = FutureProvider<QuizOfferVariant>(
  (ref) async => QuizOfferVariant.inlineOneQuestion,
);
