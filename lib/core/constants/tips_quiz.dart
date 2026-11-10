import 'dart:math';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/quiz_question.dart';
import '../../l10n/app_localizations.dart';
import 'guide_sections.dart';
import 'pronunciation_guide_sections.dart';
import 'word_order_rules.dart';

// =============================================================================
// tips_quiz.dart
// コツ問題（ガイド出典の4択）のデータと出題の選び方。
//
// まとめクイズが5問に満たない（多くは入門者で、サーバーがセットの本数に
// 合わせて2〜4問にしている）とき、ここから1問だけ足す。端末だけで作り、サーバーの語彙スコア・クイズ統計には入れない。
// 問題の一覧と出典は docs/tips_quiz_questions.md。
// 解説はガイドの本文をそのまま使い、解答から出典の節を開ける。
// =============================================================================

enum TipKind { pronunciation, tone, thaiScript, wordOrder }

/// 出典のガイドと節。section の意味はガイドごとに違う（guide_sections.dart）。
class TipGuideLink {
  final TipKind guide;

  /// 発音: pronunciationSections の添字か pronSymbolsSection。
  /// 声調: ToneGuideSection.index。タイ文字: ThaiScriptGuideSection.index。
  /// 語順: wordOrderRules の添字。
  final int section;

  const TipGuideLink(this.guide, this.section);
}

/// 選択肢1つ。語順の問題だけ読みを添える。
class TipChoice {
  final String text;
  final String reading;

  const TipChoice(this.text, [this.reading = '']);
}

class TipQuizItem {
  final String id;
  final TipKind kind;

  /// 出題カードに出すタイ語（読み付き）。無い問題もある。
  final List<PronWord> words;

  /// 2語を比べる問題か（間に ↔ の印を置く）。
  final bool contrast;

  final String Function(L10n) question;

  /// 選択肢。先頭が正解。表示の順は出題時に混ぜる。
  final List<TipChoice> Function(L10n) choices;

  final String Function(L10n) explanation;
  final TipGuideLink guide;

  const TipQuizItem({
    required this.id,
    required this.kind,
    this.words = const [],
    this.contrast = false,
    required this.question,
    required this.choices,
    required this.explanation,
    required this.guide,
  });
}

List<TipChoice> _split(String pipe) =>
    pipe.split('|').map((c) => TipChoice(c.trim())).toList();

TipQuizItem _pron(
  String id,
  List<PronWord> words,
  String Function(L10n) question,
  String Function(L10n) choices,
  String Function(L10n) explanation,
  int section, {
  bool contrast = false,
}) =>
    TipQuizItem(
      id: id,
      kind: TipKind.pronunciation,
      words: words,
      contrast: contrast,
      question: question,
      choices: (l) => _split(choices(l)),
      explanation: explanation,
      guide: TipGuideLink(TipKind.pronunciation, section),
    );

TipQuizItem _tone(
  String id,
  List<PronWord> words,
  String Function(L10n) question,
  String Function(L10n) choices,
  String Function(L10n) explanation,
  ToneGuideSection section,
) =>
    TipQuizItem(
      id: id,
      kind: TipKind.tone,
      words: words,
      question: question,
      choices: (l) => _split(choices(l)),
      explanation: explanation,
      guide: TipGuideLink(TipKind.tone, section.index),
    );

TipQuizItem _script(
  String id,
  List<PronWord> words,
  String Function(L10n) question,
  String Function(L10n) choices,
  String Function(L10n) explanation,
  TipGuideLink guide,
) =>
    TipQuizItem(
      id: id,
      kind: TipKind.thaiScript,
      words: words,
      question: question,
      choices: (l) => _split(choices(l)),
      explanation: explanation,
      guide: guide,
    );

