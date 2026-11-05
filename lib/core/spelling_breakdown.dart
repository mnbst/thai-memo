// =============================================================================
// spelling_breakdown.dart
// 単音節の綴りを頭子音・母音・末子音・声調に分ける。
// サーバーの functions/go/internal/spellunit（code.go / parts.go / segment.go /
// tonerule.go）の移植で、結果が一致するように保つ。
// 対応表は assets/spelling_forms.json（functions/go/cmd/spellforms の生成物）。
// =============================================================================

import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/models/quiz_question.dart';
import '../data/models/syllable.dart';
import 'thai_tone_analyzer.dart';

/// 1音節の分解。切り分けられない綴りでは glyphs が空、toneRule が null。
class SpellingBreakdown {
  final List<SpellingPart> parts;
  final List<SpellingGlyph> glyphs;
  final SpellingToneRule? toneRule;

  /// 声調の階級を前の字から借りるときの、その字（ตลาด の ล に対する ต）。
  final String? toneLeader;

  const SpellingBreakdown({
    required this.parts,
    this.glyphs = const [],
    this.toneRule,
    this.toneLeader,
  });

  /// 音節の声調情報をこの分解に合わせる。
  ///
  /// 対応表は辞書由来で、外来語など規則どおりでない語も正しい。規則で判定した
  /// 値を残すと、同じ画面に違う声調が並ぶ。
  Syllable applyTo(Syllable syllable) {
    final rule = toneRule;
    if (rule == null) return syllable;
    final tone = parts.firstWhere((p) => p.role == 'tone').tone;
    return Syllable(
      text: syllable.text,
      initialConsonant: toneLeader == null
          ? syllable.initialConsonant
          : '$toneLeader${parts.firstWhere((p) => p.role == 'onset').text}',
      consonantClass:
          rule.consonantClass == 'mid' ? 'middle' : rule.consonantClass,
      tone: tone,
      toneMark: switch (rule.mark) {
        '\u0E48' => 'maiEk',
        '\u0E49' => 'maiTho',
        '\u0E4A' => 'maiTri',
        '\u0E4B' => 'maiChattawa',
        _ => 'none',
      },
      syllableType: rule.syllable,
      hasShortVowel: rule.shortVowel,
    );
  }
}

/// 語を分解した1音節ぶん。
typedef SpellingItem = ({String text, SpellingBreakdown breakdown});

/// 綴り -> 音節形コードの対応表。
class SpellingIndex {
  static const _assetPath = 'assets/spelling_forms.json';
  static Future<SpellingIndex>? _loaded;

  final Map<String, _Code> _codes;

  /// 先頭の子音字だけで短い a を読む2音の綴り（ตลาด = ta + laat）。
  final Map<String, (_Code, _Code)> _linked;

  SpellingIndex._(this._codes, this._linked);

