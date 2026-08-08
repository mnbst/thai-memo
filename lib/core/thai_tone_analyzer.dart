import '../l10n/app_localizations.dart';

/// タイ語の声調分析ユーティリティ
class ThaiToneAnalyzer {
  // 高子音（สูง）
  static const highConsonants = [
    'ข',
    'ฃ',
    'ฉ',
    'ฐ',
    'ถ',
    'ผ',
    'ฝ',
    'ศ',
    'ษ',
    'ส',
    'ห',
  ];

  // 中子音（กลาง）
  static const middleConsonants = [
    'ก',
    'จ',
    'ฎ',
    'ฏ',
    'ด',
    'ต',
    'บ',
    'ป',
    'อ',
  ];

  // 低子音（ต่ำ）
  static const lowConsonants = [
    'ค',
    'ฅ',
    'ฆ',
    'ช',
    'ซ',
    'ฌ',
    'ท',
    'ธ',
    'พ',
    'ฟ',
    'ภ',
    'ง',
    'ญ',
    'ฑ', // ทะหานมนโท
    'ฒ', // ผู้เฒ่า
    'ณ',
    'น',
    'ม',
    'ย',
    'ร',
    'ฤ', // รึ (low consonant / special vowel)
    'ล',
    'ฦ', // ลึ (low consonant / special vowel, rarely used)
    'ว',
    'ฬ',
    'ฮ',
  ];

  // 声調記号
  static const toneMark1 = '\u0E48'; // ไม้เอก (่)
  static const toneMark2 = '\u0E49'; // ไม้โท (้)
  static const toneMark3 = '\u0E4A'; // ไม้ตรี (๊)
  static const toneMark4 = '\u0E4B'; // ไม้จัตวา (๋)

  // 短母音（ダイアクリティカル + รร）
  // ※ เ◌ะ / แ◌ะ 等は ะ (\u0E30) が含まれるため個別パターン不要
  static const shortVowels = [
    '\u0E30', // ะ
    '\u0E31', // ั (mai han akat = 短母音 อะ の閉音節形)
    '\u0E34', // ิ
    '\u0E36', // ึ
    '\u0E38', // ุ
    '\u0E47', // ็ (mai taikhu = 母音短化マーク、เ็/แ็ 等で長母音→短母音)
    'รร', // สระ รร = 短母音 /a/（末子音の前）または /an/（語末）
  ];

  // 長母音を示す文字
  // | 表記  | 音価 | 例    |
  // | า    | aː   | มา    |
  // | ี    | iː   | ดี    |
  // | ื    | ɯː   | มือ   |
  // | ู    | uː   | ดู    |
  // | ำ    | am   | ทำ    |（鼻音を含む複合母音、長母音相当）
  // ※ เ◌ / แ◌ / โ◌ は leadingVowels で管理
  static const longVowelChars = [
    '\u0E32', // า (aː)
    '\u0E35', // ี (iː)
    '\u0E37', // ื (ɯː)
    '\u0E39', // ู (uː)
    '\u0E33', // ำ (am)
  ];

  // 複合母音パターン（長母音として扱う / hasShortVowel = false）
  // | 表記    | 音価  | 検出方法                | 例     |
  // | เ◌า   | aw    | า → longVowelChars      | เข้า   |
  // | เ◌ีย  | iaː   | ี → longVowelChars      | เมีย   |
  // | เ◌ือ  | ɯaː   | ื → longVowelChars      | เสื้อ  |
  // | ◌ัว   | uaː   | 'ัว' パターン            | ตัว    |
  // | ◌ว    | uaː   | ว＋末子音（暗黙形）      | ควร    |
  // | ไ◌    | ai    | ไ 文字                   | ไป     |
  // | ใ◌    | ai    | ใ 文字                   | ใจ     |
  // ※ ไ / ใ は leadingVowels にも含まれる（位置検出用）
  static const compoundVowelPatterns = [
    'ัว', // อัว (uaː) の明示的表記（ั 単独は短母音だが ัว は長複合母音）
    'ไ', // ไ◌ (ai) 二重母音
    'ใ', // ใ◌ (ai) 二重母音
  ];