/// 語順ガイドの例文から作る。正解は例文の並び、誤答は [wrong] の並べ替え。
TipQuizItem _wordOrder(
  String id,
  int rule,
  int example,
  List<List<int>> wrong, {
  String Function(L10n)? question,
}) {
  final ex = wordOrderRules[rule].examples[example];
  TipChoice order(List<int> idx) => TipChoice(
        idx.map((i) => ex.words[i]).join(),
        idx.map((i) => ex.readings[i]).join(' '),
      );
  return TipQuizItem(
    id: id,
    kind: TipKind.wordOrder,
    question:
        question ?? (l) => l.tipQuizWordOrderQuestion(ex.meaning(l).trim()),
    choices: (_) => [
      order(List.generate(ex.words.length, (i) => i)),
      for (final w in wrong) order(w),
    ],
    explanation: (l) => wordOrderRules[rule].body(l),
    guide: TipGuideLink(TipKind.wordOrder, rule),
  );
}

// 発音ガイドの節（pronunciationSections の並び）。
const _asp = 0, _length = 1, _vowel = 2, _final = 3, _casual = 4;

// 語順ガイドの項目（wordOrderRules の並び。キーの番号とは違う）。
const _ruleSvo = 2, // wordOrderRule3: だれが → する → 何を
    _ruleModifier = 3, // Rule4: 名詞を説明する語は後ろ
    _ruleRelative = 4, // Rule11: 名詞 → ที่ → 説明
    _ruleCount = 5, // Rule5: 名詞 → 数 → 類別詞 → この
    _rulePrep = 6, // Rule12: 〜と・〜の上には名詞の前
    _ruleDegree = 7, // Rule13: とても・少しは後ろ
    _ruleCompare = 8, // Rule14: 形容詞 → กว่า → 相手
    _ruleNegation = 9, // Rule6: 否定の ไม่
    _ruleQuestion = 10, // Rule7: 疑問詞は答えが入る場所に
    _ruleAspect = 11, // Rule8: จะ・แล้ว
    _ruleModal = 12, // Rule15: 〜したいは前、できるは後ろ
    _rulePolite = 17; // Rule10: 丁寧の語尾は一番最後

final _pronunciationItems = <TipQuizItem>[
  _pron('P1', const [PronWord('ไก่', 'kài'), PronWord('ไข่', 'khài')],
      (l) => l.tipQuizP1Question, (l) => l.tipQuizP1Choices,
      (l) => l.pronAspBody, _asp,
      contrast: true),
  _pron('P2', const [PronWord('ตา', 'taa'), PronWord('ทา', 'thaa')],
      (l) => l.tipQuizP2Question, (l) => l.tipQuizP2Choices,
      (l) => l.pronAspBody, _asp,
      contrast: true),
  _pron('P3', const [PronWord('เข้า', 'khâw'), PronWord('ข้าว', 'khâaw')],
      (l) => l.tipQuizP3Question, (l) => l.tipQuizP3Choices,
      (l) => l.pronLengthBody, _length,
      contrast: true),
  _pron('P4', const [], (l) => l.tipQuizP4Question, (l) => l.tipQuizP4Choices,
      (l) => l.pronLengthBody, _length),
  _pron('P5', const [PronWord('แดด', 'dɛ̀ɛt')], (l) => l.tipQuizP5Question,
      (l) => l.tipQuizP5Choices, (l) => l.pronVowelBody, _vowel),
  _pron('P6', const [PronWord('มือ', 'mʉʉ')], (l) => l.tipQuizP6Question,
      (l) => l.tipQuizP6Choices, (l) => l.pronVowelBody, _vowel),
  _pron('P7', const [PronWord('นก', 'nók'), PronWord('รถ', 'rót')],
      (l) => l.tipQuizP7Question, (l) => l.tipQuizP7Choices,
      (l) => l.pronFinalBody, _final),
  _pron('P8', const [PronWord('จาน', 'jaan'), PronWord('จาง', 'jaang')],
      (l) => l.tipQuizP8Question, (l) => l.tipQuizP8Choices,
      (l) => l.pronFinalBody, _final,
      contrast: true),
  _pron(
      'P9',
      const [PronWord('เงิน', 'ngən')],
      (l) => l.tipQuizP9Question,
      (l) => l.tipQuizP9Choices,
      (l) => l.pronunciationSegmentNgInitial('เงิน'),
      pronSymbolsSection),
  _pron('P11', const [PronWord('ครับ', 'khráp')], (l) => l.tipQuizP11Question,
      (l) => l.tipQuizP11Choices, (l) => l.pronCasualBody, _casual),
];

