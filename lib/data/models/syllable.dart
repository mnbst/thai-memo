// =============================================================================
// syllable.dart
// タイ語の音節モデル。
// 各単語をさらに音節単位に分解し、声調分析情報を保持する。
// PyThaiNLP（Python側）で音節分割 → ThaiToneAnalyzer（Flutter側）で声調判定。
// 声調は5種類: 平声(mid)、低声(low)、下降声(falling)、高声(high)、上昇声(rising)
// =============================================================================

import 'package:json_annotation/json_annotation.dart';

import '../../core/thai_tone_analyzer.dart';

part 'syllable.g.dart';

/// サーバー由来の syllables を Syllable のリストに変換する。
///
/// サーバー（nlp.segment_syllables）は音節を**文字列の配列**で返すため、
/// Syllable.fromJson をそのまま適用すると型エラーになる。声調情報は
/// ThaiToneAnalyzer でクライアント側に補う。
/// SQLite 由来の Map 形式も受け取れるようにして、呼び出し側が経路を意識せずに済むようにする。
List<Syllable>? parseSyllables(List<dynamic>? raw) {
  if (raw == null) return null;
  return raw
      .map((entry) {
        if (entry is String) return Syllable.fromText(entry);
        if (entry is Map) {
          return Syllable.fromJson(Map<String, dynamic>.from(entry));
        }
        return null;
      })
      .whereType<Syllable>()
      .toList();
}

String _consonantClassToString(ConsonantClass consonantClass) {
  switch (consonantClass) {
    case ConsonantClass.high:
      return 'high';
    case ConsonantClass.middle:
      return 'middle';
    case ConsonantClass.low:
      return 'low';
    case ConsonantClass.unknown:
      return 'unknown';
  }
}

String _toneToString(ThaiTone tone) {
  switch (tone) {
    case ThaiTone.mid:
      return 'mid';
    case ThaiTone.low:
      return 'low';
    case ThaiTone.falling:
      return 'falling';
    case ThaiTone.high:
      return 'high';
    case ThaiTone.rising:
      return 'rising';
    case ThaiTone.unknown:
      return 'unknown';
  }
}

String _toneMarkToString(ToneMark toneMark) {
  switch (toneMark) {
    case ToneMark.none:
      return 'none';
    case ToneMark.maiEk:
      return 'maiEk';
    case ToneMark.maiTho:
      return 'maiTho';
    case ToneMark.maiTri:
      return 'maiTri';
    case ToneMark.maiChattawa:
      return 'maiChattawa';
  }
}

String _syllableTypeToString(SyllableType syllableType) {
  switch (syllableType) {
    case SyllableType.live:
      return 'live';
    case SyllableType.dead:
      return 'dead';
    case SyllableType.unknown:
      return 'unknown';
  }
}

/// タイ語の音節情報
///
/// 例: "สวัส" → text: "สวัส", initialConsonant: "ส", consonantClass: "high",
///     tone: "rising", toneMark: "none", syllableType: "dead"
@JsonSerializable()
class Syllable {
  /// 音節のテキスト（例: "สวัส"）
  final String text;

  /// 主子音（声調を決める子音）（例: "ส"）
  @JsonKey(name: 'initial_consonant')
  final String initialConsonant;

  /// 子音クラス（high/middle/low）
  @JsonKey(name: 'consonant_class')
  final String consonantClass;

  /// 結果の声調（mid/low/falling/high/rising）
  final String tone;

  /// 声調記号（none/maiEk/maiTho/maiTri/maiChattawa）
  @JsonKey(name: 'tone_mark')
  final String toneMark;

  /// 音節タイプ（live/dead）
  @JsonKey(name: 'syllable_type')
  final String syllableType;

  /// 短母音かどうか（省略可能）
  @JsonKey(name: 'has_short_vowel')
  final bool? hasShortVowel;

  Syllable({
    required this.text,
    required this.initialConsonant,
    required this.consonantClass,
    required this.tone,
    required this.toneMark,
    required this.syllableType,
    this.hasShortVowel,
  });

  /// Create a Syllable from JSON
  factory Syllable.fromJson(Map<String, dynamic> json) =>
      _$SyllableFromJson(json);

  /// 音節テキストだけから声調を解析して組み立てる。
  factory Syllable.fromText(String text) {
    final analysis = ThaiToneAnalyzer.analyzeTone(text);
    return Syllable(
      text: text,
      initialConsonant: analysis.initialConsonant ?? '',
      consonantClass: _consonantClassToString(analysis.consonantClass),
      tone: _toneToString(analysis.resultingTone),
      toneMark: _toneMarkToString(analysis.toneMark),
      syllableType: _syllableTypeToString(analysis.syllableType),
      hasShortVowel: analysis.hasShortVowel,
    );
  }

  /// Convert Syllable to JSON
  Map<String, dynamic> toJson() => _$SyllableToJson(this);

  @override
  String toString() {
    return 'Syllable(text: $text, consonant: $initialConsonant, '
        'class: $consonantClass, tone: $tone, toneMark: $toneMark, '
        'syllableType: $syllableType, hasShortVowel: $hasShortVowel)';
  }
}