  static Future<SpellingIndex> load() => _loaded ??=
      rootBundle.loadString(_assetPath).then((raw) => SpellingIndex.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          ));

  /// コード -> 綴りの一覧から組む。
  factory SpellingIndex.fromJson(Map<String, dynamic> json) {
    final codes = <String, _Code>{};
    final linked = <String, (_Code, _Code)>{};
    json.forEach((rawCode, rawForms) {
      if (rawForms is! List) return;
      final forms = rawForms.whereType<String>();
      final separator = rawCode.indexOf("'");
      if (separator < 0) {
        final code = _Code.parse(rawCode);
        if (code == null) return;
        for (final form in forms) {
          codes[form] = code;
        }
        return;
      }
      final head = _Code.parse(rawCode.substring(0, separator));
      final tail = _Code.parse(rawCode.substring(separator + 1));
      if (head == null || tail == null) return;
      for (final form in forms) {
        linked[form] = (head, tail);
      }
    });
    return SpellingIndex._(codes, linked);
  }

  /// 綴りを読む単位に分けて分解する。表に無い綴りは空。
  List<SpellingItem> items(String text) {
    final trimmed = text.trim();
    final code = _codes[trimmed];
    if (code != null) {
      return [(text: trimmed, breakdown: _build(trimmed.runes.toList(), code))];
    }
    final pair = _linked[trimmed];
    if (pair == null) return const [];
    final runes = trimmed.runes.toList();
    final lead = runes.first;
    final rest = runes.sublist(1);
    return [
      (
        text: String.fromCharCode(lead),
        breakdown: _build([lead], pair.$1),
      ),
      (
        text: String.fromCharCodes(rest),
        breakdown: _build(rest, pair.$2, lead: lead),
      ),
    ];
  }

  /// 語全体を分解できればそれを、できなければ音節ごとに分解して返す。
  /// 分解できない音節は結果に含めない。
  List<SpellingItem> forWord(String word, List<String> syllables) {
    final whole = items(word);
    if (whole.isNotEmpty) return whole;
    return [for (final syllable in syllables) ...items(syllable)];
  }

  static SpellingBreakdown _build(List<int> runes, _Code code, {int? lead}) {
    final owner = _segmentOwners(runes, code);
    if (owner == null) return SpellingBreakdown(parts: code.parts());
    final candidate = _leaderFor(runes, owner, lead);
    // 読みと合うときだけ階級を借りる（ขโมย は ข の後でも平声で、借りていない）。
    final leader = candidate != null &&
            _ruleGivesTone(
                _toneRule(runes, owner, code, leader: candidate), code)
        ? candidate
        : null;
    return SpellingBreakdown(
      parts: _partsWithText(runes, owner, code),
      glyphs: _glyphs(runes, owner),
      toneRule: _toneRule(runes, owner, code, leader: leader),
      toneLeader: leader == null ? null : String.fromCharCode(leader),
    );
  }
}

// ==================== 音節形コード（code.go） ====================

class _Code {
  final String onset;
  final String vowel;
  final String coda;
  final String tone;

  const _Code(this.onset, this.vowel, this.coda, this.tone);

  static const _vowels = [
    '@@', 'O', 'OO', 'U', 'UU', 'UUa', 'a', 'aa', 'e', 'e-', 'ee', //
    'i', 'ia', 'ii', 'iia', 'o', 'oo', 'u', 'uu', 'uua', 'x', 'xx',
  ];
  static const _codas = ['N', 'j', 'k', 'l', 'm', 'n', 'p', 't', 'w'];
  static const _tones = ['0', '1', '2', '3', '4'];
  static final _sortedVowels = [..._vowels]
    ..sort((a, b) => b.length.compareTo(a.length));

  static _Code? parse(String code) {
    // ~ は発音の区切り（อ.ส. = ?OO0~sOO4）で、1音節のコードではない。
    if (code.isEmpty || code.contains(RegExp(r"['^\\~]"))) return null;
    final tone = code.substring(code.length - 1);
    if (!_tones.contains(tone)) return null;
    final body = code.substring(0, code.length - 1);

    var coda = '';
    for (final c in _codas) {
      if (body.endsWith(c)) {
        coda = c;
        break;
      }
    }
    final rest = body.substring(0, body.length - coda.length);
    for (final vowel in _sortedVowels) {
      if (!rest.endsWith(vowel)) continue;
      final onset = rest.substring(0, rest.length - vowel.length);
      if (onset.isEmpty) return null;
      return _Code(onset, vowel, coda, tone);
    }
    return null;
  }

  List<SpellingPart> parts() => [
        SpellingPart(role: 'onset', sound: _onsetRoman[onset] ?? onset),
        SpellingPart(role: 'vowel', sound: _vowelRoman[vowel] ?? vowel),
        SpellingPart(role: 'coda', sound: _codaRoman[coda] ?? coda),
        SpellingPart(role: 'tone', tone: _toneNames[tone] ?? ''),
      ];

  @override
  bool operator ==(Object other) =>
      other is _Code &&
      other.onset == onset &&
      other.vowel == vowel &&
      other.coda == coda &&
      other.tone == tone;

  @override
  int get hashCode => Object.hash(onset, vowel, coda, tone);
}

// ==================== 読み（parts.go） ====================

const _onsetRoman = {
  '?': '', 'N': 'ng', 'c': 'j', 'ch': 'ch', 'j': 'y', //
  'kh': 'kh', 'khl': 'khl', 'khr': 'khr', 'khw': 'khw',
  'ph': 'ph', 'phl': 'phl', 'phr': 'phr',
  'th': 'th', 'thr': 'thr', 'thw': 'thw',
};

