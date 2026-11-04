// =============================================================================
// vocab_word.dart
// 履歴の語彙一覧に出す語。習熟度はサーバーの uvm の写しで、発音・意味・例文は
// 端末の例文データから引く。
// =============================================================================

import '../../core/database_constants.dart';
import 'thai_sentence.dart';

/// 語の覚え具合。
enum VocabMastery { seen, learning, learned }

/// 語ごとの習熟度。
class VocabWord {
  /// 「覚えた」の境目（サーバーの uvm.LearnedP と揃える）。
  static const double learnedP = 0.5;

  /// P の取りうる範囲（uvm.PFloor / PMax）。ゲージはこの範囲を 0〜1 に換算する。
  static const double minP = 0.15;
  static const double maxP = 0.99;

  final String word;

  /// 語彙ランク。頻度表に無い語は 0。
  final int rank;
  final double p;

  /// 語の力を測る回答をしたことがあるか。
  final bool answered;

  const VocabWord({
    required this.word,
    required this.rank,
    required this.p,
    required this.answered,
  });

  VocabMastery get mastery {
    if (!answered) return VocabMastery.seen;
    return p > learnedP ? VocabMastery.learned : VocabMastery.learning;
  }

  /// ゲージの長さ（0〜1）。未回答は空。
  double get gauge {
    if (!answered) return 0;
    return ((p - minP) / (maxP - minP)).clamp(0.0, 1.0);
  }

  factory VocabWord.fromDatabase(Map<String, dynamic> row) => VocabWord(
        word: row[DatabaseConstants.columnVocabWord] as String,
        rank: row[DatabaseConstants.columnVocabRank] as int,
        p: (row[DatabaseConstants.columnVocabP] as num).toDouble(),
        answered: row[DatabaseConstants.columnVocabAnswered] == 1,
      );

  Map<String, dynamic> toDatabase() => {
        DatabaseConstants.columnVocabWord: word,
        DatabaseConstants.columnVocabRank: rank,
        DatabaseConstants.columnVocabP: p,
        DatabaseConstants.columnVocabAnswered: answered ? 1 : 0,
      };

  factory VocabWord.fromServer(Map<String, dynamic> map) => VocabWord(
        word: map['word'] as String,
        rank: (map['rank'] as num?)?.toInt() ?? 0,
        p: (map['p'] as num?)?.toDouble() ?? 0,
        answered: map['answered'] == true,
      );
}

/// getVocabProgress の1ページ。
class VocabProgressPage {
  final List<VocabWord> words;
  final String? nextCursor;
  final bool done;

  const VocabProgressPage({
    required this.words,
    required this.nextCursor,
    required this.done,
  });

  factory VocabProgressPage.fromMap(Map<String, dynamic> map) =>
      VocabProgressPage(
        words: (map['words'] as List? ?? const [])
            .map((e) => VocabWord.fromServer(Map<String, dynamic>.from(e as Map)))
            .toList(),
        nextCursor: map['next_cursor'] as String?,
        done: map['done'] != false,
      );
}

/// 一覧の1行。習熟度に、端末の例文から引いた発音・意味・例文を足したもの。
class VocabEntry {
  final VocabWord progress;
  final String pronunciation;
  final String meaning;
  final List<ThaiSentence> sentences;

  const VocabEntry({
    required this.progress,
    this.pronunciation = '',
    this.meaning = '',
    this.sentences = const [],
  });

  /// 語彙ランクの大きい順に並べた一覧を作る。ランクの無い語は最後。
  static List<VocabEntry> build(
    List<VocabWord> words,
    List<ThaiSentence> sentences,
  ) {
    final pronunciation = <String, String>{};
    final meaning = <String, String>{};
    final bySentence = <String, List<ThaiSentence>>{};
    for (final sentence in sentences) {
      final inSentence = <String>{...?sentence.targetWords};
      for (final b in sentence.wordBreakdowns) {
        inSentence.add(b.wordText);
        pronunciation.putIfAbsent(b.wordText, () => b.pronunciation);
        meaning.putIfAbsent(b.wordText, () => b.meaning);
      }
      for (final word in inSentence) {
        (bySentence[word] ??= []).add(sentence);
      }
    }
    final entries = [
      for (final w in words)
        VocabEntry(
          progress: w,
          pronunciation: pronunciation[w.word] ?? '',
          meaning: meaning[w.word] ?? '',
          sentences: bySentence[w.word] ?? const [],
        ),
    ];
    entries.sort((a, b) {
      final ra = a.progress.rank, rb = b.progress.rank;
      if ((ra == 0) != (rb == 0)) return ra == 0 ? 1 : -1;
      return rb.compareTo(ra);
    });
    return entries;
  }
}
