// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'word_breakdown.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WordBreakdown _$WordBreakdownFromJson(Map<String, dynamic> json) =>
    WordBreakdown(
      id: json['id'] as String?,
      sentenceId: json['sentence_id'] as String?,
      wordText: json['word'] as String,
      pronunciation: json['pronunciation'] as String,
      meaning: json['meaning'] as String,
      grammaticalRole: json['grammatical_role'] as String?,
      wordOrder: (json['word_order'] as num?)?.toInt(),
      syllables: (json['syllables'] as List<dynamic>?)
          ?.map((e) => Syllable.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$WordBreakdownToJson(WordBreakdown instance) =>
    <String, dynamic>{
      'id': instance.id,
      'sentence_id': instance.sentenceId,
      'word': instance.wordText,
      'pronunciation': instance.pronunciation,
      'meaning': instance.meaning,
      'grammatical_role': instance.grammaticalRole,
      'word_order': instance.wordOrder,
      'syllables': instance.syllables,
    };
