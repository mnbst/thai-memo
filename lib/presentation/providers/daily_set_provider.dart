// =============================================================================
// daily_set_provider.dart
// 配信された例文セット（1.4.8以降は5本）の消化カーソル。
//
// サーバーは1回の配信で複数本を書き込み、通知は1通だけ送る（設計
// docs/design_daily_sentence_batch.md）。クライアントはそれを1サイクル
// （例文→確認クイズ→…→最後の1本のあとにまとめクイズ）として順に消化する。
//
// カーソルは SharedPreferences に持たせる。途中でアプリを閉じても、
// 何本目まで進んだかを保ったまま再開できるようにするため。
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/thai_sentence.dart';
import '../../data/sentence_repository.dart';
import 'sentence_provider.dart';

/// まとめクイズまでの消化本数（LearningScreen が持つ）の保存キー。
///
/// セット開始でリセットしたいので、キーだけをここに置いて共有する。
const String learningCompletedCountKey = 'learning_completed_count';

class DailySetState {
  const DailySetState({this.sentences = const [], this.index = 0});

  /// 配信順（daily_set_index の昇順）。空ならセットを消化していない。
  final List<ThaiSentence> sentences;

  /// いま何本目か（0 始まり）。
  final int index;

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
  DailySetController(this._ref) : super(const DailySetState());

  final Ref _ref;

  /// 復元のときだけ使う。ここで解決を遅らせるのは、進捗表示（DailySetProgress）が
  /// 状態を watch するだけで Firebase 依存のリポジトリまで作られないようにするため。
  SentenceRepository get _repository => _ref.read(sentenceRepositoryProvider);

  static const String _idsKey = 'daily_set_ids';
  static const String _cursorKey = 'daily_set_cursor';

  /// 起動時に前回の続きを復元する。
  ///
  /// 例文の実体はローカルSQLiteにあるので、保存するのはIDと位置だけでよい。
  /// 消えている例文（履歴から削除された等）は詰めて扱う。
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_idsKey) ?? const [];
    if (ids.isEmpty) return;

    final sentences = <ThaiSentence>[];
    var index = prefs.getInt(_cursorKey) ?? 0;
    for (var i = 0; i < ids.length; i++) {
      final sentence = await _repository.getSentenceById(ids[i]);
      if (sentence != null) {
        sentences.add(sentence);
      } else if (i < index) {
        index--;
      }
    }
    if (sentences.isEmpty || index >= sentences.length) {
      await clear();
      return;
    }
    state = DailySetState(sentences: sentences, index: index);
  }

  /// 新しいセットの消化を1本目から始める。
  ///
  /// 配信で届いたセットと、アプリから生成したセットのどちらも同じ入口を通る。
  Future<void> start(List<ThaiSentence> sentences) async {
    if (sentences.isEmpty) {
      await clear();
      return;
    }
    state = DailySetState(sentences: sentences);
    // 新しいセットの1本目は必ず節目の起点。前のセットで積んだ本数を持ち越すと、
    // 1本目の確認クイズでいきなりまとめクイズへ誘導してしまう（閾値を変えた
    // バージョンアップ直後に起きた）。
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(learningCompletedCountKey, 0);
    await _save();
  }

  /// 次の1本へ進む。セットを使い切っていたら null を返す（生成へ落とす合図）。
  Future<ThaiSentence?> advance() async {
    if (!state.hasNext) {
      await clear();
      return null;
    }
    state = DailySetState(sentences: state.sentences, index: state.index + 1);
    await _save();
    return state.current;
  }

  Future<void> clear() async {
    state = const DailySetState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_idsKey);
    await prefs.remove(_cursorKey);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _idsKey,
      [for (final s in state.sentences) s.id].whereType<String>().toList(),
    );
    await prefs.setInt(_cursorKey, state.index);
  }
}

final dailySetProvider =
    StateNotifierProvider<DailySetController, DailySetState>((ref) {
  final controller = DailySetController(ref);
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