  // 死音節の末子音（-p, -t, -k）
  static const deadEndConsonants = [
    // -p音（唇を閉じて止める）
    'บ', 'ป', 'พ', 'ฟ', 'ภ',
    // -t音（舌の先で止める）
    'ด', 'ต', 'ถ', 'ท', 'ธ', 'จ', 'ช', 'ซ', 'ฌ', 'ศ', 'ษ', 'ส', 'ฎ', 'ฏ', 'ฑ',
    'ฒ',
    // -k音（喉の奥で止める）
    'ก', 'ข', 'ค', 'ฅ', 'ฆ',
  ];

  // 生音節の末子音（-m, -n, -ng, -y, -w, -r(=n)）
  // ณ ล ฬ は末子音として /n/ の音を持つ（น と同等）
  static const liveEndConsonants = [
    'ม',
    'น',
    'ณ',
    'ง',
    'ญ',
    'ย',
    'ว',
    'ร',
    'ล',
    'ฬ'
  ];

  // 語彙固有の声調例外（規則では導出できない単語）
  static const Map<String, ThaiTone> _toneExceptions = {
    'เยอะ': ThaiTone.high, // yə́ — 短母音死音節だが前置母音で長母音判定される例外
  };

  // 前置母音（leading vowels）
  static const leadingVowels = [
    'เ', // ed
    'แ', // ae
    'โ', // o
    'ใ', // ai (mai malai)
    'ไ', // ai (mai muan)
  ];

  /// 音節を1回パースして全要素を抽出
  static _SyllableComponents _parseSyllable(String word) {
    if (word.isEmpty) return _SyllableComponents.empty();

    // 1. 前置母音をスキップして頭子音位置を特定
    int pos = 0;
    if (leadingVowels.contains(word[0])) pos = 1;
    if (pos >= word.length) return _SyllableComponents.empty();

    // 2. 頭子音を取得
    final firstConsonant = word[pos];
    String initialConsonant = firstConsonant;
    String consonantForTone = firstConsonant;

    // 3. 声調記号を検出
    ToneMark toneMark = ToneMark.none;
    if (word.contains(toneMark1)) {
      toneMark = ToneMark.maiEk;
    } else if (word.contains(toneMark2)) {
      toneMark = ToneMark.maiTho;
    } else if (word.contains(toneMark3)) {
      toneMark = ToneMark.maiTri;
    } else if (word.contains(toneMark4)) {
      toneMark = ToneMark.maiChattawa;
    }

    // 4. 最後の文字 → 末子音・音節タイプ判定
    // 末子音につく ิ をスキップ（例: ชาติ の ติ → 末子音は ต）
    int lastConsonantPos = word.length - 1;
    if (lastConsonantPos > pos && word[lastConsonantPos] == '\u0E34') {
      lastConsonantPos--;
    }
    final lastChar = word[lastConsonantPos];
    // 頭子音の後に文字がない（= 頭子音が末字）場合は末子音なし（開音節）
    // 例: ไป (ไ+ป) → ป は頭子音のみ、末子音なし
    final hasNoFinalConsonant = (lastConsonantPos <= pos);
    SyllableType syllableType;
    if (!hasNoFinalConsonant && deadEndConsonants.contains(lastChar)) {
      syllableType = SyllableType.dead;
    } else if (!hasNoFinalConsonant && liveEndConsonants.contains(lastChar)) {
      syllableType = SyllableType.live;
    } else {
      syllableType = SyllableType.live; // デフォルト、短母音で上書き
    }

    // 5. 母音の長短を判定（優先順位: ็短化 > ะ終止 > 複合母音/長母音 > 短母音 > 暗黙判定）
    bool hasShortVowel;
    if (word.contains('\u0E47')) {
      // ็ (mai taikhu) は長母音を短母音化する（เ็ก, แ็ว 等）→ 最優先で短母音
      hasShortVowel = true;
    } else if (word.endsWith('\u0E30')) {
      // ะ で終わる → 短母音（แ◌ะ / เ◌ะ パターン含む）
      hasShortVowel = true;
    } else if (compoundVowelPatterns.any((v) => word.contains(v)) ||
        longVowelChars.any((v) => word.contains(v)) ||
        leadingVowels.any((v) => word.contains(v))) {
      // 複合母音（◌ัว / ไ / ใ）または長母音（า ี ื ู ำ / เ แ โ）
      hasShortVowel = false;
    } else if (shortVowels.any((v) => word.contains(v))) {
      hasShortVowel = true;
    } else {
      // 明示的母音なし → 暗黙の母音を音節構造から判定
      hasShortVowel = _hasImplicitShortVowel(word, pos);
    }

    // 短母音 + 末子音なし → 死音節
    if (hasShortVowel &&
        (hasNoFinalConsonant ||
            (!deadEndConsonants.contains(lastChar) &&
                !liveEndConsonants.contains(lastChar)))) {
      syllableType = SyllableType.dead;
    }

    // 6. 子音クラスを判定
    ConsonantClass consonantClass;
    if (highConsonants.contains(consonantForTone)) {
      consonantClass = ConsonantClass.high;
    } else if (middleConsonants.contains(consonantForTone)) {
      consonantClass = ConsonantClass.middle;
    } else if (lowConsonants.contains(consonantForTone)) {
      consonantClass = ConsonantClass.low;
    } else {
      consonantClass = ConsonantClass.unknown;
    }

    return _SyllableComponents(
      initialConsonant: initialConsonant,
      consonantClass: consonantClass,
      toneMark: toneMark,
      syllableType: syllableType,
      hasShortVowel: hasShortVowel,
    );
  }

