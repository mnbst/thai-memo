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

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/models/syllable.dart';
import '../data/models/thai_sentence.dart';
import '../data/models/word_breakdown.dart';
import '../data/sentence_repository.dart';

/// 1回の配信で届いた例文のまとまり。
///
/// サーバーは1回の配信で例文を複数本（1.4.8以降は5本）書き込み、通知は1通だけ送る。
/// クライアントはこれを1サイクル（例文→確認クイズ→…→まとめクイズ）として消化する。
class DailySentenceSet {
  const DailySentenceSet({required this.setId, required this.sentences});

  /// 配信ごとの識別子。サーバーは1本目の doc ID を流用する。
  final String setId;

  /// daily_set_index の昇順。旧形式の配信は1本だけ入る。
  final List<ThaiSentence> sentences;

  ThaiSentence get first => sentences.first;
}

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
  /// 今回はじめて取り込んだ配信があれば、そのセット全体を返す。呼び出し側はこれを
  /// 順に表示するだけでよく、通知タップかどうかを判定する必要はない。
  ///
  /// 「今日ぶんか」を日付で判定しない。サーバーはユーザー登録時のタイムゾーンで
  /// 日付を切るため、端末が国をまたぐとクライアントの「今日」とずれる。
  /// 未取り込み＝まだ見せていない配信、という判定なら時差に依存しない。
  Future<DailySentenceSet?> sync({String? sentenceId}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    // last_opened_at は表示に関係しない副シグナルなので待たない。
    // 待つとサーバー往復ぶんだけ通知タップからの表示が遅れる。
    unawaited(_touchLastOpenedAt(uid));
    return _syncDeliveredSentences(uid, sentenceId: sentenceId);
  }

  Future<DailySentenceSet?> _syncDeliveredSentences(
    String uid, {
    String? sentenceId,
  }) async {
    // 指定分を先に取り込んでから一括取り込みを回す。順序を守ると、一括側は
    // 指定分を「取り込み済み」として飛ばすので、古い未取り込み配信が
    // 通知で開いた例文を押しのけて表示されることがない。
    final byId = (sentenceId != null && sentenceId.isNotEmpty)
        ? await _importDeliveredSentenceById(uid, sentenceId)
        : null;

    // 表示すべき1件が確定したら、取りこぼし回収の一括取り込みは待たずに返す。
    // 待つと7日ぶんのクエリが終わるまで画面が切り替わらない。
    if (byId != null) {
      unawaited(_importDeliveredSentences(uid));
      return byId;
    }
    return _importDeliveredSentences(uid);
  }

  Future<DailySentenceSet?> _importDeliveredSentenceById(
    String uid,
    String sentenceId,
  ) async {
    ThaiSentence? local;
    try {
      local = await _repository.getSentenceById(sentenceId);
      // ローカルにあっても Firestore を確認する。セットの先頭は一括同期で既に
      // SQLite に入っていることが多く、ここで即 return すると通知タップのたびに
      // 5本セットを「先頭だけの1本セット」で上書きしてしまう。
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('sentences')
          .doc(sentenceId)
          .get();
      final data = doc.data();
      if (!doc.exists || data == null || data['daily'] != true) {
        return local == null
            ? null
            : DailySentenceSet(setId: sentenceId, sentences: [local]);
      }

      // 通知は1通なので、同じセットの残りはここで引き直す。
      final setId = data['daily_set_id'] as String?;
      if (setId != null && setId.isNotEmpty) {
        final siblings = await _firestore
            .collection('users')
            .doc(uid)
            .collection('sentences')
            .where('daily_set_id', isEqualTo: setId)
            .get();
        final set = await _importSet(setId, siblings.docs);
        if (set != null) return set;
      }

      final sentence = local ?? toSentence(doc.id, data);
      if (local == null) await _repository.saveSentence(sentence);
      return DailySentenceSet(setId: doc.id, sentences: [sentence]);
    } catch (e) {
      debugPrint(
        'DailySentenceService: fetch by ID failed for $sentenceId: $e',
      );
      // 1.4.7 までは、取り込み済みの通知は通信できなくてもローカルから開けた。
      // セット確認のための Firestore 読み直しに失敗しても、その挙動は落とさない。
      return local == null
          ? null
          : DailySentenceSet(setId: sentenceId, sentences: [local]);
    }
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

  /// 配信済み例文をローカルへ取り込み、新しく届いたセットを返す。
  ///
  /// 取り込みは未取り込みの配信すべてが対象（取りこぼしの回収）。返すのは
  /// そのうち最新のものが属するセットだけで、それが「今日の学習」になる。
  Future<DailySentenceSet?> _importDeliveredSentences(String uid) async {
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

      String? newestSetId;
      DateTime? latest;
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
            latest = createdAt;
            newestSetId = _setIdOf(doc.id, doc.data());
          }
        } catch (e) {
          debugPrint('DailySentenceService: import failed for ${doc.id}: $e');
        }
      }

      if (newestSetId == null) return null;
      return _importSet(newestSetId, snapshot.docs);
    } catch (e) {
      // 取り込み失敗時は次回の起動で再試行される。
      // 黙って落ちるとインデックス不足などの構成ミスに気づけないのでログは残す。
      debugPrint('DailySentenceService: fetch failed: $e');
      return null;
    }
  }

  /// docs から setId のセットを組み立てる。未取り込みのものはここで保存する。
  Future<DailySentenceSet?> _importSet(
    String setId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final members = orderSetMembers(
      setId,
      [for (final doc in docs) MapEntry(doc.id, doc.data())],
    );

    final sentences = <ThaiSentence>[];
    for (final member in members) {
      try {
        // お気に入り等の端末固有状態を保つため、取り込み済みならremoteから
        // 作り直したオブジェクトではなくSQLite上の実体を返す。
        final local = await _repository.getSentenceById(member.key);
        final sentence = local ?? toSentence(member.key, member.value);
        if (local == null) {
          await _repository.saveSentence(sentence);
        }
        sentences.add(sentence);
      } catch (e) {
        debugPrint(
          'DailySentenceService: import failed for ${member.key}: $e',
        );
      }
    }
    if (sentences.isEmpty) return null;
    return DailySentenceSet(setId: setId, sentences: sentences);
  }

  /// setId に属するドキュメントを配信順（daily_set_index の昇順）に並べる。
  @visibleForTesting
  static List<MapEntry<String, Map<String, dynamic>>> orderSetMembers(
    String setId,
    List<MapEntry<String, Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) => _setIdOf(doc.key, doc.value) == setId).toList()
      ..sort((a, b) => _setIndexOf(a.value).compareTo(_setIndexOf(b.value)));
  }

  /// セットの識別子。1本ずつ配信していた頃のドキュメントには無いので、
  /// その場合は doc ID 自身を使って「1本だけのセット」として扱う。
  static String _setIdOf(String docId, Map<String, dynamic> data) {
    final setId = data['daily_set_id'];
    return (setId is String && setId.isNotEmpty) ? setId : docId;
  }

  static int _setIndexOf(Map<String, dynamic> data) {
    final index = data['daily_set_index'];
    return index is num ? index.toInt() : 0;
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
    final wordBreakdowns =
        rawBreakdowns.whereType<Map>().toList().asMap().entries.map((entry) {
      final raw = Map<String, dynamic>.from(entry.value);
      final syllables = parseSyllables(raw['syllables'] as List<dynamic>?);
      raw.remove('syllables');
      return WordBreakdown.fromJson(raw).copyWith(
        id: _uuid.v4(),
        sentenceId: id,
        wordOrder: entry.key,
        syllables: syllables,
      );
    }).toList();

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
