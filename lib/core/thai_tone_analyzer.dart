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
    '\u0E34', // ิ
    '\u0E36', // ึ
    '\u0E38', // ุ
  ];

  // 死音節の末子音（-p, -t, -k）
  static const deadEndConsonants = [
    'ป',
    'บ',
    'พ',
    'ภ',
    'ฟ',
    'ต',
    'ด',
    'ท',
    'ธ',
    'ฏ',
    'ฎ',
    'จ',
    'ช',
    'ซ',
    'ก',
    'ข',
    'ค'
  ];

  // 生音節の末子音（-m, -n, -ng, -y, -w）
  static const liveEndConsonants = ['ม', 'น', 'ง', 'ญ', 'ย', 'ว'];

  // 前置母音（leading vowels）
  static const leadingVowels = [
    'เ', // e
    'แ', // ae
    'โ', // o
    'ใ', // ai (mai malai)
    'ไ', // ai (mai muan)
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

    // 主子音を取得（前置母音を考慮）
    final firstChar = _getInitialConsonant(thaiWord);

    // 声調計算用の子音を取得（ห+低子音、子音クラスター対応）
    final consonantForTone = _getConsonantForTone(thaiWord);
    final consonantClass = _getConsonantClass(consonantForTone);

    // 声調記号を検出
    final toneMark = _detectToneMark(thaiWord);

    // 母音の長短を判定
    final hasShortVowel = _hasShortVowel(thaiWord);

    // 音節タイプを判定（生音節/死音節）
    final syllableType = _analyzeSyllableType(thaiWord);

    // 声調を決定
    final resultingTone = _determineTone(
      consonantClass,
      toneMark,
      syllableType,
      hasShortVowel,
    );

    // 解説文を生成
    final explanation = _generateExplanation(
      thaiWord,
      consonantClass,
      toneMark,
      syllableType,
      resultingTone,
    );

    return ToneAnalysis(
      consonantClass: consonantClass,
      toneMark: toneMark,
      syllableType: syllableType,
      resultingTone: resultingTone,
      explanation: explanation,
      initialConsonant: firstChar,
      hasShortVowel: hasShortVowel,
    );
  }

  /// 主子音を取得（前置母音を考慮）
  static String _getInitialConsonant(String word) {
    if (word.isEmpty) return '';

    // 前置母音をチェック
    final firstChar = word[0];
    if (leadingVowels.contains(firstChar)) {
      // 前置母音がある場合、次の文字が主子音
      if (word.length > 1) {
        return word[1];
      }
      return '';
    }

    // 前置母音がない場合、最初の文字が主子音
    return firstChar;
  }

  /// 声調計算用の子音を取得（ห+低子音、子音クラスター対応）
  static String _getConsonantForTone(String word) {
    if (word.isEmpty) return '';

    // 前置母音をスキップして、実際の子音部分を取得
    int startIndex = 0;
    if (word.isNotEmpty && leadingVowels.contains(word[0])) {
      startIndex = 1;
    }

    if (startIndex >= word.length) return '';

    final firstConsonant = word[startIndex];

    // อ + 子音の処理（อ は声調に関与しない）
    // 例: อยาก → ย、อ้วน → ว
    // ただし、อา など อ + 母音のみの場合は อ を使う
    if (firstConsonant == 'อ' && startIndex + 1 < word.length) {
      // 声調記号をスキップして次の文字を探す
      int nextIndex = startIndex + 1;
      while (nextIndex < word.length && _isToneMark(word[nextIndex])) {
        nextIndex++;
      }

      if (nextIndex < word.length) {
        final nextChar = word[nextIndex];
        // 次の文字が子音の場合、その子音を使う（อ を無視）
        if (_isConsonant(nextChar)) {
          // startIndexを更新して、以降の処理で正しい位置から開始
          return _getConsonantForTone(word.substring(nextIndex));
        }
      }
      // 次が母音の場合は อ を使う
      return 'อ';
    }

    // 特殊な発音変化の組み合わせ（優先処理）
    if (startIndex + 1 < word.length) {
      final secondChar = word[startIndex + 1];

      // ทร → ซ (ソー) の音に変化、声調も ซ（低子音）で計算
      if (firstConsonant == 'ท' && secondChar == 'ร') {
        return 'ซ';
      }

      // ศร → ส (スー) の音に変化、声調も ส（高子音）で計算
      if (firstConsonant == 'ศ' && secondChar == 'ร') {
        return 'ส';
      }

      // จร → จ（中子音）として計算（クラスター扱いしない）
      if (firstConsonant == 'จ' && secondChar == 'ร') {
        return 'จ';
      }
    }

    // ห + 低子音の特別処理
    // หม, หน, หง, หญ, หย, หร, หล, หว, หฬ など
    if (firstConsonant == 'ห' && startIndex + 1 < word.length) {
      final secondChar = word[startIndex + 1];
      // 次の文字が子音で、かつ低子音の場合
      if (_isConsonant(secondChar) && lowConsonants.contains(secondChar)) {
        // 声調計算には ห（高子音）を使用
        return 'ห';
      }
    }

    // 子音クラスターの処理（母音に近い子音を使用）
    // 例: ครับ → ร、กรุง → ร、ปลา → ล
    if (startIndex + 1 < word.length) {
      final secondChar = word[startIndex + 1];
      // 2文字目が ร, ล, ว の場合、子音クラスターの可能性をチェック
      if (secondChar == 'ร' || secondChar == 'ล' || secondChar == 'ว') {
        // 第1子音がクラスターを形成できる子音か確認
        // ก, ข, ค, ต, ท, ด, ป, พ, ผ, ฟ, ภ, บ など
        final clusterFormingConsonants = [
          'ก', 'ข', 'ค', 'ฅ', 'ฆ', // ก系
          'ต', 'ท', 'ธ', 'ด', // ต系
          'ป', 'พ', 'ผ', 'ฟ', 'ภ', 'บ', // ป系
        ];

        if (clusterFormingConsonants.contains(firstConsonant)) {
          // 母音に近い方（2番目の子音）を返す
          return secondChar;
        }
      }
    }

    // 通常の場合は最初の子音を返す
    return firstConsonant;
  }

  /// 文字が子音かどうかを判定
  static bool _isConsonant(String char) {
    return highConsonants.contains(char) ||
        middleConsonants.contains(char) ||
        lowConsonants.contains(char);
  }

  /// 文字が声調記号かどうかを判定
  static bool _isToneMark(String char) {
    return char == toneMark1 ||
        char == toneMark2 ||
        char == toneMark3 ||
        char == toneMark4;
  }

  /// 子音のクラスを判定
  static ConsonantClass _getConsonantClass(String consonant) {
    if (highConsonants.contains(consonant)) {
      return ConsonantClass.high;
    } else if (middleConsonants.contains(consonant)) {
      return ConsonantClass.middle;
    } else if (lowConsonants.contains(consonant)) {
      return ConsonantClass.low;
    }
    return ConsonantClass.unknown;
  }

  /// 声調記号を検出
  static ToneMark _detectToneMark(String word) {
    if (word.contains(toneMark1)) return ToneMark.maiEk;
    if (word.contains(toneMark2)) return ToneMark.maiTho;
    if (word.contains(toneMark3)) return ToneMark.maiTri;
    if (word.contains(toneMark4)) return ToneMark.maiChattawa;
    return ToneMark.none;
  }

  /// 短母音を含むかチェック
  static bool _hasShortVowel(String word) {
    if (word.isEmpty) return false;
    for (final vowel in shortVowels) {
      if (word.contains(vowel)) {
        return true;
      }
    }
    return false;
  }

  /// 音節タイプを分析（生音節/死音節）
  static SyllableType _analyzeSyllableType(String word) {
    if (word.isEmpty) return SyllableType.unknown;

    // 短母音を含むかチェック
    final hasShortVowel = shortVowels.any((v) => word.contains(v));

    // 最後の文字を確認
    final lastChar = word[word.length - 1];

    // 死音節の条件：短母音 + 末子音なし、または -p, -t, -k で終わる
    if (hasShortVowel &&
        !liveEndConsonants.contains(lastChar) &&
        !deadEndConsonants.contains(lastChar)) {
      return SyllableType.dead; // 短母音で末子音なし
    }

    if (deadEndConsonants.contains(lastChar)) {
      return SyllableType.dead; // -p, -t, -k で終わる
    }

    // 生音節の条件：長母音、または -m, -n, -ng, -y, -w で終わる
    if (liveEndConsonants.contains(lastChar)) {
      return SyllableType.live;
    }

    // デフォルトは生音節
    return SyllableType.live;
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
