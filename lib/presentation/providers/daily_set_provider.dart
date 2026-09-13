// =============================================================================
// daily_set_provider.dart
// 配信された例文セット（1.4.8以降は5本）の消化カーソル。
//
// サーバーは1回の配信で複数本を書き込み、通知は1通だけ送る（設計
// docs/design_daily_sentence_batch.md）。クライアントはそれを1サイクル
// （例文→確認クイズ→…→最後の1本のあとにまとめクイズ）として順に消化する。
//
// 進行位置は SharedPreferences（端末の続き）と Firestore（端末間の正本）の
// 両方に、DailySetProgressSnapshot という同じ形で持つ。保存するのは例文IDと
// 位置だけで、本文はローカルDBか配信docから引き直す。
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/thai_sentence.dart';
import '../../data/sentence_repository.dart';
import '../../services/daily_set_progress_store.dart';
import 'sentence_provider.dart';

/// まとめクイズまでの消化本数（LearningScreen が持つ）の保存キー。
///
/// セット開始でリセットしたいので、キーだけをここに置いて共有する。
const String learningCompletedCountKey = 'learning_completed_count';

class PendingDailySet {
  const PendingDailySet({required this.setId, required this.sentences});

  final String setId;
  final List<ThaiSentence> sentences;
}

class DailySetState {
  const DailySetState({
    this.setId,
    this.sentences = const [],
    this.index = 0,
    this.pendingSets = const [],
  });

  /// 配信セットの識別子。アプリ内生成では先頭例文のIDを使う。
  final String? setId;

  /// 配信順（daily_set_index の昇順）。空ならセットを消化していない。
  final List<ThaiSentence> sentences;

  /// いま何本目か（0 始まり）。
  final int index;

  /// 進行中セットを終えたあとに表示する配信セット。
  final List<PendingDailySet> pendingSets;

  /// セットを消化中か。
  bool get isActive => sentences.isNotEmpty && index < sentences.length;

  /// 「2 / 5」の分子。
  int get position => index + 1;

  int get total => sentences.length;

  /// 次の1本がセットに残っているか。残っていなければ従来どおり生成へ落ちる。
  bool get hasNext => index + 1 < sentences.length;

  /// セットの最後の1本か。ここの確認クイズの後は必ずまとめクイズへ進む。
  ///
  /// 1本だけのもの（旧形式の配信・クォータ残1）はセットの締めとして扱わない。
  /// 1本読んだだけでまとめクイズへ送られてしまう。
  bool get isLast => isActive && !hasNext && sentences.length > 1;

  ThaiSentence? get current => isActive ? sentences[index] : null;
}

class DailySetController extends StateNotifier<DailySetState> {
  DailySetController(this._ref, this._readProgressStore)
      : super(const DailySetState());

  final Ref _ref;
  final DailySetProgressStore Function() _readProgressStore;
  List<String> _completedSetIds = const [];
  Future<void>? _remoteSyncFuture;
  bool _remoteSyncDirty = false;
  Future<void> _operationTail = Future.value();

  DailySetProgressStore get _progressStore => _readProgressStore();

  /// 外から今の状態を読むための入口（StateNotifier の state は protected）。
  DailySetState get currentState => state;

  /// 復元のときだけ使う。ここで解決を遅らせるのは、進捗表示（DailySetProgress）が
  /// 状態を watch するだけで Firebase 依存のリポジトリまで作られないようにするため。
  SentenceRepository get _repository => _ref.read(sentenceRepositoryProvider);

  static const String _progressKey = 'daily_set_progress';

  /// 1.4.8 までのキー。移行のためだけに読み、読んだ時点で捨てる。
  static const List<String> _legacyKeys = [
    'daily_set_ids',
    'daily_set_cursor',
    'daily_set_id',
    'pending_daily_sets',
    'completed_daily_set_ids',
  ];

