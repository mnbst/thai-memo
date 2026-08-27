// =============================================================================
// quiz_question.dart
// 穴埋めクイズの問題モデル。
// Cloud Functions (generateQuiz) がGeminiで生成したクイズ問題を表現する。
// 例文の一部を空欄にし、4択から正解を選ぶ形式。
// SRS（間隔反復）による復習間隔(srsInterval)も保持。
// =============================================================================

import '../../core/pronunciation_text.dart';
import 'thai_sentence.dart';

/// 穴埋めクイズ問題モデル
///
/// blankText: 空欄部分を _____ に置換した文
/// choices: 4つの選択肢（正解を含む）
/// correctAnswer: 正解のタイ語テキスト
/// correctAnswerMeaning: 正解単語の日本語の意味
/// srsInterval: SRS復習間隔（日数）
class QuizQuestion {
  final String sentenceId;
  final String thaiText;
  final String blankText;
  final String correctAnswer;
  final String correctAnswerMeaning;
  final List<String> choices;
  final List<String> choicePronunciations;
  final String pronunciation;
  final String explanation;
  final int srsInterval;
  final String japaneseTranslation;
  final String sentencePronunciation;
  final String blankSentencePronunciation;
  final List<String> dummyReasons;
  final ThaiSentence? sentenceDetail;

  const QuizQuestion({
    required this.sentenceId,
    required this.thaiText,
    required this.blankText,
    required this.correctAnswer,
    this.correctAnswerMeaning = '',
    required this.choices,
    this.choicePronunciations = const [],
    required this.pronunciation,
    required this.explanation,
    this.srsInterval = 0,
    this.japaneseTranslation = '',
    this.sentencePronunciation = '',
    this.blankSentencePronunciation = '',
    this.dummyReasons = const [],
    this.sentenceDetail,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final sentenceId = json['sentence_id']?.toString() ?? '';
    final sentenceDetailJson = json['sentence_detail'] is Map
        ? Map<String, dynamic>.from(json['sentence_detail'] as Map)
        : null;
    if (sentenceDetailJson != null && sentenceId.isNotEmpty) {
      sentenceDetailJson['id'] ??= sentenceId;
    }
    _normalizeSentenceDetailJson(sentenceDetailJson);

    return QuizQuestion(
      sentenceId: sentenceId,
      thaiText: json['thai_text'] ?? '',
      blankText: json['blank_text'] ?? '',
      correctAnswer: json['correct_answer'] ?? '',
      correctAnswerMeaning: json['correct_answer_meaning'] ?? '',
      choices: (json['choices'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      choicePronunciations: (json['choice_pronunciations'] as List<dynamic>?)
              ?.map((e) => sanitizePronunciation(e.toString()))
              .toList() ??
          [],
      pronunciation: sanitizePronunciation(json['pronunciation'] ?? ''),
      explanation: json['explanation'] ?? '',
      srsInterval: json['srs_interval'] ?? 0,
      japaneseTranslation: json['japanese_translation'] ?? '',
      sentencePronunciation:
          sanitizePronunciation(json['sentence_pronunciation'] ?? ''),
      blankSentencePronunciation:
          sanitizePronunciation(json['blank_sentence_pronunciation'] ?? ''),
      dummyReasons: (json['dummy_reasons'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      sentenceDetail: sentenceDetailJson != null
          ? ThaiSentence.fromJson(sentenceDetailJson)
          : null,
    );
  }

  static void _normalizeSentenceDetailJson(Map<String, dynamic>? json) {
    final wordBreakdown = json?['word_breakdown'];
    if (wordBreakdown is! List) return;

    json!['word_breakdown'] = wordBreakdown.map((entry) {
      if (entry is! Map) return <String, dynamic>{};
      final normalized = Map<String, dynamic>.from(entry);
      final syllables = normalized['syllables'];
      if (syllables is List && syllables.any((syllable) => syllable is! Map)) {
        normalized.remove('syllables');
      }
      return normalized;
    }).where((entry) {
      return (entry['word']?.toString().trim().isNotEmpty ?? false) &&
          (entry['pronunciation']?.toString().trim().isNotEmpty ?? false) &&
          (entry['meaning']?.toString().trim().isNotEmpty ?? false);
    }).toList();
  }

  Map<String, dynamic> toJson() => {
        'sentence_id': sentenceId,
        'thai_text': thaiText,
        'blank_text': blankText,
        'correct_answer': correctAnswer,
        'correct_answer_meaning': correctAnswerMeaning,
        'choices': choices,
        'choice_pronunciations': choicePronunciations,
        'pronunciation': pronunciation,
        'explanation': explanation,
        'srs_interval': srsInterval,
        'japanese_translation': japaneseTranslation,
        'sentence_pronunciation': sentencePronunciation,
        'blank_sentence_pronunciation': blankSentencePronunciation,
        'dummy_reasons': dummyReasons,
        if (sentenceDetail != null) 'sentence_detail': sentenceDetail!.toJson(),
      };
}
