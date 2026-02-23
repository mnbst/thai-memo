import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GrammarPoint {
  final String label;
  final String detail;
  const GrammarPoint({required this.label, required this.detail});

  Map<String, dynamic> toJson() => {'label': label, 'detail': detail};
  factory GrammarPoint.fromJson(Map<String, dynamic> json) => GrammarPoint(
        label: json['label'] ?? '',
        detail: json['detail'] ?? '',
      );
}

class PronunciationTip {
  final String thai;
  final String roman;
  final String tip;
  const PronunciationTip(
      {required this.thai, required this.roman, required this.tip});

  Map<String, dynamic> toJson() =>
      {'thai': thai, 'roman': roman, 'tip': tip};
  factory PronunciationTip.fromJson(Map<String, dynamic> json) =>
      PronunciationTip(
        thai: json['thai'] ?? '',
        roman: json['roman'] ?? '',
        tip: json['tip'] ?? '',
      );
}

class RelatedExpression {
  final String thai;
  final String roman;
  final String meaning;
  const RelatedExpression(
      {required this.thai, required this.roman, required this.meaning});

  Map<String, dynamic> toJson() =>
      {'thai': thai, 'roman': roman, 'meaning': meaning};
  factory RelatedExpression.fromJson(Map<String, dynamic> json) =>
      RelatedExpression(
        thai: json['thai'] ?? '',
        roman: json['roman'] ?? '',
        meaning: json['meaning'] ?? '',
      );
}

class ReviewNotes {
  final List<GrammarPoint> grammarPoints;
  final List<PronunciationTip> pronunciationTips;
  final List<RelatedExpression> relatedExpressions;

  const ReviewNotes({
    this.grammarPoints = const [],
    this.pronunciationTips = const [],
    this.relatedExpressions = const [],
  });

  bool get isEmpty =>
      grammarPoints.isEmpty &&
      pronunciationTips.isEmpty &&
      relatedExpressions.isEmpty;

  Map<String, dynamic> toJson() => {
        'grammar_points': grammarPoints.map((e) => e.toJson()).toList(),
        'pronunciation_tips': pronunciationTips.map((e) => e.toJson()).toList(),
        'related_expressions':
            relatedExpressions.map((e) => e.toJson()).toList(),
      };

  factory ReviewNotes.fromJson(Map<String, dynamic> json) => ReviewNotes(
        grammarPoints: (json['grammar_points'] as List<dynamic>?)
                ?.map((e) => GrammarPoint.fromJson(e))
                .toList() ??
            [],
        pronunciationTips: (json['pronunciation_tips'] as List<dynamic>?)
                ?.map((e) => PronunciationTip.fromJson(e))
                .toList() ??
            [],
        relatedExpressions: (json['related_expressions'] as List<dynamic>?)
                ?.map((e) => RelatedExpression.fromJson(e))
                .toList() ??
            [],
      );

  /// FCMから届くJSON文字列をパース。旧形式（プレーン文字列）にもフォールバック
  factory ReviewNotes.parse(String raw) {
    if (raw.isEmpty) return const ReviewNotes();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return ReviewNotes.fromJson(decoded);
      }
    } catch (_) {}
    // 旧形式: プレーンテキスト → grammar_points に1件として格納
    return ReviewNotes(
      grammarPoints: [GrammarPoint(label: '解説', detail: raw)],
    );
  }
}

class ReviewData {
  final String thaiText;
  final String pronunciation;
  final String japaneseTranslation;
  final String reviewNotesRaw;
  final ReviewNotes reviewNotes;

  ReviewData({
    required this.thaiText,
    required this.pronunciation,
    required this.japaneseTranslation,
    required this.reviewNotesRaw,
  }) : reviewNotes = ReviewNotes.parse(reviewNotesRaw);

  Map<String, String> toJson() => {
        'thai_text': thaiText,
        'pronunciation': pronunciation,
        'japanese_translation': japaneseTranslation,
        'review_notes': reviewNotesRaw,
      };

  factory ReviewData.fromJson(Map<String, dynamic> json) => ReviewData(
        thaiText: json['thai_text'] ?? '',
        pronunciation: json['pronunciation'] ?? '',
        japaneseTranslation: json['japanese_translation'] ?? '',
        reviewNotesRaw: json['review_notes'] ?? '',
      );
}

class ReviewNotifier extends StateNotifier<List<ReviewData>> {
  static const _key = 'review_data_list';
  // 旧キー（マイグレーション用）
  static const _legacyKey = 'review_data';

  ReviewNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    // 新形式を優先
    final json = prefs.getString(_key);
    if (json != null) {
      final list = jsonDecode(json) as List<dynamic>;
      state = list.map((e) => ReviewData.fromJson(e)).toList();
      return;
    }

    // 旧形式からマイグレーション
    final legacy = prefs.getString(_legacyKey);
    if (legacy != null) {
      final data = ReviewData.fromJson(jsonDecode(legacy));
      state = [data];
      await _persist();
      await prefs.remove(_legacyKey);
    }
  }

  Future<void> addItem(ReviewData data) async {
    // 同一 thaiText の重複は除外
    final exists = state.any((e) => e.thaiText == data.thaiText);
    if (!exists) {
      state = [...state, data];
      await _persist();
    }
  }

  Future<void> clear() async {
    state = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(state.map((e) => e.toJson()).toList()));
  }
}

final reviewProvider =
    StateNotifierProvider<ReviewNotifier, List<ReviewData>>((ref) {
  return ReviewNotifier();
});
