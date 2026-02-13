import 'package:json_annotation/json_annotation.dart';

part 'word_breakdown.g.dart';

/// Model for individual word breakdown in a Thai sentence
@JsonSerializable()
class WordBreakdown {
  /// Unique identifier for the word breakdown
  final String? id;

  /// ID of the sentence this word belongs to
  @JsonKey(name: 'sentence_id')
  final String? sentenceId;

  /// The Thai word/phrase
  @JsonKey(name: 'word')
  final String wordText;

  /// Romanized pronunciation of the word
  final String pronunciation;

  /// Japanese translation/meaning of the word
  final String meaning;

  /// Grammatical role (e.g., 名詞, 動詞, 形容詞, 助詞)
  @JsonKey(name: 'grammatical_role')
  final String? grammaticalRole;

  /// Order of the word in the sentence (for sorting)
  @JsonKey(name: 'word_order')
  final int? wordOrder;

  WordBreakdown({
    this.id,
    this.sentenceId,
    required this.wordText,
    required this.pronunciation,
    required this.meaning,
    this.grammaticalRole,
    this.wordOrder,
  });

  /// Create a WordBreakdown from JSON
  factory WordBreakdown.fromJson(Map<String, dynamic> json) =>
      _$WordBreakdownFromJson(json);

  /// Convert WordBreakdown to JSON
  Map<String, dynamic> toJson() => _$WordBreakdownToJson(this);

  /// Create a WordBreakdown from database map
  factory WordBreakdown.fromDatabase(Map<String, dynamic> map) {
    return WordBreakdown(
      id: map['id'] as String?,
      sentenceId: map['sentence_id'] as String?,
      wordText: map['word_text'] as String,
      pronunciation: map['pronunciation'] as String,
      meaning: map['meaning'] as String,
      grammaticalRole: map['grammatical_role'] as String?,
      wordOrder: map['word_order'] as int?,
    );
  }

  /// Convert WordBreakdown to database map
  Map<String, dynamic> toDatabase() {
    return {
      if (id != null) 'id': id,
      if (sentenceId != null) 'sentence_id': sentenceId,
      'word_text': wordText,
      'pronunciation': pronunciation,
      'meaning': meaning,
      if (grammaticalRole != null) 'grammatical_role': grammaticalRole,
      if (wordOrder != null) 'word_order': wordOrder,
    };
  }

  /// Create a copy with updated values
  WordBreakdown copyWith({
    String? id,
    String? sentenceId,
    String? wordText,
    String? pronunciation,
    String? meaning,
    String? grammaticalRole,
    int? wordOrder,
  }) {
    return WordBreakdown(
      id: id ?? this.id,
      sentenceId: sentenceId ?? this.sentenceId,
      wordText: wordText ?? this.wordText,
      pronunciation: pronunciation ?? this.pronunciation,
      meaning: meaning ?? this.meaning,
      grammaticalRole: grammaticalRole ?? this.grammaticalRole,
      wordOrder: wordOrder ?? this.wordOrder,
    );
  }

  @override
  String toString() {
    return 'WordBreakdown(id: $id, wordText: $wordText, '
        'pronunciation: $pronunciation, meaning: $meaning, '
        'grammaticalRole: $grammaticalRole, wordOrder: $wordOrder)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is WordBreakdown &&
        other.id == id &&
        other.sentenceId == sentenceId &&
        other.wordText == wordText &&
        other.pronunciation == pronunciation &&
        other.meaning == meaning &&
        other.grammaticalRole == grammaticalRole &&
        other.wordOrder == wordOrder;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        sentenceId.hashCode ^
        wordText.hashCode ^
        pronunciation.hashCode ^
        meaning.hashCode ^
        grammaticalRole.hashCode ^
        wordOrder.hashCode;
  }
}
