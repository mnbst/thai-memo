// =============================================================================
// daily_sentence_service.dart
// 毎日例文（サーバー配信）のクライアント側取り込み。
//
// 配信バッチ（deliverDailySentence）が users/{uid}/sentences に daily: true 付きで
// 書き込んだ例文を、起動時・フォアグラウンド復帰時にローカルSQLiteへ取り込む。
// 通知ペイロードは表示に使わない（通知を開かなくても例文が手元に揃うようにするため）。
//
// 取り込みは updated_at の差分同期。前回読んだ updated_at より新しい doc だけを
// 読み、配信・自分で生成した例文・ほかの端末でのお気に入りと削除をまとめて
// 反映する。まっさらな端末（再インストール・アカウント切替）だけは全件読む。
//
// 同じタイミングで users/{uid}.last_opened_at を書く。配信バックオフの「開封」判定に
// 使われる副シグナルで、これが動いている限り配信頻度は落ちない。
// =============================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/models/syllable.dart';
import '../data/models/thai_sentence.dart';
import '../data/models/word_breakdown.dart';
import '../data/sentence_repository.dart';

/// 1回の配信で届いた例文のまとまり。
///
/// サーバーは1回の配信で例文を複数本（1.4.8以降は5本）書き込み、通知は1通だけ送る。
/// クライアントはこれを1サイクル（例文→確認クイズ→…→まとめクイズ）として消化する。
/// 待機列へ積む配信の古さの上限（日）。全件読んだとき、これより古い配信は
/// 履歴へ入れるだけにする。進行位置の再構成も同じ窓を使う。
const int deliveredSetLookbackDays = 30;

/// syncAll の結果。
class SentenceSyncResult {
  const SentenceSyncResult({this.sets = const [], this.historyChanged = false});

  /// 今回はじめて取り込んだ配信セット。
  final List<DailySentenceSet> sets;