final _toneItems = <TipQuizItem>[
  _tone('T1', const [], (l) => l.tipQuizT1Question, (l) => l.tipQuizT1Choices,
      (l) => l.toneGuideIntro, ToneGuideSection.fiveTones),
  _tone('T5', const [], (l) => l.tipQuizT5Question, (l) => l.tipQuizT5Choices,
      (l) => l.thaiScriptToneRule, ToneGuideSection.shiftTable),
  _tone('T6', const [], (l) => l.tipQuizT6Question, (l) => l.tipQuizT6Choices,
      (l) => l.thaiScriptToneRule, ToneGuideSection.shiftTable),
  _tone('T7', const [PronWord('หมา', 'mǎa')], (l) => l.tipQuizT7Question,
      (l) => l.tipQuizT7Choices, (l) => l.toneLeadingHBody,
      ToneGuideSection.consonantClasses),
];

TipGuideLink _scriptLink(ThaiScriptGuideSection s) =>
    TipGuideLink(TipKind.thaiScript, s.index);

final _scriptItems = <TipQuizItem>[
  _script('S1', const [], (l) => l.tipQuizS1Question, (l) => l.tipQuizS1Choices,
      (l) => l.thaiScriptBasicsDirection,
      _scriptLink(ThaiScriptGuideSection.basics)),
  _script('S2', const [], (l) => l.tipQuizS2Question, (l) => l.tipQuizS2Choices,
      (l) => l.thaiScriptBasicsVowelPosition,
      _scriptLink(ThaiScriptGuideSection.vowels)),
  _script(
      'S3',
      const [PronWord('เด็ก', 'dèk')],
      (l) => l.tipQuizS3Question,
      (l) => l.tipQuizS3Choices,
      (l) => l.thaiScriptBasicsVowelPosition,
      _scriptLink(ThaiScriptGuideSection.basics)),
  _script(
      'S4',
      const [PronWord('อา', 'aa')],
      (l) => l.tipQuizS4Question,
      (l) => l.tipQuizS4Choices,
      (l) => l.thaiScriptConsonantCarrierNote,
      _scriptLink(ThaiScriptGuideSection.consonants)),
  _script(
      'S5',
      const [PronWord('จะ', 'jà')],
      (l) => l.tipQuizS5Question,
      (l) => l.tipQuizS5Choices,
      (l) => l.thaiScriptVowelPairsBody,
      _scriptLink(ThaiScriptGuideSection.vowels)),
  // 語末の ด は発音ガイドの「語末の k・t・p」の注記が出典。
  _script(
      'S6',
      const [PronWord('แดด', 'dɛ̀ɛt')],
      (l) => l.tipQuizS6Question,
      (l) => l.tipQuizS6Choices,
      (l) => l.pronFinalNote,
      const TipGuideLink(TipKind.pronunciation, _final)),
  _script('S7', const [], (l) => l.tipQuizS7Question, (l) => l.tipQuizS7Choices,
      (l) => l.thaiScriptToneMarksBody,
      _scriptLink(ThaiScriptGuideSection.toneMarks)),
];

