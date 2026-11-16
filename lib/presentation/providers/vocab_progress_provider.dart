// =============================================================================
// vocab_progress_provider.dart
// 履歴の語彙一覧のデータ。差分を同期してから端末の DB を読み、例文と合わせる。
// =============================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/backend_api_service.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../data/models/vocab_word.dart';
import '../../services/vocab_progress_sync.dart';
import 'sentence_provider.dart';

/// 語ごとの習熟度と、まとめクイズのスコア枠（取れなければ null）。
typedef VocabProgress = ({List<VocabWord> words, (int, int)? quizBand});

/// 語ごとの習熟度。読むたびにサーバーとの差分を取り込み、スコア枠も取り直す。
final vocabProgressProvider = FutureProvider<VocabProgress>((ref) async {
  final db = DatabaseHelper.instance;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  (int, int)? band;
  if (uid != null) {
    final api = BackendApiService();
    band = await VocabProgressSync.run(
      uid: uid,
      prefs: await SharedPreferences.getInstance(),
      fetch: api.getVocabProgress,
      save: (words) =>
          db.upsertVocabProgress([for (final w in words) w.toDatabase()]),
      clear: db.clearVocabProgress,
    );
  }
  final rows = await db.getVocabProgress();
  return (
    words: rows.map(VocabWord.fromDatabase).toList(),
    quizBand: band,
  );
});

/// サーバーが単語一覧と一緒に返したまとめクイズのスコア枠。
final quizBandProvider = FutureProvider<(int, int)?>((ref) async {
  return (await ref.watch(vocabProgressProvider.future)).quizBand;
});

/// 一覧に出す行（語彙ランクの大きい順）。
final vocabEntriesProvider = FutureProvider<List<VocabEntry>>((ref) async {
  final words = (await ref.watch(vocabProgressProvider.future)).words;
  final sentences = await ref.watch(allSentencesProvider.future);
  return VocabEntry.build(words, sentences);
});