  /// 履歴（例文の増減・お気に入り）が変わったか。一覧の読み直しに使う。
  final bool historyChanged;
}

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

  static const _lookbackDays = deliveredSetLookbackDays;

  /// 差分同期のカーソル（読んだ doc の updated_at の最大、マイクロ秒）。
  static String syncCursorKey(String uid) => 'sentence_sync_cursor_$uid';

  /// 起動時・フォアグラウンド復帰時に呼ぶ。失敗しても学習の妨げにならないよう握り潰す。
  ///
  /// 今回はじめて取り込んだ配信セットをすべて返す。通知タップ対象があれば先頭、
  /// 残りは古い順。呼び出し側は順に表示・待機列へ積むだけでよく、通知タップか
  /// どうかを判定する必要はない。
  ///
  /// 「今日ぶんか」を日付で判定しない。サーバーはユーザー登録時のタイムゾーンで
  /// 日付を切るため、端末が国をまたぐとクライアントの「今日」とずれる。
  /// 未取り込み＝まだ見せていない配信、という判定なら時差に依存しない。
  Future<SentenceSyncResult> syncAll({String? sentenceId}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const SentenceSyncResult();

    // last_opened_at は表示に関係しない副シグナルなので待たない。
    // 待つとサーバー往復ぶんだけ通知タップからの表示が遅れる。
    unawaited(_touchLastOpenedAt(uid));
    return _syncDeliveredSets(uid, sentenceId: sentenceId);
  }

  Future<SentenceSyncResult> _syncDeliveredSets(
    String uid, {
    String? sentenceId,
  }) async {
    // 指定分を先に取り込んでから一括取り込みを回す。順序を守ると、一括側は
    // 指定分を「取り込み済み」として飛ばすので、古い未取り込み配信が
    // 通知で開いた例文を押しのけて表示されることがない。
    final byId = (sentenceId != null && sentenceId.isNotEmpty)
        ? await _importDeliveredSentenceById(uid, sentenceId)
        : null;

    final others = await _syncChanges(uid);
    return SentenceSyncResult(
      sets: [if (byId != null) byId, ...others.sets],
      historyChanged: byId != null || others.historyChanged,
    );
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

      if (local == null && await _repository.isSentenceDeleted(doc.id)) {
        return null;
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

  static Future<int>? _restoring;

  /// 自分で生成した例文を Firestore から端末へ取り込み、取り込んだ本数を返す。
  ///
  /// アカウント切替の直後に使う。配信分（daily: true）は待機列に積む必要が
  /// あるので [syncAll] に任せる。端末にあるもの・ユーザーが消したものは
  /// 取り込まない。
  Future<int> restoreHistory() =>
      _restoring ??= _restoreHistory().whenComplete(() => _restoring = null);

  Future<int> _restoreHistory() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 0;
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('sentences')
          .get();
      var imported = 0;
      for (final doc in snapshot.docs) {
        try {
          if (doc.data()['daily'] == true) continue;
          if (doc.data()['deleted'] == true) continue;
          if (await _repository.sentenceExists(doc.id)) continue;
          if (await _repository.isSentenceDeleted(doc.id)) continue;
          await _repository.saveSentence(toSentence(doc.id, doc.data()));
          imported++;
        } catch (e) {
          debugPrint('DailySentenceService: restore failed for ${doc.id}: $e');
        }
      }
      return imported;
    } catch (e) {
      debugPrint('DailySentenceService: restore fetch failed: $e');
      return 0;
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

  /// 前回の同期より後に変わった例文を端末へ反映し、新しく届いた配信セットを返す。
  ///
  /// - 端末に無い例文は取り込む（配信・自分で生成したもの）。ユーザーが消した
  ///   ものは取り込まない。
  /// - ほかの端末で消された例文は端末からも消す。
  /// - お気に入りはサーバーの値に合わせる。
  ///
  /// 返す配信セットは、今回はじめて取り込んだ配信を含むもの（取りこぼしの回収）。
  /// 順番は配信日時の古いセットから。複数日ぶんあっても待機キューへ順に積める。
  Future<SentenceSyncResult> _syncChanges(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cursorKey = syncCursorKey(uid);
      final cursor = prefs.getInt(cursorKey);
      // まっさらな端末では、前に使っていたときのカーソルが残っていても全件読む。
      final full = cursor == null || await _repository.hasNoLocalHistory();

      Query<Map<String, dynamic>> query =
          _firestore.collection('users').doc(uid).collection('sentences');
      if (!full) {
        query = query.where(
          'updated_at',
          isGreaterThan: Timestamp.fromMicrosecondsSinceEpoch(cursor),
        );
      }
      // 端末キャッシュから読むと、手元に無い doc を飛ばしたままカーソルだけ
      // 進んで取りこぼす。必ずサーバーから読む。
      final snapshot = await query.get(const GetOptions(source: Source.server));

      final queueSince = DateTime.now().subtract(
        const Duration(days: _lookbackDays),
      );
      final bySet =
          <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      final newSets = <String, DateTime>{};
      var historyChanged = false;
      var failed = false;
      var latest = cursor;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        // updated_at の無い旧docは created_at で代える。旧docに後からお気に
        // 入り・削除が付けば、そのときの updated_at がこれより新しくなる。
        final stamp = data['updated_at'] ?? data['created_at'];
        if (stamp is Timestamp) {
          final micros = stamp.microsecondsSinceEpoch;
          if (latest == null || micros > latest) latest = micros;
        }
        final isDaily = data['daily'] == true;
        if (isDaily && data['deleted'] != true) {
          bySet.putIfAbsent(setIdOf(doc.id, data), () => []).add(doc);
        }

        // 1件の不正データで他の例文まで取り込めなくならないよう、docごとに握り潰す。
        try {
          if (data['deleted'] == true) {
            if (await _repository.sentenceExists(doc.id)) {
              await _repository.applyRemoteDeletion(doc.id);
              historyChanged = true;
            }
            continue;
          }
          // Firestore の doc ID をそのままローカルの主キーに使う。
          final local = await _repository.getSentenceById(doc.id);
          if (local != null) {
            final favorite = data['favorite'];
            if (favorite is bool && favorite != local.isFavorite) {
              await _repository.applyRemoteFavorite(doc.id, favorite);
              historyChanged = true;
            }
            continue;
          }
          if (await _repository.isSentenceDeleted(doc.id)) continue;

          final sentence = toSentence(doc.id, data);
          await _repository.saveSentence(sentence);
          historyChanged = true;
          final date =
              sentence.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          if (!isDaily || date.isBefore(queueSince)) continue;
          final setId = setIdOf(doc.id, data);
          final previous = newSets[setId];
          if (previous == null || date.isBefore(previous)) {
            newSets[setId] = date;
          }
        } catch (e) {
          failed = true;
          debugPrint('DailySentenceService: import failed for ${doc.id}: $e');
        }
      }

      // 取り込めなかった doc があれば、次回また読めるようカーソルを据え置く。
      if (!failed && latest != null && latest != cursor) {
        await prefs.setInt(cursorKey, latest);
      }

      final orderedIds = newSets.keys.toList()
        ..sort((a, b) => newSets[a]!.compareTo(newSets[b]!));
      final sets = <DailySentenceSet>[];
      for (final setId in orderedIds) {
        final set = await _importSet(setId, bySet[setId]!);
        if (set != null) sets.add(set);
      }
      return SentenceSyncResult(sets: sets, historyChanged: historyChanged);
    } catch (e) {
      // 取り込み失敗時は次回の起動で再試行される。
      // 黙って落ちるとインデックス不足などの構成ミスに気づけないのでログは残す。
      debugPrint('DailySentenceService: fetch failed: $e');
      return const SentenceSyncResult();
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
        if (local == null && await _repository.isSentenceDeleted(member.key)) {
          continue;
        }
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
  /// 進行位置の再構成（daily_set_progress_store）からも使う。
  static List<MapEntry<String, Map<String, dynamic>>> orderSetMembers(
    String setId,
    List<MapEntry<String, Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) => setIdOf(doc.key, doc.value) == setId).toList()
      ..sort((a, b) => _setIndexOf(a.value).compareTo(_setIndexOf(b.value)));
  }

  /// セットの識別子。1本ずつ配信していた頃のドキュメントには無いので、
  /// その場合は doc ID 自身を使って「1本だけのセット」として扱う。
  /// 配信docのセット識別子。旧形式（daily_set_id 無し）は doc 自身を1本のセットとして扱う。
  static String setIdOf(String docId, Map<String, dynamic> data) {
    final setId = data['daily_set_id'];
    return (setId is String && setId.isNotEmpty) ? setId : docId;
  }

  static int _setIndexOf(Map<String, dynamic> data) {
    final index = data['daily_set_index'];
    return index is num ? index.toInt() : 0;
  }

  /// Firestore の配信docを ThaiSentence に変換する。
  ///
  /// インスタンス状態を持たないので静的にし、Firestore進捗の復元でも共用する。
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
      isFavorite: data['favorite'] == true,
      generationTier: data['generation_tier'] as String?,
      targetWords: [
        if (data['key_word'] is String) data['key_word'] as String,
      ],
    );
  }
}