final _wordOrderItems = <TipQuizItem>[
  _wordOrder('W1', _ruleModifier, 0, const [
    [1, 0]
  ]),
  _wordOrder('W3', _ruleSvo, 0, const [
    [0, 2, 1],
    [1, 0, 2],
  ]),
  _wordOrder('W5', _ruleCount, 1, const [
    [3, 0, 1, 2],
    [0, 1, 3, 2],
  ]),
  _wordOrder('W6', _ruleNegation, 0, const [
    [1, 0, 2, 3],
    [0, 2, 3, 1],
  ]),
  _wordOrder(
      'W7',
      _ruleNegation,
      2,
      const [
        [1, 0]
      ],
      question: (l) => l.tipQuizW7Question),
  _wordOrder('W8', _ruleQuestion, 0, const [
    [2, 0, 1]
  ]),
  _wordOrder('W9', _ruleAspect, 1, const [
    [0, 2, 1]
  ]),
  _wordOrder('W10', _rulePrep, 0, const [
    [0, 1, 3, 2]
  ]),
  _wordOrder('W12', _ruleDegree, 0, const [
    [0, 1, 3, 2]
  ]),
  _wordOrder('W13', _ruleCompare, 0, const [
    [0, 2, 3, 1],
    [0, 3, 1, 2],
  ]),
  _wordOrder('W14', _ruleModal, 0, const [
    [0, 2, 3, 1]
  ]),
  _wordOrder('W16', _ruleRelative, 0, const [
    [1, 2, 3, 0]
  ]),
  _wordOrder('W17', _rulePolite, 0, const [
    [0, 2, 1]
  ]),
];

/// 出題順。種類を1問ずつ交互に並べ、続けて同じガイドから出さない。
final List<TipQuizItem> tipQuizItems = () {
  final groups = [
    _pronunciationItems,
    _wordOrderItems,
    _scriptItems,
    _toneItems,
  ];
  final longest = groups.map((g) => g.length).reduce(max);
  return [
    for (var i = 0; i < longest; i++)
      for (final g in groups)
        if (i < g.length) g[i],
  ];
}();

TipQuizItem? tipQuizItemById(String id) {
  for (final item in tipQuizItems) {
    if (item.id == id) return item;
  }
  return null;
}

/// まとめクイズを [size] 問まで埋めるコツ問題を選ぶ。
///
/// 一度出した問題は端末に記録し、全部出し切るまで同じ問題を出さない。
/// 出し切ったら最初から。1回のクイズの中では重ねない。
class TipQuizPicker {
  TipQuizPicker._();

  static const _usedKey = 'tip_quiz_used_ids';

  static Future<List<QuizQuestion>> fill(
    List<QuizQuestion> questions,
    int size, {
    Random? random,
  }) async {
    final missing = size - questions.length;
    if (missing <= 0) return questions;
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getStringList(_usedKey)?.toSet() ?? <String>{};

    final picked = <TipQuizItem>[];
    for (final item in tipQuizItems) {
      if (picked.length >= missing) break;
      if (!used.contains(item.id)) picked.add(item);
    }
    if (picked.length < missing) {
      // 出し切った。記録を空にして頭から（今回選んだ分は除く）。
      used.clear();
      for (final item in tipQuizItems) {
        if (picked.length >= missing) break;
        if (!picked.contains(item)) picked.add(item);
      }
    }
    used.addAll(picked.map((i) => i.id));
    await prefs.setStringList(_usedKey, used.toList());

    final rnd = random ?? Random();
    return [...questions, for (final item in picked) toQuestion(item, rnd)];
  }

  /// 選択肢の数。言語によらず同じ（テストで確かめる）なので、日本語で数える。
  static int choiceCount(TipQuizItem item) =>
      item.choices(lookupL10n(const Locale('ja'))).length;

  static QuizQuestion toQuestion(TipQuizItem item, Random rnd) {
    final count = choiceCount(item);
    final order = List.generate(count, (i) => '$i')..shuffle(rnd);
    return QuizQuestion(
      sentenceId: '',
      thaiText: '',
      blankText: '',
      correctAnswer: '0',
      choices: order,
      pronunciation: '',
      explanation: '',
      quizFormat: QuizQuestion.tipFormat,
      tipId: item.id,
    );
  }
}