  /// 文字が声調記号かどうかを判定
  static bool _isToneMark(String char) {
    return char == toneMark1 ||
        char == toneMark2 ||
        char == toneMark3 ||
        char == toneMark4;
  }

  /// 二重子音クラスターの2番目になりうる子音か判定
  static bool _isClusterSecondConsonant(String char) {
    return char == 'ร' || char == 'ล' || char == 'ว';
  }

  /// 明示的母音がない場合に暗黙の短母音かどうかを音節構造から判定
  static bool _hasImplicitShortVowel(String word, int pos) {
    int i = pos + 1;

    // ว の次が子音なら暗黙の複合母音 อัว（長母音）
    if (i < word.length && word[i] == 'ว') {
      int nextI = i + 1;
      while (nextI < word.length && _isToneMark(word[nextI])) {
        nextI++;
      }
      if (nextI < word.length && !_vowelDiacritics.contains(word[nextI])) {
        return false; // 複合母音 อัว（暗黙形）
      }
      i++; // ว はクラスター子音かソノラント末子音としてスキップ
    } else if (i < word.length && _isClusterSecondConsonant(word[i])) {
      i++; // クラスター子音をスキップ
    }

    // 声調記号をスキップ
    while (i < word.length && _isToneMark(word[i])) {
      i++;
    }

    // อ があれば長母音（暗黙の อ◌อ）
    return !(i < word.length && word[i] == 'อ');
  }

  // 後置母音ダイアクリティカル（子音かどうかの判定用、前置母音は除く）
  static const _vowelDiacritics = [
    '\u0E30', // ะ
    '\u0E31', // ั
    '\u0E32', // า
    '\u0E33', // ำ
    '\u0E34', // ิ
    '\u0E35', // ี
    '\u0E36', // ึ
    '\u0E37', // ื
    '\u0E38', // ุ
    '\u0E39', // ู
    '\u0E47', // ็
  ];

  /// タイ語の単語を分析して声調情報を返す
  static ToneAnalysis analyzeTone(String thaiWord) {
    if (thaiWord.isEmpty) {
      return ToneAnalysis(
        consonantClass: ConsonantClass.unknown,
        toneMark: ToneMark.none,
        syllableType: SyllableType.unknown,
        resultingTone: ThaiTone.unknown,
        explanation: '',
        hasShortVowel: false,
      );
    }

    final c = _parseSyllable(thaiWord);

    // 語彙固有の例外を優先
    final exceptionTone = _toneExceptions[thaiWord];

    final resultingTone = exceptionTone ??
        _determineTone(
          c.consonantClass,
          c.toneMark,
          c.syllableType,
          c.hasShortVowel,
        );

    final explanation = _generateExplanation(
      thaiWord,
      c.consonantClass,
      c.toneMark,
      c.syllableType,
      resultingTone,
    );

    return ToneAnalysis(
      consonantClass: c.consonantClass,
      toneMark: c.toneMark,
      syllableType: c.syllableType,
      resultingTone: resultingTone,
      explanation: explanation,
      initialConsonant: c.initialConsonant,
      hasShortVowel: c.hasShortVowel,
    );
  }

