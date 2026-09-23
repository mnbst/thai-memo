// =============================================================================
// quiz_question.dart
// 穴埋め・意味4択クイズの問題モデル。
// Cloud Functions (generateQuiz) がGeminiで生成したクイズ問題を表現する。
// 例文の一部を空欄にし、4択から正解を選ぶ形式。
// SRS（間隔反復）による復習間隔(srsInterval)も保持。
// =============================================================================

import '../../core/pronunciation_text.dart';
import 'thai_sentence.dart';

/// クイズ問題モデル
///
/// blankText: 空欄部分を _____ に置換した文
/// choices: 4つの選択肢（正解を含む）
/// correctAnswer: 正解のタイ語テキスト
/// correctAnswerMeaning: 正解単語の日本語の意味
/// srsInterval: SRS復習間隔（日数）
/// quizFormat: cloze_choice（穴埋め）/ meaning_choice（単語→意味）/
///            spelling_choice（読み＋意味→綴り）
/// 綴り4択で見せる分解。Part は音の順（頭子音→母音→末子音→声調）、
/// Glyph は書く順。タイ語は音の順に書かないので両方を使う。
///
/// 綴り4択の部品1つ（頭子音・母音・末子音・声調）。
///
/// role: onset / vowel / coda / tone
/// text: その部品を書くタイ文字。字にならない部品（母音が表記されない綴り・
///       末子音を母音字が兼ねる綴り）と、切り分けられない綴りでは空。
/// sound: 学習者向けの読み。末子音なし・声門閉鎖の頭子音は空。
/// tone: role が tone のときの声調名（mid / low / falling / high / rising）
class SpellingPart {
  final String role;
  final String text;
  final String sound;
  final String tone;

  const SpellingPart({
    required this.role,
    this.text = '',
    this.sound = '',
    this.tone = '',
  });

  factory SpellingPart.fromJson(Map<String, dynamic> json) => SpellingPart(
        role: json['role']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        sound: json['sound']?.toString() ?? '',
        tone: json['tone']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        if (text.isNotEmpty) 'text': text,
        if (sound.isNotEmpty) 'sound': sound,
        if (tone.isNotEmpty) 'tone': tone,
      };

  /// 単体で出すための表記。母音記号・声調記号は土台の子音が無いと
  /// 宙に浮くので、タイ語の辞書と同じように「-」を土台にして添える
  /// （点線の丸 ◌ は端末のタイ語フォントに無く豆腐になる）。
  String get displayText {
    final buffer = StringBuffer();
    int? prev;
    for (final r in text.runes) {
      if (_isCombining(r) && (prev == null || !_isThaiConsonant(prev))) {
        buffer.write('-');
      }
      buffer.writeCharCode(r);
      prev = r;
    }
    return buffer.toString();
  }

  static bool _isCombining(int r) =>
      r == 0x0E31 || (r >= 0x0E34 && r <= 0x0E3A) || (r >= 0x0E47 && r <= 0x0E4E);

  static bool _isThaiConsonant(int r) => r >= 0x0E01 && r <= 0x0E2E;
}

/// 正解の綴りを書く順に切った断片1つ。role は SpellingPart と同じ語。
class SpellingGlyph {
  final String role;
  final String text;

  const SpellingGlyph({required this.role, required this.text});

  factory SpellingGlyph.fromJson(Map<String, dynamic> json) => SpellingGlyph(
        role: json['role']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {'role': role, 'text': text};
}

/// 声調が決まる3要素。頭子音の階級 × 生音/死音 × 声調記号。
///
/// consonantClass: mid / high / low
/// syllable: live（生音）/ dead（死音）
/// mark: 声調記号。無記号は空。
class SpellingToneRule {
  final String consonantClass;
  final String syllable;
  final String mark;

  /// 短母音か。低子音の死音は母音の長短で声調が変わる。
  final bool shortVowel;

  const SpellingToneRule({
    required this.consonantClass,
    required this.syllable,
    this.mark = '',
    this.shortVowel = false,
  });

  factory SpellingToneRule.fromJson(Map<String, dynamic> json) =>
      SpellingToneRule(
        consonantClass: json['class']?.toString() ?? '',
        syllable: json['syllable']?.toString() ?? '',
        mark: json['mark']?.toString() ?? '',
        shortVowel: json['short_vowel'] == true,
      );

  Map<String, dynamic> toJson() => {
        'class': consonantClass,
        'syllable': syllable,
        if (mark.isNotEmpty) 'mark': mark,
        if (shortVowel) 'short_vowel': true,
      };
}

class QuizQuestion {
  static const clozeChoiceFormat = 'cloze_choice';
  static const meaningChoiceFormat = 'meaning_choice';
  static const spellingChoiceFormat = 'spelling_choice';

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
  final String quizFormat;

  /// 綴り4択の答え合わせ用。正解の綴りの部品（音の順）。
  final List<SpellingPart> spellingParts;

  /// 同じ正解を書く順に切った字。部品との対応を色で示すのに使う。
  final List<SpellingGlyph> spellingGlyphs;

  /// 声調が決まる3要素。切り分けられない綴りでは null。
  final SpellingToneRule? spellingToneRule;

  bool get isMeaningChoice => quizFormat == meaningChoiceFormat;

  /// 綴り4択。読みと意味を出題文にして、タイ語の綴りを4択から選ぶ。
  /// ダミー3件はサーバーがその場で作る非語なので、選択肢の発音は付かない。
  bool get isSpellingChoice => quizFormat == spellingChoiceFormat;

  /// 選択肢に実際に入る正解。意味4択でもUVMへ送る語はcorrectAnswerのまま。
  String get correctChoice =>
      isMeaningChoice ? correctAnswerMeaning : correctAnswer;

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
    this.quizFormat = clozeChoiceFormat,
    this.spellingParts = const [],
    this.spellingGlyphs = const [],
    this.spellingToneRule,
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
      quizFormat: json['quiz_format']?.toString() ?? clozeChoiceFormat,
      spellingParts: (json['spelling_parts'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((e) => SpellingPart.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      spellingToneRule: json['spelling_tone_rule'] is Map
          ? SpellingToneRule.fromJson(
              Map<String, dynamic>.from(json['spelling_tone_rule'] as Map))
          : null,
      spellingGlyphs: (json['spelling_glyphs'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((e) => SpellingGlyph.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
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
        'quiz_format': quizFormat,
        if (spellingParts.isNotEmpty)
          'spelling_parts': spellingParts.map((p) => p.toJson()).toList(),
        if (spellingGlyphs.isNotEmpty)
          'spelling_glyphs': spellingGlyphs.map((g) => g.toJson()).toList(),
        if (spellingToneRule != null)
          'spelling_tone_rule': spellingToneRule!.toJson(),
      };
}
