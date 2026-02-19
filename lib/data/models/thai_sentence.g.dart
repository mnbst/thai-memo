// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thai_sentence.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ThaiSentence _$ThaiSentenceFromJson(Map<String, dynamic> json) => ThaiSentence(
      id: json['id'] as String?,
      thaiText: json['thai_text'] as String,
      pronunciation: json['pronunciation'] as String,
      japaneseTranslation: json['japanese_translation'] as String,
      wordBreakdowns: (json['word_breakdown'] as List<dynamic>)
          .map((e) => WordBreakdown.fromJson(e as Map<String, dynamic>))
          .toList(),
      context: json['context'] == null
          ? null
          : SentenceContext.fromJson(json['context'] as Map<String, dynamic>),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      isFavorite: json['is_favorite'] as bool? ?? false,
    );

Map<String, dynamic> _$ThaiSentenceToJson(ThaiSentence instance) =>
    <String, dynamic>{
      'id': instance.id,
      'thai_text': instance.thaiText,
      'pronunciation': instance.pronunciation,
      'japanese_translation': instance.japaneseTranslation,
      'word_breakdown': instance.wordBreakdowns.map((e) => e.toJson()).toList(),
      'context': instance.context?.toJson(),
      'created_at': instance.createdAt?.toIso8601String(),
      'is_favorite': instance.isFavorite,
    };

SentenceContext _$SentenceContextFromJson(Map<String, dynamic> json) =>
    SentenceContext(
      topic: json['topic'] as String?,
      style: json['style'] as String?,
      emotion: json['emotion'] as String?,
      usageScenarios: json['usage_scenarios'] as String?,
      culturalNotes: json['cultural_notes'] as String?,
    );

Map<String, dynamic> _$SentenceContextToJson(SentenceContext instance) =>
    <String, dynamic>{
      'topic': instance.topic,
      'style': instance.style,
      'emotion': instance.emotion,
      'usage_scenarios': instance.usageScenarios,
      'cultural_notes': instance.culturalNotes,
    };
