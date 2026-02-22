import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewData {
  final String thaiText;
  final String pronunciation;
  final String japaneseTranslation;
  final String reviewNotes;

  const ReviewData({
    required this.thaiText,
    required this.pronunciation,
    required this.japaneseTranslation,
    required this.reviewNotes,
  });

  Map<String, String> toJson() => {
        'thai_text': thaiText,
        'pronunciation': pronunciation,
        'japanese_translation': japaneseTranslation,
        'review_notes': reviewNotes,
      };

  factory ReviewData.fromJson(Map<String, dynamic> json) => ReviewData(
        thaiText: json['thai_text'] ?? '',
        pronunciation: json['pronunciation'] ?? '',
        japaneseTranslation: json['japanese_translation'] ?? '',
        reviewNotes: json['review_notes'] ?? '',
      );
}

class ReviewNotifier extends StateNotifier<ReviewData?> {
  static const _key = 'review_data';

  ReviewNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json != null) {
      state = ReviewData.fromJson(jsonDecode(json));
    }
  }

  Future<void> save(ReviewData data) async {
    state = data;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data.toJson()));
  }
}

final reviewProvider =
    StateNotifierProvider<ReviewNotifier, ReviewData?>((ref) {
  return ReviewNotifier();
});