  /// 声調を決定
  static ThaiTone _determineTone(
    ConsonantClass consonantClass,
    ToneMark toneMark,
    SyllableType syllableType,
    bool hasShortVowel,
  ) {
    switch (consonantClass) {
      case ConsonantClass.middle:
        return _determineMiddleClassTone(toneMark, syllableType);
      case ConsonantClass.high:
        return _determineHighClassTone(toneMark, syllableType);
      case ConsonantClass.low:
        return _determineLowClassTone(toneMark, syllableType, hasShortVowel);
      case ConsonantClass.unknown:
        return ThaiTone.unknown;
    }
  }

  /// 中子音の声調決定
  static ThaiTone _determineMiddleClassTone(
      ToneMark toneMark, SyllableType syllableType) {
    switch (toneMark) {
      case ToneMark.none:
        return syllableType == SyllableType.dead ? ThaiTone.low : ThaiTone.mid;
      case ToneMark.maiEk:
        return ThaiTone.low;
      case ToneMark.maiTho:
        return ThaiTone.falling;
      case ToneMark.maiTri:
        return ThaiTone.high;
      case ToneMark.maiChattawa:
        return ThaiTone.rising;
    }
  }

  /// 高子音の声調決定
  static ThaiTone _determineHighClassTone(
      ToneMark toneMark, SyllableType syllableType) {
    switch (toneMark) {
      case ToneMark.none:
        return syllableType == SyllableType.dead
            ? ThaiTone.low
            : ThaiTone.rising;
      case ToneMark.maiEk:
        return ThaiTone.low;
      case ToneMark.maiTho:
        return ThaiTone.falling;
      case ToneMark.maiTri:
        // 注意: 高子音ではไม้ตรี（マイトリー）は例外的な使用です
        // 通常の現代タイ語では使われません
        return ThaiTone.high;
      case ToneMark.maiChattawa:
        // 注意: 高子音ではไม้จัตวา（マイチャッタワー）は例外的な使用です
        // 通常の現代タイ語では使われません
        return ThaiTone.rising;
    }
  }

  /// 低子音の声調決定
  static ThaiTone _determineLowClassTone(
    ToneMark toneMark,
    SyllableType syllableType,
    bool hasShortVowel,
  ) {
    switch (toneMark) {
      case ToneMark.none:
        if (syllableType == SyllableType.dead) {
          // 促音節：短母音なら高声、長母音・複合母音なら下降声
          return hasShortVowel ? ThaiTone.high : ThaiTone.falling;
        } else {
          // 生音節：平声
          return ThaiTone.mid;
        }
      case ToneMark.maiEk:
        return ThaiTone.falling;
      case ToneMark.maiTho:
        return ThaiTone.high;
      case ToneMark.maiTri:
        // 注意: 低子音でไม้ตรี（マイトリー）は例外的な使用です
        // 主にไม้โทと同じ高声になりますが、現代では稀です
        return ThaiTone.high;
      case ToneMark.maiChattawa:
        // 注意: 低子音でไม้จัตวา（マイチャッタワー）は例外的な使用です
        // サンスクリット由来の単語などで稀に見られます
        return ThaiTone.rising;
    }
  }

  /// 解説文を生成
  static String _generateExplanation(
    String word,
    ConsonantClass consonantClass,
    ToneMark toneMark,
    SyllableType syllableType,
    ThaiTone tone,
  ) {
    final classText = consonantClass.displayName;
    final markText = toneMark.displayName;
    final syllableText = syllableType.displayName;
    final toneText = tone.displayName;

    return '$classText + $markText + $syllableText → $toneText';
  }

  /// 声調テーブルを取得
  static List<ToneRule> getToneTable(ConsonantClass consonantClass) {
    switch (consonantClass) {
      case ConsonantClass.middle:
        return _getMiddleClassToneTable();
      case ConsonantClass.high:
        return _getHighClassToneTable();
      case ConsonantClass.low:
        return _getLowClassToneTable();
      case ConsonantClass.unknown:
        return [];
    }
  }

  static List<ToneRule> _getMiddleClassToneTable() {
    return [
      ToneRule(ToneMark.none, SyllableType.live, ThaiTone.mid),
      ToneRule(ToneMark.none, SyllableType.dead, ThaiTone.low),
      ToneRule(ToneMark.maiEk, SyllableType.live, ThaiTone.low),
      ToneRule(ToneMark.maiTho, SyllableType.live, ThaiTone.falling),
      ToneRule(ToneMark.maiTri, SyllableType.live, ThaiTone.high),
      ToneRule(ToneMark.maiChattawa, SyllableType.live, ThaiTone.rising),
    ];
  }

