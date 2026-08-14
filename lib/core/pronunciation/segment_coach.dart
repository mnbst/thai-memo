// =============================================================================
// segment_coach.dart
// 通じなかった語について、子音・母音の直し方を1つだけ選ぶ。
//
// 音声認識は「通じたか」しか返さないので、**どの音を外したかは分からない**。
// 分からないものを名指しはできないが、日本語話者が外す音は偏っているので、
// その語に含まれる音のうち**いちばん外しやすいもの**を1つ出す。
//
// 優先順位は「日本語話者の癖」の強さで決める（[kSegmentPriority]）。当てずっぽうを
// 並べても直せないので、順位の高いものが1つ見つかったらそこで打ち切る。
//
// 声調（ピッチ）は測って判定しているので、**声調の助言のほうが常に優先**
// （[coachingTipOf]）。ここが出るのは声調が合っているのに通じなかった語だけ。
// =============================================================================

import '../thai_tone_analyzer.dart';

/// 助言の対象になる音節（判定に要る最小限）。
///
/// [Syllable]（data 層）をそのまま受け取らない。core は data を参照しない。
class SegmentSyllable {
  const SegmentSyllable({
    required this.text,
    required this.initialConsonant,
    required this.hasShortVowel,
  });

  /// 音節のタイ文字。
  final String text;

  /// 頭子音（1文字）。二重子音の2文字目は含まない。
  final String initialConsonant;

  /// 短母音か（声調規則の上での生死ではなく、実際の長さ）。
  final bool hasShortVowel;
}

/// 何を直すか。
enum SegmentIssue {
  /// 無気音（ก ต ป จ）を息を出さずに出す。
  unaspirated,

  /// 末子音の閉鎖音（-p -t -k）を破裂させずに止める。
  finalStop,

  /// 語頭の ง。
  ngInitial,

  /// 末子音の鼻音（-ng -n -m）の区別。
  finalNasal,

  /// 母音を短く切る。
  shortVowel,

  /// 日本語に無い母音。
  thaiVowel,
}

/// 助言の優先順位。**上から順に探して、最初に見つかったものを出す。**
///
/// 通じなくなる度合いで並べる。日本語話者の癖のうち、
///   1. 無気音の有気化は**別の子音に聞こえる**（ปา が พา になる）。癖として最も強い
///   2. 末子音の破裂・母音の付加は、音節が1つ増えて別の語になる
///   3. 語頭の ง は日本語に無い位置の音で、母音を入れてしまうと語が変わる
///   4. 鼻音の末子音は「ん」1つに潰れる（-ng と -n の対立が消える）
///   5. 母音の長短は対立だが、長短だけの違いなら文脈で通じることがある
///   6. 母音の音色は幅があり、多少ずれても通じやすい
const List<SegmentIssue> kSegmentPriority = [
  SegmentIssue.unaspirated,
  SegmentIssue.finalStop,
  SegmentIssue.ngInitial,
  SegmentIssue.finalNasal,
  SegmentIssue.shortVowel,
  SegmentIssue.thaiVowel,
];

/// 息を出さない子音と、息が漏れたときに聞こえる子音。
///
/// 日本語のカ・タ・パ行は息が出る（有気）ので、そのまま当てると有気音の側に
/// 聞こえる。**有声の บ ด は入れない**（日本語のバ・ダがそのまま当たる）。
const Map<String, String> kUnaspiratedPairs = {
  'ก': 'ค',
  'จ': 'ช',
  'ต': 'ท',
  'ฏ': 'ท',
  'ป': 'พ',
};

/// 末子音の閉鎖音（-p -t -k）。
const Map<String, String> kFinalStopSounds = {
  'บ': 'p', 'ป': 'p', 'พ': 'p', 'ฟ': 'p', 'ภ': 'p',
  'ด': 't', 'ต': 't', 'ถ': 't', 'ท': 't', 'ธ': 't', 'จ': 't', 'ช': 't',
  'ซ': 't', 'ฌ': 't', 'ศ': 't', 'ษ': 't', 'ส': 't', 'ฎ': 't', 'ฏ': 't',
  'ฑ': 't', 'ฒ': 't',
  'ก': 'k', 'ข': 'k', 'ค': 'k', 'ฅ': 'k', 'ฆ': 'k',
};

/// 末子音の鼻音（-ng -n -m）。
///
/// ย ว は末子音でも母音の渡り（-i / -u）なので入れない。
const Map<String, String> kFinalNasalSounds = {
  'ง': 'ng',
  'น': 'n', 'ณ': 'n', 'ร': 'n', 'ล': 'n', 'ฬ': 'n', 'ญ': 'n',
  'ม': 'm',
};

/// 日本語に無い母音。値は音の名前（文言の出し分けに使う）。
enum ThaiVowelSound {
  /// แ（ɛ）。「エ」より口を横に大きく開く。
  ae,

  /// เ◌อ / เ◌ิ◌（ə）。口をあまり動かさない、こもった音。
  oe,

  /// ◌อ / เ◌าะ（ɔ）。「オ」より口を丸く大きく開く。
  aw,