const _vowelRoman = {
  'a': 'a', 'aa': 'aa', 'i': 'i', 'ii': 'ii', 'u': 'u', 'uu': 'uu', //
  'e': 'e', 'ee': 'ee', 'e-': 'ə', '@@': 'əə',
  'o': 'o', 'oo': 'oo', 'O': 'ɔ', 'OO': 'ɔɔ',
  'x': 'ɛ', 'xx': 'ɛɛ', 'U': 'ʉ', 'UU': 'ʉʉ',
  'ia': 'ia', 'iia': 'iia', 'uua': 'uua', 'UUa': 'ʉʉa',
};

const _codaRoman = {'N': 'ng', 'j': 'i', 'w': 'w', '': ''};

const _toneNames = {
  '0': 'mid', '1': 'low', '2': 'falling', '3': 'high', '4': 'rising', //
};

const _roles = ['onset', 'vowel', 'coda', 'tone', 'silent'];

const _dimOnset = 0;
const _dimVowel = 1;
const _dimCoda = 2;
const _dimTone = 3;
const _dimSilent = 4;

List<SpellingPart> _partsWithText(
  List<int> runes,
  List<int> owner,
  _Code code,
) {
  final texts = List.filled(_roles.length, '');
  for (var i = 0; i < runes.length; i++) {
    texts[owner[i]] += String.fromCharCode(runes[i]);
  }
  final base = code.parts();
  return [
    for (var i = 0; i < base.length; i++)
      SpellingPart(
        role: base[i].role,
        text: texts[i],
        sound: base[i].sound,
        tone: base[i].tone,
      ),
    // 読まない字は音の部品に混ぜず、それだけの枠にする。
    if (texts[_dimSilent].isNotEmpty)
      SpellingPart(role: 'silent', text: texts[_dimSilent]),
  ];
}

List<SpellingGlyph> _glyphs(List<int> runes, List<int> owner) {
  final out = <SpellingGlyph>[];
  var last = -1;
  var buffer = StringBuffer();
  void flush() {
    if (last >= 0) {
      out.add(SpellingGlyph(role: _roles[last], text: buffer.toString()));
    }
    buffer = StringBuffer();
  }

  for (var i = 0; i < runes.length; i++) {
    if (owner[i] != last) {
      flush();
      last = owner[i];
    }
    buffer.writeCharCode(runes[i]);
  }
  flush();
  return out;
}

// ==================== 字の切り分け（segment.go） ====================

const _thanthakhat = 0x0E4C; // ์
const _saraAm = 0x0E33; // ำ
const _ro = 0x0E23; // ร
const _ho = 0x0E2B; // ห
const _o = 0x0E2D; // อ

final _leadingVowels = 'เแโใไ'.runes.toSet();

const _clusterOnsets = {
  'kl', 'kr', 'kw', 'khl', 'khr', 'khw', 'pl', 'pr', 'phl', 'phr', 'tr', //
  'thr', 'thw', 'bl', 'br', 'dr', 'fl', 'fr', 'cl', 'sl', 'sr', 'sw',
};

const _sonorantOnsets = {'m', 'n', 'N', 'l', 'w', 'r', 'j'};

/// 末子音として読むときの音（コード）。
final _finalSounds = <int, String>{
  for (final entry in const {
    'k': 'กขคฆ',
    'N': 'ง',
    't': 'จชซฎฏฐฑฒดตถทธศษส',
    'n': 'ญณนรลฬ',
    'p': 'บปพฟภ',
    'm': 'ม',
    'j': 'ย',
    'w': 'ว',
  }.entries)
    for (final r in entry.value.runes) r: entry.key,
};

bool _isConsonant(int r) => r >= 0x0E01 && r <= 0x0E2E;
bool _isToneMark(int r) => r >= 0x0E48 && r <= 0x0E4B;
bool _isCombining(int r) =>
    r == 0x0E31 || (r >= 0x0E34 && r <= 0x0E3A) || (r >= 0x0E47 && r <= 0x0E4E);

/// 末子音を母音字が兼ねる綴りか（ำ・ไ/ใ・เ-า）。
bool _hasCodaInVowel(List<int> r) {
  if (r.contains(_saraAm) || r.contains(0x0E44) || r.contains(0x0E43)) {
    return true;
  }
  return r.isNotEmpty && r.first == 0x0E40 && r.last == 0x0E32;
}

