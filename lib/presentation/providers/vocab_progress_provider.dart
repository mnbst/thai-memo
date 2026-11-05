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

/// 語ごとの習熟度。読むたびにサーバーとの差分を取り込む。
final vocabProgressProvider = FutureProvider<List<VocabWord>>((ref) async {
  final db = DatabaseHelper.instance;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid != null) {
    final api = BackendApiService();
    await VocabProgressSync.run(
      uid: uid,
      prefs: await SharedPreferences.getInstance(),
      fetch: api.getVocabProgress,
      save: (words) =>
          db.upsertVocabProgress([for (final w in words) w.toDatabase()]),
      clear: db.clearVocabProgress,
    );
  }
  final rows = await db.getVocabProgress();
  return rows.map(VocabWord.fromDatabase).toList();
});

/// 一覧に出す行（語彙ランクの大きい順）。
final vocabEntriesProvider = FutureProvider<List<VocabEntry>>((ref) async {
  final words = await ref.watch(vocabProgressProvider.future);
  final sentences = await ref.watch(allSentencesProvider.future);
  return VocabEntry.build(words, sentences);
});
