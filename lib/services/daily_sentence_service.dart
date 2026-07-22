// =============================================================================
// daily_sentence_service.dart
// 毎日例文（サーバー配信）のクライアント側取り込み。
//
// 配信バッチ（deliverDailySentence）が users/{uid}/sentences に daily: true 付きで
// 書き込んだ例文を、起動時・フォアグラウンド復帰時にローカルSQLiteへ取り込む。
// 通知ペイロードは表示に使わない（通知を開かなくても例文が手元に揃うようにするため）。
//
// 同じタイミングで users/{uid}.last_opened_at を書く。配信バックオフの「開封」判定に
// 使われる副シグナルで、これが動いている限り配信頻度は落ちない。
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/models/syllable.dart';
import '../data/models/thai_sentence.dart';
import '../data/models/word_breakdown.dart';
import '../data/sentence_repository.dart';

class DailySentenceService {
  DailySentenceService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    SentenceRepository? repository,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _repository = repository ?? SentenceRepository();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final SentenceRepository _repository;
  static const _uuid = Uuid();

  /// 直近この日数ぶんの配信を取り込み対象にする。
  /// サーバー側の例文保持期間（30日）より短く、取りこぼしを拾える程度の幅。
  static const _lookbackDays = 7;

  /// 起動時・フォアグラウンド復帰時に呼ぶ。失敗しても学習の妨げにならないよう握り潰す。
  ///
  /// 今回はじめて取り込んだ配信例文があれば返す。呼び出し側はこれを表示するだけでよく、
  /// 通知タップかどうかを判定する必要はない。
  ///
  /// 「今日ぶんか」を日付で判定しない。サーバーはユーザー登録時のタイムゾーンで
  /// 日付を切るため、端末が国をまたぐとクライアントの「今日」とずれる。
  /// 未取り込み＝まだ見せていない配信、という判定なら時差に依存しない。
  Future<ThaiSentence?> sync() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    final results = await Future.wait([
      _touchLastOpenedAt(uid).then((_) => null),
      _importDeliveredSentences(uid),
    ]);
    return results.last;
  }

  Future<void> _touchLastOpenedAt(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).set(
        {'last_opened_at': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (_) {
      // 通信失敗は次回の起動で回復するので無視する
    }
  }

  /// 配信済み例文をローカルへ取り込み、新規に取り込んだ最新の1件を返す。
  Future<ThaiSentence?> _importDeliveredSentences(String uid) async {
    ThaiSentence? imported;
    DateTime? latest;
    try {
      final since = DateTime.now().subtract(
        const Duration(days: _lookbackDays),
      );
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('sentences')
          .where('daily', isEqualTo: true)
          .where('created_at', isGreaterThan: Timestamp.fromDate(since))
          .get();

      for (final doc in snapshot.docs) {
        // 1件の不正データで他の配信まで取り込めなくならないよう、docごとに握り潰す。
        try {
          // Firestore の doc ID をそのままローカルの主キーに使う。
          // 取り込み済みならスキップするので、お気に入り等のローカル状態を壊さない。
          if (await _repository.sentenceExists(doc.id)) continue;

          final sentence = toSentence(doc.id, doc.data());
          await _repository.saveSentence(sentence);
          final createdAt = sentence.createdAt;
          if (latest == null ||
              (createdAt != null && createdAt.isAfter(latest))) {
            imported = sentence;
            latest = createdAt;
          }
        } catch (e) {
          debugPrint('DailySentenceService: import failed for ${doc.id}: $e');
        }
      }
    } catch (e) {
      // 取り込み失敗時は次回の起動で再試行される。
      // 黙って落ちるとインデックス不足などの構成ミスに気づけないのでログは残す。
      debugPrint('DailySentenceService: fetch failed: $e');
    }
    return imported;
  }

  /// Firestore の配信docを ThaiSentence に変換する。
  ///
  /// インスタンス状態を持たないので静的にしてある（テストから直接叩けるようにするため）。
  @visibleForTesting
  static ThaiSentence toSentence(String id, Map<String, dynamic> data) {
    final createdAt = data['created_at'];
    final rawBreakdowns = (data['word_breakdown'] as List?) ?? const [];

    // syllables はサーバーが文字列配列で返すため、WordBreakdown.fromJson には渡せない。
    // parseSyllables で声調解析を補いつつ Syllable に変換する。
    final wordBreakdowns = rawBreakdowns
        .whereType<Map>()
        .toList()
        .asMap()
        .entries
        .map((entry) {
          final raw = Map<String, dynamic>.from(entry.value);
          final syllables = parseSyllables(raw['syllables'] as List<dynamic>?);
          raw.remove('syllables');
          return WordBreakdown.fromJson(raw).copyWith(
            id: _uuid.v4(),
            sentenceId: id,
            wordOrder: entry.key,
            syllables: syllables,
          );
        })
        .toList();

    final context = data['context'];

    return ThaiSentence(
      id: id,
      thaiText: data['thai_text'] as String? ?? '',
      pronunciation: data['pronunciation'] as String? ?? '',
      japaneseTranslation: data['japanese_translation'] as String? ?? '',
      wordBreakdowns: wordBreakdowns,
      context: context is Map
          ? SentenceContext.fromJson(Map<String, dynamic>.from(context))
          : null,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      generationTier: data['generation_tier'] as String?,
      targetWords: [
        if (data['key_word'] is String) data['key_word'] as String,
      ],
    );
  }
}