  /// ◌ึ / ◌ื（ɯ）。唇を横に引いたままの「ウ」。
  ue,
}

/// 直す点。
class SegmentPoint {
  const SegmentPoint({
    required this.issue,
    required this.syllableIndex,
    required this.label,
    this.sound = '',
    this.aspirated = '',
    this.vowel,
  });

  final SegmentIssue issue;

  /// 文の音節列における位置（ローマ字を引くために持つ）。
  final int syllableIndex;

  /// 名指しする表記（子音1文字、または母音の表記）。
  final String label;

  /// [SegmentIssue.finalStop] は 'p' / 't' / 'k'、
  /// [SegmentIssue.finalNasal] は 'ng' / 'n' / 'm'。他では空文字。
  final String sound;

  /// [SegmentIssue.unaspirated] のとき、息が漏れると聞こえる子音。
  final String aspirated;

  /// [SegmentIssue.thaiVowel] のときの母音。他では null。
  final ThaiVowelSound? vowel;
}

/// 語（[start] 以上 [end] 未満の音節）から、直す点を1つ選ぶ。
///
/// 見つからなければ null（そのときは語を名指しするだけに留める）。
SegmentPoint? segmentPointOf(
  List<SegmentSyllable> syllables, {
  required int start,
  required int end,
}) {
  final from = start < 0 ? 0 : start;
  final to = end > syllables.length ? syllables.length : end;
  if (from >= to) return null;

  // 優先順位が上のものから探す。同じ順位なら語の先頭に近い音節。
  for (final issue in kSegmentPriority) {
    for (var i = from; i < to; i++) {
      final point = _pointOf(issue, syllables[i], i);
      if (point != null) return point;
    }
  }
  return null;
}

SegmentPoint? _pointOf(
  SegmentIssue issue,
  SegmentSyllable syllable,
  int index,
) {
  switch (issue) {
    case SegmentIssue.unaspirated:
      final initial = _firstChar(syllable.initialConsonant);
      final aspirated = kUnaspiratedPairs[initial];
      if (aspirated == null) return null;
      return SegmentPoint(
        issue: issue,
        syllableIndex: index,
        label: initial,
        aspirated: aspirated,
      );

    case SegmentIssue.finalStop:
      final sound =
          kFinalStopSounds[ThaiToneAnalyzer.finalConsonantOf(syllable.text)];
      if (sound == null) return null;
      return SegmentPoint(
        issue: issue,
        syllableIndex: index,
        label: ThaiToneAnalyzer.finalConsonantOf(syllable.text),
        sound: sound,
      );

    case SegmentIssue.ngInitial:
      if (_firstChar(syllable.initialConsonant) != 'ง') return null;
      return SegmentPoint(
        issue: issue,
        syllableIndex: index,
        label: 'ง',
      );

    case SegmentIssue.finalNasal:
      final sound =
          kFinalNasalSounds[ThaiToneAnalyzer.finalConsonantOf(syllable.text)];
      if (sound == null) return null;
      return SegmentPoint(
        issue: issue,
        syllableIndex: index,
        label: ThaiToneAnalyzer.finalConsonantOf(syllable.text),
        sound: sound,
      );

    case SegmentIssue.shortVowel:
      if (!syllable.hasShortVowel) return null;
      return SegmentPoint(
        issue: issue,
        syllableIndex: index,
        label: syllable.text,
      );

    case SegmentIssue.thaiVowel:
      final vowel = thaiVowelOf(syllable.text);
      if (vowel == null) return null;
      return SegmentPoint(
        issue: issue,
        syllableIndex: index,
        label: syllable.text,
        vowel: vowel,
      );
  }
}

/// 音節に含まれる、日本語に無い母音。無ければ null。
///
/// 表記から拾う。**เ◌ือ（ɯa）を เ◌อ（ə）と取り違えないこと**が要点で、
/// ื を持つ音節は先に ue 側で受ける。
ThaiVowelSound? thaiVowelOf(String syllable) {
  if (syllable.contains('แ')) return ThaiVowelSound.ae;
  if (syllable.contains('ึ') || syllable.contains('ื')) {
    return ThaiVowelSound.ue;
  }
  // เ◌อ（เธอ）と เ◌ิ◌（เดิน）。どちらも ə。
  if (syllable.contains('เ') &&
      (syllable.endsWith('อ') || syllable.contains('ิ'))) {
    return ThaiVowelSound.oe;
  }
  // เ◌าะ（เกาะ）と ◌อ（ขอ・ตอน）。อ が頭子音のときは母音ではない。
  if (syllable.contains('เ') && syllable.contains('าะ')) {
    return ThaiVowelSound.aw;
  }
  // เ◌า（เขา・เอา）は ao の二重母音。อ を含んでも ɔ ではない。
  if (syllable.startsWith('เ') && syllable.endsWith('า')) return null;
  final at = syllable.indexOf('อ');
  if (at > 0) return ThaiVowelSound.aw;
  return null;
}

String _firstChar(String text) => text.isEmpty ? '' : text[0];
