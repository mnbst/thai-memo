import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

import '../../core/database_constants.dart';
import 'syllable.dart';

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

  /// Syllable breakdown for tone analysis
  final List<Syllable>? syllables;

  WordBreakdown({
    this.id,
    this.sentenceId,
    required this.wordText,
    required this.pronunciation,
    required this.meaning,
    this.grammaticalRole,
    this.wordOrder,
    this.syllables,
  });

  /// Create a WordBreakdown from JSON
  factory WordBreakdown.fromJson(Map<String, dynamic> json) =>
      _$WordBreakdownFromJson(json);

  /// Convert WordBreakdown to JSON
  Map<String, dynamic> toJson() => _$WordBreakdownToJson(this);

  /// Create a WordBreakdown from database map
  factory WordBreakdown.fromDatabase(Map<String, dynamic> map) {
    List<Syllable>? syllables;
    final syllablesJson = map[DatabaseConstants.columnSyllablesJson] as String?;
    if (syllablesJson != null && syllablesJson.isNotEmpty) {
      try {
        final List<dynamic> syllablesList = jsonDecode(syllablesJson);
        syllables = syllablesList
            .map((json) => Syllable.fromJson(json as Map<String, dynamic>))
            .toList();
      } catch (e) {
        // Silently ignore JSON parse errors
        syllables = null;
      }
    }

    return WordBreakdown(
      id: map[DatabaseConstants.columnWordId] as String?,
      sentenceId: map[DatabaseConstants.columnWordSentenceId] as String?,
      wordText: map[DatabaseConstants.columnWordText] as String,
      pronunciation: map[DatabaseConstants.columnWordPronunciation] as String,
      meaning: map[DatabaseConstants.columnWordMeaning] as String,
      grammaticalRole: map[DatabaseConstants.columnGrammaticalRole] as String?,
      wordOrder: map[DatabaseConstants.columnWordOrder] as int?,
      syllables: syllables,
    );
  }

  /// Convert WordBreakdown to database map
  Map<String, dynamic> toDatabase() {
    return {
      if (id != null) DatabaseConstants.columnWordId: id,
      if (sentenceId != null) DatabaseConstants.columnWordSentenceId: sentenceId,
      DatabaseConstants.columnWordText: wordText,
      DatabaseConstants.columnWordPronunciation: pronunciation,
      DatabaseConstants.columnWordMeaning: meaning,
      if (grammaticalRole != null)
        DatabaseConstants.columnGrammaticalRole: grammaticalRole,
      if (wordOrder != null) DatabaseConstants.columnWordOrder: wordOrder,
      if (syllables != null)
        DatabaseConstants.columnSyllablesJson:
            jsonEncode(syllables!.map((s) => s.toJson()).toList()),
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
    List<Syllable>? syllables,
  }) {
    return WordBreakdown(
      id: id ?? this.id,
      sentenceId: sentenceId ?? this.sentenceId,
      wordText: wordText ?? this.wordText,
      pronunciation: pronunciation ?? this.pronunciation,
      meaning: meaning ?? this.meaning,
      grammaticalRole: grammaticalRole ?? this.grammaticalRole,
      wordOrder: wordOrder ?? this.wordOrder,
      syllables: syllables ?? this.syllables,
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
