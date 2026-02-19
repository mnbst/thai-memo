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

  // 短母音
  static const shortVowels = [
    'อะ',
    'อิ',
    'อึ',
    'อุ',
    'เอะ',
    'แอะ',
    'โอะ',
    'เออะ',
    'เอาะ',
    '\u0E30', // ะ
    '\u0E31', // ั (mai han akat = 短母音 อะ の閉音節形)
    '\u0E34', // ิ
    '\u0E36', // ึ
    '\u0E38', // ุ
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

  // 生音節の末子音（-m, -n, -ng, -y, -w）
  static const liveEndConsonants = ['ม', 'น', 'ง', 'ญ', 'ย', 'ว'];

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

    // 例外: อ + ย/ร/ล/ว → อは無音、次の子音を使用
    if (firstConsonant == 'อ' && pos + 1 < word.length) {
      int nextPos = pos + 1;
      while (nextPos < word.length && _isToneMark(word[nextPos])) nextPos++;
      if (nextPos < word.length &&
          const ['ย', 'ร', 'ล', 'ว'].contains(word[nextPos])) {
        initialConsonant = word[nextPos];
        consonantForTone = word[nextPos];
      }
    }

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
    final lastChar = word[word.length - 1];
    SyllableType syllableType;
    if (deadEndConsonants.contains(lastChar)) {
      syllableType = SyllableType.dead;
    } else if (liveEndConsonants.contains(lastChar)) {
      syllableType = SyllableType.live;
    } else {
      syllableType = SyllableType.live; // デフォルト、短母音で上書き
    }

    // 5. 母音の長短を判定
    bool hasShortVowel = false;
    if (shortVowels.any((v) => word.contains(v))) {
      hasShortVowel = true;
    } else if (!_allVowelChars.any((v) => word.contains(v))) {
      // 明示的な母音なし → 頭子音の後にอがあれば母音ออ（長母音）、なければ暗黙の短母音
      int i = pos + 1;
      if (i < word.length && _isClusterSecondConsonant(word[i])) i++;
      while (i < word.length && _isToneMark(word[i])) i++;
      hasShortVowel = !(i < word.length && word[i] == 'อ');
    }

    // 短母音 + 末子音なし → 死音節
    if (hasShortVowel &&
        !deadEndConsonants.contains(lastChar) &&
        !liveEndConsonants.contains(lastChar)) {
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

  // 母音文字（明示的に書かれる母音すべて）
  static const _allVowelChars = [
    '\u0E30', // ะ
    '\u0E31', // ั (mai han akat)
    '\u0E32', // า
    '\u0E33', // ำ
    '\u0E34', // ิ
    '\u0E35', // ี
    '\u0E36', // ึ
    '\u0E37', // ื
    '\u0E38', // ุ
    '\u0E39', // ู
    'เ',
    'แ',
    'โ',
    'ใ',
    'ไ',
  ];

  /// タイ語の単語を分析して声調情報を返す
  static ToneAnalysis analyzeTone(String thaiWord) {
    if (thaiWord.isEmpty) {
      return ToneAnalysis(
        consonantClass: ConsonantClass.unknown,
        toneMark: ToneMark.none,
        syllableType: SyllableType.unknown,
        resultingTone: ThaiTone.unknown,
        explanation: '単語が空です',
        hasShortVowel: false,
      );
    }

    final c = _parseSyllable(thaiWord);

    final resultingTone = _determineTone(
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

  String get displayName {
    switch (this) {
      case ConsonantClass.high:
        return '高子音';
      case ConsonantClass.middle:
        return '中子音';
      case ConsonantClass.low:
        return '低子音';
      case ConsonantClass.unknown:
        return '不明';
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

  String get displayName {
    switch (this) {
      case ToneMark.none:
        return '声調記号なし';
      case ToneMark.maiEk:
        return 'マイエーク';
      case ToneMark.maiTho:
        return 'マイトー';
      case ToneMark.maiTri:
        return 'マイトリー';
      case ToneMark.maiChattawa:
        return 'マイチャッタワー';
    }
  }

  String get symbol {
    switch (this) {
      case ToneMark.none:
        return 'なし';
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

  String get displayName {
    switch (this) {
      case SyllableType.live:
        return '生音節';
      case SyllableType.dead:
        return '死音節';
      case SyllableType.unknown:
        return '不明';
    }
  }

  /// 母音の長短を含む表示名（低子音の死音節で使用）
  String getDisplayNameWithVowel({bool? hasShortVowel}) {
    if (this == SyllableType.dead && hasShortVowel != null) {
      return hasShortVowel ? '死音節（短母音）' : '死音節（長母音・複合母音）';
    }
    return displayName;
  }

  String get description {
    switch (this) {
      case SyllableType.live:
        return '長母音 または -m, -n, -ng, -y, -w で終わる';
      case SyllableType.dead:
        return '短母音で末子音なし または -p, -t, -k で終わる';
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

  String get displayName {
    switch (this) {
      case ThaiTone.mid:
        return '平声';
      case ThaiTone.low:
        return '低声';
      case ThaiTone.falling:
        return '下降声';
      case ThaiTone.high:
        return '高声';
      case ThaiTone.rising:
        return '上昇声';
      case ThaiTone.unknown:
        return '不明';
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
