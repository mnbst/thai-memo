import 'package:json_annotation/json_annotation.dart';

part 'syllable.g.dart';

/// タイ語の音節情報
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

  /// Factory constructor that creates a Syllable with tone analysis
  /// from minimal data (text and initial_consonant only)
  factory Syllable.fromMinimalJson(Map<String, dynamic> json, {
    required String consonantClass,
    required String tone,
    required String toneMark,
    required String syllableType,
    bool? hasShortVowel,
  }) {
    return Syllable(
      text: json['text'] as String,
      initialConsonant: json['initial_consonant'] as String,
      consonantClass: consonantClass,
      tone: tone,
      toneMark: toneMark,
      syllableType: syllableType,
      hasShortVowel: hasShortVowel,
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