  static List<ToneRule> _getHighClassToneTable() {
    return [
      ToneRule(ToneMark.none, SyllableType.live, ThaiTone.rising),
      ToneRule(ToneMark.none, SyllableType.dead, ThaiTone.low),
      ToneRule(ToneMark.maiEk, SyllableType.live, ThaiTone.low),
      ToneRule(ToneMark.maiTho, SyllableType.live, ThaiTone.falling),
    ];
  }

  static List<ToneRule> _getLowClassToneTable() {
    return [
      ToneRule(ToneMark.none, SyllableType.live, ThaiTone.mid),
      ToneRule(ToneMark.none, SyllableType.dead, ThaiTone.high,
          isShortVowel: true),
      ToneRule(ToneMark.none, SyllableType.dead, ThaiTone.falling,
          isShortVowel: false),
      ToneRule(ToneMark.maiEk, SyllableType.live, ThaiTone.falling),
      ToneRule(ToneMark.maiTho, SyllableType.live, ThaiTone.high),
      ToneRule(ToneMark.maiTri, SyllableType.live, ThaiTone.high),
      ToneRule(ToneMark.maiChattawa, SyllableType.live, ThaiTone.rising),
    ];
  }

  /// 文字列から子音クラスのenumに変換
  static ConsonantClass parseConsonantClass(String value) {
    switch (value.toLowerCase()) {
      case 'high':
        return ConsonantClass.high;
      case 'middle':
        return ConsonantClass.middle;
      case 'low':
        return ConsonantClass.low;
      default:
        return ConsonantClass.unknown;
    }
  }

  /// 文字列から声調記号のenumに変換
  static ToneMark parseToneMark(String value) {
    switch (value.toLowerCase()) {
      case 'maiek':
        return ToneMark.maiEk;
      case 'maitho':
        return ToneMark.maiTho;
      case 'maitri':
        return ToneMark.maiTri;
      case 'maichattawa':
        return ToneMark.maiChattawa;
      case 'none':
      default:
        return ToneMark.none;
    }
  }

  /// 文字列から音節タイプのenumに変換
  static SyllableType parseSyllableType(String value) {
    switch (value.toLowerCase()) {
      case 'live':
        return SyllableType.live;
      case 'dead':
        return SyllableType.dead;
      default:
        return SyllableType.unknown;
    }
  }

  /// 文字列から声調のenumに変換
  static ThaiTone parseTone(String value) {
    switch (value.toLowerCase()) {
      case 'mid':
        return ThaiTone.mid;
      case 'low':
        return ThaiTone.low;
      case 'falling':
        return ThaiTone.falling;
      case 'high':
        return ThaiTone.high;
      case 'rising':
        return ThaiTone.rising;
      default:
        return ThaiTone.unknown;
    }
  }
}

/// 声調分析結果
class ToneAnalysis {
  final ConsonantClass consonantClass;
  final ToneMark toneMark;
  final SyllableType syllableType;
  final ThaiTone resultingTone;
  final String explanation;
  final String? initialConsonant;
  final bool hasShortVowel;

  ToneAnalysis({
    required this.consonantClass,
    required this.toneMark,
    required this.syllableType,
    required this.resultingTone,
    required this.explanation,
    this.initialConsonant,
    required this.hasShortVowel,
  });
}

/// 声調ルール
class ToneRule {
  final ToneMark toneMark;
  final SyllableType syllableType;
  final ThaiTone resultingTone;
  final bool? isShortVowel; // 低子音の促音節で短母音/長母音を区別するため

  ToneRule(
    this.toneMark,
    this.syllableType,
    this.resultingTone, {
    this.isShortVowel,
  });

  bool matches(ToneMark mark, SyllableType syllable, {bool? hasShortVowel}) {
    if (toneMark != mark || syllableType != syllable) {
      return false;
    }
    // isShortVowelが指定されている場合は、それも一致する必要がある
    if (isShortVowel != null && hasShortVowel != null) {
      return isShortVowel == hasShortVowel;
    }
    return true;
  }
}

/// 子音クラス
enum ConsonantClass {
  high,
  middle,
  low,
  unknown;

  String displayName(L10n l10n) {
    switch (this) {
      case ConsonantClass.high:
        return l10n.consonantClassHigh;
      case ConsonantClass.middle:
        return l10n.consonantClassMiddle;
      case ConsonantClass.low:
        return l10n.consonantClassLow;
      case ConsonantClass.unknown:
        return l10n.commonUnknownShort;
    }
  }

