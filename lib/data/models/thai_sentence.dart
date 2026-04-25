// =============================================================================
// thai_sentence.dart
// タイ語例文のデータモデル。
// Gemini AIが生成した例文（タイ語本文・発音・日本語訳・単語分解・文脈情報）を保持する。
// JSON変換（API通信用）とSQLite変換（ローカル保存用）の両方に対応。
// json_serializableによる自動コード生成を使用（thai_sentence.g.dart）。
// =============================================================================

import 'package:json_annotation/json_annotation.dart';
import 'word_breakdown.dart';

part 'thai_sentence.g.dart';

/// 学習情報を含むタイ語例文モデル
///
/// Cloud Functionsから返される例文データを表現するメインモデル。
/// 1つの例文に対して複数のWordBreakdown（単語分解）を持つ。
/// データフロー:
///   Cloud Function → JSON → ThaiSentence → SQLite (toDatabase/fromDatabase)
@JsonSerializable(explicitToJson: true)
class ThaiSentence {
  /// 一意な識別子
  final String? id;

  /// タイ語の例文本文
  @JsonKey(name: 'thai_text')
  final String thaiText;

  /// 発音（ローマ字）
  final String pronunciation;

  /// 日本語訳
  @JsonKey(name: 'japanese_translation')
  final String japaneseTranslation;

  /// 単語ごとの分解情報
  @JsonKey(name: 'word_breakdown')
  final List<WordBreakdown> wordBreakdowns;

  /// 例文の文脈情報
  final SentenceContext? context;

  /// 例文の作成日時
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;

  /// 生成時に使われた仕様（free / premium）
  @JsonKey(name: 'generation_tier')
  final String? generationTier;

  /// 生成時に選定されたターゲット単語
  @JsonKey(name: 'target_words')
  final List<String>? targetWords;

  bool get wasGeneratedWithPremiumSpec => generationTier == 'premium';

  ThaiSentence({
    this.id,
    required this.thaiText,
    required this.pronunciation,
    required this.japaneseTranslation,
    required this.wordBreakdowns,
    this.context,
    this.createdAt,
    this.generationTier,
    this.targetWords,
  });

  /// JSONからThaiSentenceを生成
  factory ThaiSentence.fromJson(Map<String, dynamic> json) =>
      _$ThaiSentenceFromJson(json);

  /// ThaiSentenceをJSONへ変換
  Map<String, dynamic> toJson() => _$ThaiSentenceToJson(this);

  /// データベースのMapからThaiSentenceを生成
  factory ThaiSentence.fromDatabase(
    Map<String, dynamic> map,
    List<WordBreakdown> wordBreakdowns,
  ) {
    final targetWordsRaw = map['target_words'] as String?;
    List<String>? targetWords;
    if (targetWordsRaw != null && targetWordsRaw.isNotEmpty) {
      targetWords = targetWordsRaw.split(',');
    }

    return ThaiSentence(
      id: map['id'] as String?,
      thaiText: map['thai_text'] as String,
      pronunciation: map['pronunciation'] as String,
      japaneseTranslation: map['japanese_translation'] as String,
      wordBreakdowns: wordBreakdowns,
      context: SentenceContext.fromDatabase(map),
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
          : null,
      generationTier: map['generation_tier'] as String?,
      targetWords: targetWords,
    );
  }

  /// ThaiSentenceをデータベース保存用Mapへ変換（wordBreakdownsを除く）
  Map<String, dynamic> toDatabase() {
    return {
      if (id != null) 'id': id,
      'thai_text': thaiText,
      'pronunciation': pronunciation,
      'japanese_translation': japaneseTranslation,
      'context_explanation': context?.getFullExplanation() ?? '',
      'topic': context?.topic,
      'style': context?.style,
      'emotion': context?.emotion,
      'usage_scenarios': context?.usageScenarios,
      if (createdAt != null) 'created_at': createdAt!.millisecondsSinceEpoch,
      'generation_tier': generationTier,
      'target_words': targetWords?.join(','),
    };
  }