  /// 起動時に前回の続きを復元する。
  Future<void> restore() => _serialized(_restore);

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    await _apply(_readLocal(prefs) ?? await _readLegacy(prefs));
    if (!mounted) return;
    // 進行中セットが残っていなければ、待機列の先頭を今日のセットに繰り上げる。
    if (!state.isActive) await _promotePendingIfAny();
    if (!mounted) return;
    await _persist();
  }

  /// Firestore の正本を取り込み、別端末で進んだカーソルや待機セットを反映する。
  Future<void> syncFromCloud() async {
    _scheduleRemoteSync();
    await settled;
  }

  /// 予約済みの Firestore 同期まで含めて落ち着くのを待つ。
  @visibleForTesting
  Future<void> get settled async {
    while (true) {
      await _operationTail;
      final remote = _remoteSyncFuture;
      if (remote != null) {
        await remote;
        continue;
      }
      await _operationTail;
      if (_remoteSyncFuture == null) return;
    }
  }

  /// 新しいセットの消化を1本目から始める。
  ///
  /// 配信で届いたセットと、アプリから生成したセットのどちらも同じ入口を通る。
  Future<void> start(List<ThaiSentence> sentences, {String? setId}) =>
      _serialized(() => _start(sentences, setId: setId));

  Future<void> _start(List<ThaiSentence> sentences, {String? setId}) async {
    final nextSetId = sentences.isEmpty ? null : (setId ?? sentences.first.id);
    if (state.setId != nextSetId) _markCompleted(state.setId);
    if (sentences.isEmpty) {
      state = DailySetState(pendingSets: state.pendingSets);
      await _persist();
      return;
    }
    state = DailySetState(
      setId: nextSetId,
      sentences: sentences,
      pendingSets: state.pendingSets,
    );
    await _startNewCycle();
  }

  /// 新着配信を受け取る。進行中なら表示を奪わず、次のセットとして保存する。
  ///
  /// 戻り値は、その場で新着を表示できる状態になったときだけ true。
  Future<bool> acceptDeliveredSet({
    required String setId,
    required List<ThaiSentence> sentences,
  }) =>
      _serialized(
        () => _acceptDeliveredSet(setId: setId, sentences: sentences),
      );

  Future<bool> _acceptDeliveredSet({
    required String setId,
    required List<ThaiSentence> sentences,
  }) async {
    if (sentences.isEmpty) return false;
    if (_completedSetIds.contains(setId) ||
        state.setId == setId ||
        state.pendingSets.any((pending) => pending.setId == setId)) {
      return false;
    }
    if (!state.isActive) {
      // 1本しか無い配信（旧prod・旧形式doc・通信断のfallback、free のクォータ残1）
      // もセットとして開始する。載せないと進行位置が残らず、再起動や別端末で
      // 「読んだのにまた出る／読まずに消える」になる。まとめクイズへ強制遷移
      // させないための除外は isLast 側で行う。
      await _start(sentences, setId: setId);
      return true;
    }

    state = DailySetState(
      setId: state.setId,
      sentences: state.sentences,
      index: state.index,
      pendingSets: [
        ...state.pendingSets,
        PendingDailySet(setId: setId, sentences: sentences),
      ],
    );
    await _persist();
    return false;
  }

  /// アプリ内で生成したセットを受け取る。配信と同じく、消化中のセットは
  /// 奪わず次のセットとして待たせる。表示を戻すのは呼び出し側。
  ///
  /// 戻り値は、その場で表示に切り替えてよいときだけ true。
  Future<bool> acceptGeneratedSet(List<ThaiSentence> sentences) =>
      _serialized(() => _acceptGeneratedSet(sentences));

  Future<bool> _acceptGeneratedSet(List<ThaiSentence> sentences) async {
    if (sentences.isEmpty) return false;
    final setId = sentences.first.id;
    if (setId == null) {
      // ID が無いものは待機列に積んでも復元できない。従来どおり即開始する。
      await _start(sentences);
      return true;
    }
    return _acceptDeliveredSet(setId: setId, sentences: sentences);
  }

  /// 次の1本へ進む。セットを使い切っていたら null を返す（生成へ落とす合図）。
  Future<ThaiSentence?> advance() => _serialized(_advance);

  Future<ThaiSentence?> _advance() async {
    if (!state.hasNext) {
      return _promotePendingIfAny();
    }
    state = DailySetState(
      setId: state.setId,
      sentences: state.sentences,
      index: state.index + 1,
      pendingSets: state.pendingSets,
    );
    await _persist();
    return state.current;
  }

  Future<void> clear() => _serialized(_clear);

  Future<void> _clear() async {
    state = const DailySetState();
    _completedSetIds = const [];
    final prefs = await SharedPreferences.getInstance();
    for (final key in [_progressKey, ..._legacyKeys]) {
      await prefs.remove(key);
    }
  }

  Future<T> _serialized<T>(Future<T> Function() operation) async {
    final previous = _operationTail;
    final done = Completer<void>();
    _operationTail = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
    }
  }

  Future<ThaiSentence?> _promotePendingIfAny() async {
    _markCompleted(state.setId);
    if (state.pendingSets.isEmpty) {
      state = const DailySetState();
      await _persist();
      return null;
    }

    final next = state.pendingSets.first;
    final remaining = state.pendingSets.skip(1).toList();
    state = DailySetState(
      setId: next.setId,
      sentences: next.sentences,
      pendingSets: remaining,
    );
    await _startNewCycle();
    return next.sentences.first;
  }

  /// 新しいセットの1本目は必ず節目の起点。前のセットで積んだ本数を持ち越すと、
  /// 1本目の確認クイズでいきなりまとめクイズへ誘導してしまう（閾値を変えた
  /// バージョンアップ直後に起きた）。
  Future<void> _startNewCycle() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(learningCompletedCountKey, 0);
    await _persist();
  }

  /// セットから抜けるときは必ず完了として記録する。記録が漏れると、Firestore に
  /// 残った同じセットが merge で未完了の正本と見なされ、いま開始したセットを
  /// 待機側へ押しやってカーソルが巻き戻る。
  void _markCompleted(String? setId) {
    if (setId == null || _completedSetIds.contains(setId)) return;
    _completedSetIds = trimCompletedSetIds([..._completedSetIds, setId]);
  }

  /// いまの状態を、ローカルと Firestore で共通の形に落とす。
  DailySetProgressSnapshot _snapshot() => DailySetProgressSnapshot(
        active: state.isActive && state.setId != null
            ? DailySetRef.fromSentences(state.setId!, state.sentences)
            : null,
        // 位置の正本は「いま読んでいる例文のID」。番号は並びから引き直す。
        activeSentenceId: state.current?.id,
        pending: [
          for (final pending in state.pendingSets)
            DailySetRef.fromSentences(pending.setId, pending.sentences),
        ],
        completedSetIds: _completedSetIds,
      );

  /// 端末の続きを確定させる。Firestore は待たない。
  ///
  /// 正本は端末のローカル状態として扱い、Firestore との突き合わせは後ろで回す。
  /// 通信を待って表示を止めると、機内・低速回線で「開いたのに例文が出ない」
  /// になり、待った末にカーソルが動いて画面が切り替わる。
  Future<void> _persist() async {
    await _saveLocal();
    _scheduleRemoteSync();
  }

  /// Firestore とのマージを1本だけ予約する。予約済みなら重ねない。
  void _scheduleRemoteSync() {
    if (_remoteSyncFuture != null) {
      _remoteSyncDirty = true;
      return;
    }
    late final Future<void> future;
    future = _mergeRemote().whenComplete(() {
      if (identical(_remoteSyncFuture, future)) _remoteSyncFuture = null;
      if (_remoteSyncDirty && mounted) {
        _remoteSyncDirty = false;
        _scheduleRemoteSync();
      }
    });
    _remoteSyncFuture = future;
  }

  /// ローカルの状態を Firestore の正本とマージして反映する。
  ///
  /// マージに失敗しても端末側の続きは保存済みなので、学習は止まらない。
  Future<void> _mergeRemote() async {
    // 破棄後に走ることがある（アプリ終了・テストの後始末）。ここから先は
    // provider を読むので、生きているときだけ進める。
    if (!mounted) return;
    // provider の参照と送信状態は await をまたぐ前に取る。通信中に進んだ
    // ローカル状態は、完了後の foreground merge で重ね直す。
    final store = _progressStore;
    final localAtRequest = _snapshot();
    final merged = await store.merge(localAtRequest);
    if (merged == null || !mounted) return;
    // 通信中も advance/start は止めない。反映だけをローカル操作と直列化し、
    // その時点で学習中のセットとカーソルは維持する。
    await _serialized(() async {
      if (!mounted) return;
      final localNow = _snapshot();
      final reconciled = mergeDailySetProgressPreservingLocalActive(
        merged,
        localNow,
      );
      await _apply(reconciled);
      if (mounted) await _saveLocal();
    });
  }

  Future<void> _saveLocal() async {
    if (!mounted) return;
    // state は await をまたぐ前に写し取る。破棄後に読むと例外になるうえ、
    // 待っているあいだに進んだ位置を書き戻してしまう。
    final encoded = jsonEncode(_snapshot().toJson());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_progressKey, encoded);
  }

  DailySetProgressSnapshot? _readLocal(SharedPreferences prefs) {
    final encoded = prefs.getString(_progressKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return DailySetProgressSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(encoded) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  /// 1.4.8 以前の分割キーから読み直す。次回からは統合キーだけを見る。
  Future<DailySetProgressSnapshot?> _readLegacy(
    SharedPreferences prefs,
  ) async {
    final ids = prefs.getStringList('daily_set_ids') ?? const [];
    final setId = prefs.getString('daily_set_id');
    final cursor = prefs.getInt('daily_set_cursor') ?? 0;
    final completed =
        prefs.getStringList('completed_daily_set_ids') ?? const <String>[];
    final pending = <DailySetRef>[];
    try {
      final rawSets =
          (jsonDecode(prefs.getString('pending_daily_sets') ?? '[]') as List)
              .whereType<Map>();
      for (final raw in rawSets) {
        final set = DailySetRef.fromJson({
          'set_id': raw['set_id'],
          'sentence_ids': raw['sentence_ids'],
        });
        if (set != null) pending.add(set);
      }
    } catch (_) {
      // 壊れていれば待機列は諦める。進行中セットの復元は続ける。
    }
    for (final key in _legacyKeys) {
      await prefs.remove(key);
    }
    return DailySetProgressSnapshot(
      active: ids.isEmpty
          ? null
          : DailySetRef(setId: setId ?? ids.first, sentenceIds: ids),
      activeSentenceId: cursor >= 0 && cursor < ids.length ? ids[cursor] : null,
      pending: pending,
      completedSetIds: completed,
    );
  }

  /// スナップショットの例文IDを実体へ解決して state に反映する。
  /// ローカル保存とクラウド正本のどちらも同じ経路を通る。
  Future<void> _apply(DailySetProgressSnapshot? snapshot) async {
    if (snapshot == null || !mounted) return;
    // 解決中に provider が破棄されても ref を読み直さないよう、依存先を先に取る。
    final repository = _repository;
    final progressStore = _progressStore;
    _completedSetIds = snapshot.completedSetIds;

    final pending = <PendingDailySet>[];
    for (final ref in snapshot.pending) {
      final sentences = await _resolve(
        ref.sentenceIds,
        repository,
        progressStore,
      );
      if (sentences.isNotEmpty) {
        pending.add(PendingDailySet(setId: ref.setId, sentences: sentences));
      }
    }

    final activeRef = snapshot.active;
    // 読んでいた1本（snapshot.activeIndex が指す位置）より前に何本残ったかが、
    // そのまま復元後の位置になる。消えた例文（履歴から削除された等）は詰めて
    // 扱い、読んでいた1本自体が消えていれば次に残っている1本を指す。
    final anchorAt = snapshot.activeIndex;
    var index = 0;
    final active = <ThaiSentence>[];
    if (activeRef != null) {
      for (var i = 0; i < activeRef.sentenceIds.length; i++) {
        final sentence = await _fetch(
          activeRef.sentenceIds[i],
          repository,
          progressStore,
        );
        if (sentence == null) continue;
        if (i < anchorAt) index++;
        active.add(sentence);
      }
    }

    // 例文の解決はローカルDBとFirestoreをまたぐので、この間に画面が破棄される
    // ことがある。dispose 後に state を代入すると StateNotifier が例外を投げる。
    if (!mounted) return;
    if (active.isEmpty) {
      state = DailySetState(pendingSets: pending);
      return;
    }
    state = DailySetState(
      setId: activeRef!.setId,
      sentences: active,
      index: index.clamp(0, active.length - 1),
      pendingSets: pending,
    );
  }

  Future<List<ThaiSentence>> _resolve(
    List<String> ids,
    SentenceRepository repository,
    DailySetProgressStore progressStore,
  ) async {
    final sentences = <ThaiSentence>[];
    for (final id in ids) {
      final sentence = await _fetch(id, repository, progressStore);
      if (sentence != null) sentences.add(sentence);
    }
    return sentences;
  }

  /// ローカルDBを先に見る。別端末で受け取った例文だけ配信docから引き直し、
  /// 引けたらローカルにも入れて以後の復元を通信なしで済ませる。
  Future<ThaiSentence?> _fetch(
    String id,
    SentenceRepository repository,
    DailySetProgressStore progressStore,
  ) async {
    final local = await repository.getSentenceById(id);
    if (local != null) return local;
    final remote = await progressStore.fetchSentence(id);
    if (remote != null) await repository.saveSentence(remote);
    return remote;
  }

}

final dailySetProgressStoreProvider = Provider<DailySetProgressStore>((ref) {
  return FirestoreDailySetProgressStore();
});

final dailySetProvider =
    StateNotifierProvider<DailySetController, DailySetState>((ref) {
  final controller = DailySetController(
    ref,
    () => ref.read(dailySetProgressStoreProvider),
  );
  // アプリからの生成もセット単位。生成経路が複数あるので、呼び出し側それぞれで
  // カーソルを立てるのではなく、生成結果を1か所で拾う。
  ref.listen<SentenceState>(sentenceControllerProvider, (_, next) {
    if (next is! SentenceStateSuccess || !next.generated) return;
    final generated = next.generatedSet;
    if (generated.isEmpty) return;
    // 消化中のセットは奪わない。日付が変わった朝の自動生成（クォータ復活・
    // daily_sentence_generated=false）はセットの途中でも走るので、ここで
    // start すると残りが履歴にしか残らず「飛ばされた」ように見える。
    controller.acceptGeneratedSet(generated).then((accepted) {
      if (accepted) return;
      // 待機列へ回したぶんを表示したままにすると、進捗（2/5）と本文がずれる。
      // 消化中の1本へ戻す。
      final current = controller.currentState.current;
      if (current != null) {
        ref.read(sentenceControllerProvider.notifier).showSentence(current);
      }
    });
  });
  return controller;
});
