// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'syllable.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Syllable _$SyllableFromJson(Map<String, dynamic> json) => Syllable(
      text: json['text'] as String,
      initialConsonant: json['initial_consonant'] as String,
      consonantClass: json['consonant_class'] as String,
      tone: json['tone'] as String,
      toneMark: json['tone_mark'] as String,
      syllableType: json['syllable_type'] as String,
      hasShortVowel: json['has_short_vowel'] as bool?,
    );

Map<String, dynamic> _$SyllableToJson(Syllable instance) => <String, dynamic>{
      'text': instance.text,
      'initial_consonant': instance.initialConsonant,
      'consonant_class': instance.consonantClass,
      'tone': instance.tone,
      'tone_mark': instance.toneMark,
      'syllable_type': instance.syllableType,
      'has_short_vowel': instance.hasShortVowel,
    };
