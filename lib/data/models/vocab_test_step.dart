/// 語彙テストの1往復ぶんの応答（startVocabTest / submitVocabTest）。
///
/// 出題は1段（4問）ずつ返り、答えを送ると次の段か最終結果が返る。
/// 正解はサーバーにしか無いので、採点結果はここに入らない。
class VocabTestStep {
  const VocabTestStep({
    required this.done,
    this.stage = 0,
    this.totalStages = 0,
    this.questions = const [],
    this.vocab = 0,
    this.asked = 0,
    this.freeCapped = false,
  });

  /// 出題が終わったか。真なら vocab が測定結果。
  final bool done;

  /// いま出ている段（0 起点）と全段数。進捗表示に使う。
  final int stage;
  final int totalStages;

  final List<VocabTestQuestion> questions;

  /// 測定した語彙数（done のときだけ意味がある）。
  final int vocab;

  /// 出題した語数。
  final int asked;

  /// free に落ちると上限で切り下がる値か。結果画面の注意書きに使う。
  final bool freeCapped;

  factory VocabTestStep.fromJson(Map<String, dynamic> json) {
    return VocabTestStep(
      done: json['done'] as bool? ?? false,
      stage: (json['stage'] as num?)?.toInt() ?? 0,
      totalStages: (json['total_stages'] as num?)?.toInt() ?? 0,
      questions: (json['questions'] as List<dynamic>? ?? [])
          .map((e) =>
              VocabTestQuestion.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      vocab: (json['vocab'] as num?)?.toInt() ?? 0,
      asked: (json['asked'] as num?)?.toInt() ?? 0,
      freeCapped: json['free_capped'] as bool? ?? false,
    );
  }
}

/// 4択1問。
class VocabTestQuestion {
  const VocabTestQuestion({required this.word, required this.choices});

  final String word;
  final List<String> choices;

  factory VocabTestQuestion.fromJson(Map<String, dynamic> json) {
    return VocabTestQuestion(
      word: json['word'] as String? ?? '',
      choices: (json['choices'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