/// 読む子音字（์ の付いていない子音）が from 以降に残っているか。
bool _hasPronouncedConsonant(List<int> r, int from) {
  for (var j = from; j < r.length; j++) {
    if (!_isConsonant(r[j])) continue;
    if (j + 1 < r.length && r[j + 1] == _thanthakhat) continue;
    return true;
  }
  return false;
}

/// ์ とそれが消す字を読まない字にする（เสาร์ の ร์、โพธิ์ の ธิ์）。
/// 母音の綴りや末子音の判定に混ざらないよう、ほかの部品より先に決める。
void _markKaran(List<int> r, List<int> owner) {
  for (var j = 0; j < r.length; j++) {
    if (r[j] != _thanthakhat) continue;
    owner[j] = _dimSilent;
    var k = j - 1;
    while (k >= 0 && _isCombining(r[k])) {
      if (owner[k] < 0) owner[k] = _dimSilent;
      k--;
    }
    if (k >= 0 && _isConsonant(r[k]) && owner[k] < 0) {
      owner[k] = _dimSilent;
    }
  }
}

/// 各字の役割（0=頭子音 1=母音 2=末子音 3=声調 4=読まない字）。
/// 切り分けられなければ null（間違った対応を教えるより文字を出さない）。
List<int>? _segmentOwners(List<int> r, _Code code) {
  final owner = List.filled(r.length, -1);

  for (var i = 0; i < r.length; i++) {
    if (_isToneMark(r[i])) owner[i] = _dimTone;
  }

  _markKaran(r, owner);

  // 頭子音。前置母音を飛ばした先の子音字から。
  var i = 0;
  while (i < r.length && (_leadingVowels.contains(r[i]) || owner[i] >= 0)) {
    if (owner[i] < 0) owner[i] = _dimVowel;
    i++;
  }
  if (i >= r.length || !_isConsonant(r[i])) return null;
  owner[i] = _dimOnset;
  var onsetLen = 1;
  // 2文字で書く頭子音（二重子音と、ห・อ を前に置くもの）。
  if (i + 1 < r.length && _isConsonant(r[i + 1]) && owner[i + 1] < 0) {
    final lead = r[i];
    if (_clusterOnsets.contains(code.onset) ||
        ((lead == _ho || lead == _o) && _sonorantOnsets.contains(code.onset))) {
      owner[i + 1] = _dimOnset;
      onsetLen = 2;
    }
  }
  i += onsetLen;

  var codaAssigned = false;
  var codaPos = -1;

  if (i + 1 < r.length &&
      r[i] == _ro &&
      r[i + 1] == _ro &&
      owner[i] < 0 &&
      owner[i + 1] < 0) {
    // รร は母音 a を子音字で書く綴り。後ろに読む字がなければ2つめが末子音 n。
    owner[i] = _dimVowel;
    if (_hasPronouncedConsonant(r, i + 2)) {
      owner[i + 1] = _dimVowel;
    } else {
      owner[i + 1] = _dimCoda;
      codaAssigned = true;
      codaPos = i + 1;
    }
    i += 2;
  } else if (i < r.length &&
      r[i] == _ro &&
      owner[i] < 0 &&
      code.coda.isNotEmpty &&
      !_hasPronouncedConsonant(r, i + 1)) {
    // 単独の ร は母音と末子音をまとめて書く（กร = kɔɔn）。
    owner[i] = _dimVowel;
    codaAssigned = true;
    codaPos = i;
    i++;
  } else if (i < r.length &&
      r[i] == _ro &&
      owner[i] < 0 &&
      !code.onset.contains('r') &&
      code.coda != 'r') {
    // 頭子音のすぐ後の ร は読まない綴りがある（จริง・สร้าง・เสร็จ）。
    owner[i] = _dimSilent;
    i++;
  }

  if (code.coda.isNotEmpty && !codaAssigned) {
    var last = -1;
    var fallback = -1;
    for (var j = r.length - 1; j >= i; j--) {
      if (!_isConsonant(r[j]) || owner[j] >= 0) continue;
      if (j + 1 < r.length && r[j + 1] == _thanthakhat) continue;
      if (fallback < 0) fallback = j;
      if (_finalSounds[r[j]] == code.coda) {
        last = j;
        break;
      }
    }
    if (last < 0) last = fallback;
    if (last >= 0) {
      owner[last] = _dimCoda;
      codaPos = last;
      // 末子音の直前の ร は読まない綴りがある（มารถ・เกียรติ）。
      if (last - 1 > i && r[last - 1] == _ro && owner[last - 1] < 0) {
        owner[last - 1] = _dimSilent;
      }
      // 末子音より後ろに付く記号も読まない（เกียรติ の ิ、องค์ の ์）。
      for (var j = last + 1; j < r.length && _isCombining(r[j]); j++) {
        owner[j] = _dimSilent;
      }
    } else if (!_hasCodaInVowel([
      for (var j = 0; j < r.length; j++)
        if (owner[j] != _dimSilent) r[j],
    ])) {
      return null;
    }
  }

  // 残りは母音。末子音より後ろに残った字は読まない字。
  for (var j = 0; j < r.length; j++) {
    if (owner[j] >= 0) continue;
    owner[j] = codaPos >= 0 && j > codaPos ? _dimSilent : _dimVowel;
  }
  return owner;
}

