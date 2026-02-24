/// FCMから届く穴埋めクイズ問題モデル
class QuizQuestion {
  final String sentenceId;
  final String thaiText;
  final String blankText;
  final String correctAnswer;
  final List<String> choices;
  final String pronunciation;
  final String explanation;
  final int srsInterval;
  final String japaneseTranslation;
  final String sentencePronunciation;

  const QuizQuestion({
    required this.sentenceId,
    required this.thaiText,
    required this.blankText,
    required this.correctAnswer,
    required this.choices,
    required this.pronunciation,
    required this.explanation,
    this.srsInterval = 0,
    this.japaneseTranslation = '',
    this.sentencePronunciation = '',
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
        sentenceId: json['sentence_id'] ?? '',
        thaiText: json['thai_text'] ?? '',
        blankText: json['blank_text'] ?? '',
        correctAnswer: json['correct_answer'] ?? '',
        choices: (json['choices'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        pronunciation: json['pronunciation'] ?? '',
        explanation: json['explanation'] ?? '',
        srsInterval: json['srs_interval'] ?? 0,
        japaneseTranslation: json['japanese_translation'] ?? '',
        sentencePronunciation: json['sentence_pronunciation'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'sentence_id': sentenceId,
        'thai_text': thaiText,
        'blank_text': blankText,
        'correct_answer': correctAnswer,
        'choices': choices,
        'pronunciation': pronunciation,
        'explanation': explanation,
        'srs_interval': srsInterval,
        'japanese_translation': japaneseTranslation,
        'sentence_pronunciation': sentencePronunciation,
      };
}
