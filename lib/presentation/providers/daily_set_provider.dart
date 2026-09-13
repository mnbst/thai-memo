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
  bool get isLast => isActive && !hasNext;

  ThaiSentence? get current => isActive ? sentences[index] : null;
}

class DailySetController extends StateNotifier<DailySetState> {
  DailySetController(this._ref, this._readProgressStore)
      : super(const DailySetState());

  final Ref _ref;
  final DailySetProgressStore Function() _readProgressStore;
  List<String> _completedSetIds = const [];
  Future<void> _operationTail = Future.value();

  DailySetProgressStore get _progressStore => _readProgressStore();

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
  Future<void> syncFromCloud() => _serialized(_persist);

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
      // 1本しか無い配信（旧prod・旧形式doc・通信断のfallback）はセットにしない。
      // isLast=true になり、1本後にまとめクイズへ強制遷移してしまう。
      if (sentences.length > 1) {
        await _start(sentences, setId: setId);
      }
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
    if (next.sentences.length > 1) {
      state = DailySetState(
        setId: next.setId,
        sentences: next.sentences,
        pendingSets: remaining,
      );
    } else {
      // 1本しか無いものはセットにしない。ただし捨てるだけだと Firestore 側に
      // 残り、merge で正本として復活してしまうので、完了として記録して落とす。
      _markCompleted(next.setId);
      state = DailySetState(pendingSets: remaining);
    }
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
        activeIndex: state.index,
        pending: [
          for (final pending in state.pendingSets)
            DailySetRef.fromSentences(pending.setId, pending.sentences),
        ],
        completedSetIds: _completedSetIds,
      );

  /// ローカルへ保存し、Firestore の正本とマージして反映する。
  ///
  /// 通信前にローカルを確定させておくのは、マージに失敗しても端末側の続きが
  /// 残るようにするため。マージできたらその結果でもう一度上書きする。
  Future<void> _persist() async {
    await _saveLocal();
    final merged = await _progressStore.merge(_snapshot());
    if (merged == null) return;
    await _apply(merged);
    if (mounted) await _saveLocal();
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_progressKey, jsonEncode(_snapshot().toJson()));
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
      final rawSets = (jsonDecode(prefs.getString('pending_daily_sets') ?? '[]')
              as List)
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
      activeIndex: cursor,
      pending: pending,
      completedSetIds: completed,
    );
  }

  /// スナップショットの例文IDを実体へ解決して state に反映する。
  /// ローカル保存とクラウド正本のどちらも同じ経路を通る。
  Future<void> _apply(DailySetProgressSnapshot? snapshot) async {
    if (snapshot == null) return;
    _completedSetIds = snapshot.completedSetIds;

    final pending = <PendingDailySet>[];
    for (final ref in snapshot.pending) {
      final sentences = await _resolve(ref.sentenceIds);
      if (sentences.isNotEmpty) {
        pending.add(PendingDailySet(setId: ref.setId, sentences: sentences));
      }
    }

    final activeRef = snapshot.active;
    // 消えた例文（履歴から削除された等）は詰めて扱う。カーソルより前が欠けた
    // ぶんだけ位置も前へずらす。
    var index = snapshot.activeIndex;
    final active = <ThaiSentence>[];
    if (activeRef != null) {
      for (var i = 0; i < activeRef.sentenceIds.length; i++) {
        final sentence = await _fetch(activeRef.sentenceIds[i]);
        if (sentence != null) {
          active.add(sentence);
        } else if (i < snapshot.activeIndex) {
          index--;
        }
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

  Future<List<ThaiSentence>> _resolve(List<String> ids) async {
    final sentences = <ThaiSentence>[];
    for (final id in ids) {
      final sentence = await _fetch(id);
      if (sentence != null) sentences.add(sentence);
    }
    return sentences;
  }

  /// ローカルDBを先に見る。別端末で受け取った例文だけ配信docから引き直し、
  /// 引けたらローカルにも入れて以後の復元を通信なしで済ませる。
  Future<ThaiSentence?> _fetch(String id) async {
    final local = await _repository.getSentenceById(id);
    if (local != null) return local;
    final remote = await _progressStore.fetchSentence(id);
    if (remote != null) await _repository.saveSentence(remote);
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
    // 1本しか作れなかった（残りクォータ）ときは空で渡す。セットになって
    // いないので進捗も出さず、前のセットのカーソルも残さない。
    controller.start(
      next.generatedSet.length > 1 ? next.generatedSet : const [],
    );
  });
  return controller;
});