// ==================== 声調の3要素（tonerule.go） ====================

final _midConsonants = 'กจฎฏดตบปอ'.runes.toSet();
final _highConsonants = 'ขฃฉฐถผฝศษสห'.runes.toSet();

const _shortVowels = {'a', 'i', 'u', 'e', 'e-', 'o', 'O', 'x', 'U', 'ia'};
const _deadCodas = {'k', 'p', 't'};

/// 低子音の共鳴音。前の高子音・中子音の字に階級を借りる（ตลาด・สนุก）。
final _sonorantConsonants = 'งญณนมยรลวฬ'.runes.toSet();

/// 階級を貸す前の字。借りない綴りでは null。
int? _leaderFor(List<int> r, List<int> owner, int? lead) {
  if (lead == null || _lowClass(lead)) return null;
  final onset = owner.indexOf(_dimOnset);
  if (onset < 0 || !_sonorantConsonants.contains(r[onset])) return null;
  return lead;
}

/// 声調の3要素が、表の上でコードの声調になるか。
bool _ruleGivesTone(SpellingToneRule? rule, _Code code) {
  if (rule == null) return false;
  final klass = switch (rule.consonantClass) {
    'mid' => ConsonantClass.middle,
    'high' => ConsonantClass.high,
    _ => ConsonantClass.low,
  };
  final mark = switch (rule.mark) {
    '\u0E48' => ToneMark.maiEk,
    '\u0E49' => ToneMark.maiTho,
    '\u0E4A' => ToneMark.maiTri,
    '\u0E4B' => ToneMark.maiChattawa,
    _ => ToneMark.none,
  };
  final type = rule.syllable == 'dead' ? SyllableType.dead : SyllableType.live;
  final hit = ThaiToneAnalyzer.getToneTable(klass)
      .where((r) => r.matches(mark, type, hasShortVowel: rule.shortVowel))
      .firstOrNull;
  return hit?.resultingTone.name == _toneNames[code.tone];
}

bool _lowClass(int r) =>
    !_midConsonants.contains(r) && !_highConsonants.contains(r);

SpellingToneRule? _toneRule(
  List<int> r,
  List<int> owner,
  _Code code, {
  int? leader,
}) {
  // 階級は頭子音のかたまりの最初の字で決まる（หน・อย は前に置いた字が効く）。
  int? first = leader;
  final mark = StringBuffer();
  for (var i = 0; i < r.length; i++) {
    if (owner[i] == _dimOnset && first == null && _isConsonant(r[i])) {
      first = r[i];
    }
    if (owner[i] == _dimTone) mark.writeCharCode(r[i]);
  }
  if (first == null) return null;

  final short = _shortVowels.contains(code.vowel);
  return SpellingToneRule(
    consonantClass: _midConsonants.contains(first)
        ? 'mid'
        : _highConsonants.contains(first)
            ? 'high'
            : 'low',
    syllable: _deadCodas.contains(code.coda) || (code.coda.isEmpty && short)
        ? 'dead'
        : 'live',
    mark: mark.toString(),
    shortVowel: short,
  );
}