  String get exampleConsonants {
    switch (this) {
      case ConsonantClass.high:
        return 'ข ฉ ถ ผ ฝ ศ ษ ส ห';
      case ConsonantClass.middle:
        return 'ก จ ด ต บ ป อ';
      case ConsonantClass.low:
        return 'ค ง ช ซ ฑ ฒ ท น พ ฟ ม ย ร ฤ ล ฦ ว ฮ';
      case ConsonantClass.unknown:
        return '';
    }
  }
}

/// 声調記号
enum ToneMark {
  none,
  maiEk, // ่
  maiTho, // ้
  maiTri, // ๊
  maiChattawa; // ๋

  String displayName(L10n l10n) {
    switch (this) {
      case ToneMark.none:
        return l10n.toneMarkNone;
      case ToneMark.maiEk:
        return l10n.toneMarkMaiEk;
      case ToneMark.maiTho:
        return l10n.toneMarkMaiTho;
      case ToneMark.maiTri:
        return l10n.toneMarkMaiTri;
      case ToneMark.maiChattawa:
        return l10n.toneMarkMaiChattawa;
    }
  }

  String symbol(L10n l10n) {
    switch (this) {
      case ToneMark.none:
        return l10n.toneMarkSymbolNone;
      case ToneMark.maiEk:
        return '่';
      case ToneMark.maiTho:
        return '้';
      case ToneMark.maiTri:
        return '๊';
      case ToneMark.maiChattawa:
        return '๋';
    }
  }
}

/// 音節タイプ
enum SyllableType {
  live, // 生音節
  dead, // 死音節
  unknown;

  String displayName(L10n l10n) {
    switch (this) {
      case SyllableType.live:
        return l10n.syllableLive;
      case SyllableType.dead:
        return l10n.syllableDead;
      case SyllableType.unknown:
        return l10n.commonUnknownShort;
    }
  }

  /// 母音の長短を含む表示名（低子音の死音節で使用）
  String getDisplayNameWithVowel(L10n l10n, {bool? hasShortVowel}) {
    if (this == SyllableType.dead && hasShortVowel != null) {
      return hasShortVowel ? l10n.syllableDeadShort : l10n.syllableDeadLong;
    }
    return displayName(l10n);
  }

  String description(L10n l10n) {
    switch (this) {
      case SyllableType.live:
        return l10n.syllableLiveDesc;
      case SyllableType.dead:
        return l10n.syllableDeadDesc;
      case SyllableType.unknown:
        return '';
    }
  }
}

/// タイ語の声調
enum ThaiTone {
  mid, // 平声（第1声調）
  low, // 低声（第2声調）
  falling, // 下降声（第3声調）
  high, // 高声（第4声調）
  rising, // 上昇声（第5声調）
  unknown;

  String displayName(L10n l10n) {
    switch (this) {
      case ThaiTone.mid:
        return l10n.toneMid;
      case ThaiTone.low:
        return l10n.toneLow;
      case ThaiTone.falling:
        return l10n.toneFalling;
      case ThaiTone.high:
        return l10n.toneHigh;
      case ThaiTone.rising:
        return l10n.toneRising;
      case ThaiTone.unknown:
        return l10n.commonUnknownShort;
    }
  }

  String get symbol {
    switch (this) {
      case ThaiTone.mid:
        return '—';
      case ThaiTone.low:
        return '\\';
      case ThaiTone.falling:
        return '^';
      case ThaiTone.high:
        return '/';
      case ThaiTone.rising:
        return 'v';
      case ThaiTone.unknown:
        return '?';
    }
  }
}

/// 音節パース結果（内部用）
class _SyllableComponents {
  final String initialConsonant;
  final ConsonantClass consonantClass;
  final ToneMark toneMark;
  final SyllableType syllableType;
  final bool hasShortVowel;

  _SyllableComponents({
    required this.initialConsonant,
    required this.consonantClass,
    required this.toneMark,
    required this.syllableType,
    required this.hasShortVowel,
  });

  factory _SyllableComponents.empty() => _SyllableComponents(
        initialConsonant: '',
        consonantClass: ConsonantClass.unknown,
        toneMark: ToneMark.none,
        syllableType: SyllableType.unknown,
        hasShortVowel: false,
      );
}