  /// 指定値を上書きしたコピーを生成
  ThaiSentence copyWith({
    String? id,
    String? thaiText,
    String? pronunciation,
    String? japaneseTranslation,
    List<WordBreakdown>? wordBreakdowns,
    SentenceContext? context,
    DateTime? createdAt,
    String? generationTier,
    List<String>? targetWords,
  }) {
    return ThaiSentence(
      id: id ?? this.id,
      thaiText: thaiText ?? this.thaiText,
      pronunciation: pronunciation ?? this.pronunciation,
      japaneseTranslation: japaneseTranslation ?? this.japaneseTranslation,
      wordBreakdowns: wordBreakdowns ?? this.wordBreakdowns,
      context: context ?? this.context,
      createdAt: createdAt ?? this.createdAt,
      generationTier: generationTier ?? this.generationTier,
      targetWords: targetWords ?? this.targetWords,
    );
  }

  @override
  String toString() {
    return 'ThaiSentence(id: $id, thaiText: $thaiText, '
        'wordBreakdowns: ${wordBreakdowns.length}, '
        'generationTier: $generationTier, '
        'createdAt: $createdAt)';
  }
}

/// タイ語例文の文脈情報
@JsonSerializable()
class SentenceContext {
  /// この表現を使う場面・場所
  final String? topic;

  /// 文体スタイル
  final String? style;

  /// 感情・トーン（フォーマル/カジュアル/丁寧/親しみ）
  final String? emotion;

  /// 具体的な使用シーン
  @JsonKey(name: 'usage_scenarios')
  final String? usageScenarios;

  /// 文化的背景やニュアンス
  @JsonKey(name: 'cultural_notes')
  final String? culturalNotes;

  SentenceContext({
    this.topic,
    this.style,
    this.emotion,
    this.usageScenarios,
    this.culturalNotes,
  });

  /// JSONからSentenceContextを生成
  factory SentenceContext.fromJson(Map<String, dynamic> json) =>
      _$SentenceContextFromJson(json);

  /// SentenceContextをJSONへ変換
  Map<String, dynamic> toJson() => _$SentenceContextToJson(this);

  /// データベースのMapからSentenceContextを生成
  factory SentenceContext.fromDatabase(Map<String, dynamic> map) {
    return SentenceContext(
      topic: map['topic'] as String?,
      style: map['style'] as String?,
      emotion: map['emotion'] as String?,
      usageScenarios: map['usage_scenarios'] as String?,
      // culturalNotesはcontext_explanationに統合して保存する
      culturalNotes: null,
    );
  }

  /// すべての文脈項目を結合した説明文を取得
  String getFullExplanation() {
    final parts = <String>[];

    if (topic != null && topic!.isNotEmpty) {
      parts.add('【場面】$topic');
    }
    if (style != null && style!.isNotEmpty) {
      parts.add('【文体】$style');
    }
    if (emotion != null && emotion!.isNotEmpty) {
      parts.add('【トーン】$emotion');
    }
    if (usageScenarios != null && usageScenarios!.isNotEmpty) {
      parts.add('【使用シーン】$usageScenarios');
    }
    if (culturalNotes != null && culturalNotes!.isNotEmpty) {
      parts.add('【文化的背景】$culturalNotes');
    }

    return parts.join('\n\n');
  }

  /// 指定値を上書きしたコピーを生成
  SentenceContext copyWith({
    String? topic,
    String? style,
    String? emotion,
    String? usageScenarios,
    String? culturalNotes,
  }) {
    return SentenceContext(
      topic: topic ?? this.topic,
      style: style ?? this.style,
      emotion: emotion ?? this.emotion,
      usageScenarios: usageScenarios ?? this.usageScenarios,
      culturalNotes: culturalNotes ?? this.culturalNotes,
    );
  }

  @override
  String toString() {
    return 'SentenceContext(topic: $topic, style: $style, emotion: $emotion, '
        'usageScenarios: $usageScenarios, culturalNotes: $culturalNotes)';
  }
}
