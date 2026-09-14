// 学習の進み具合を1レコードで持つストア。旧キー（カーソル・確認クイズ・
// まとめクイズ）からの畳み込みと、書き手が複数いる状況での読み書きを押さえる。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/services/daily_set_progress_store.dart';
import 'package:thai_memo/services/learning_progress_store.dart';

Map<String, dynamic> _legacySet({
  required String setId,
  required List<String> ids,
  required String currentId,
}) =>
    {
      'active': {'set_id': setId, 'sentence_ids': ids},
      'active_index': ids.indexOf(currentId),
      'active_sentence_id': currentId,
      'pending': <dynamic>[],
      'completed_set_ids': <String>[],
    };

Map<String, dynamic> _legacyQuiz({String? setId, String? sentenceId}) => {
      'phase': 'summary',
      if (setId != null) 'set_id': setId,
      if (sentenceId != null) 'sentence_id': sentenceId,
      'questions': [
        {'sentence_id': 'x', 'thai_text': 'ก', 'correct_answer': 'ก'}
      ],
      'answers': [true],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('新しいキーが無ければ旧キーから畳み、旧キーは消す', () async {
    SharedPreferences.setMockInitialValues({
      LearningProgressStore.legacySetKey: jsonEncode(
        _legacySet(setId: 'set-a', ids: ['a', 'b'], currentId: 'b'),
      ),
      LearningProgressStore.legacySummaryQuizKey:
          jsonEncode(_legacyQuiz(setId: 'set-a')),
    });

    final record = await LearningProgressStore().load();

    expect(record.set.active?.setId, 'set-a');
    expect(record.set.activeSentenceId, 'b');
    // まとめクイズが残っていた＝結果や回答の途中で閉じた人なので、段も戻す。
    expect(record.stage, LearningStage.summaryQuiz);
    expect(record.summaryQuiz?['phase'], 'summary');
    // 持ち主は畳んだ時点で落とす（カーソルと同じレコードにいるので要らない）。
    expect(record.summaryQuiz?.containsKey('set_id'), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LearningProgressStore.legacySetKey), isNull);
    expect(
      prefs.getString(LearningProgressStore.legacySummaryQuizKey),
      isNull,
    );
    expect(prefs.getString(LearningProgressStore.key), isNotNull);
  });

  test('別のセットの旧まとめクイズは引き継がない', () async {
    SharedPreferences.setMockInitialValues({
      LearningProgressStore.legacySetKey: jsonEncode(
        _legacySet(setId: 'set-new', ids: ['a', 'b'], currentId: 'a'),
      ),
      LearningProgressStore.legacySummaryQuizKey:
          jsonEncode(_legacyQuiz(setId: 'set-old')),
    });

    final record = await LearningProgressStore().load();

    expect(record.summaryQuiz, isNull);
    expect(record.stage, LearningStage.sentence);
  });

  test('別の例文の旧確認クイズは引き継がない', () async {
    SharedPreferences.setMockInitialValues({
      LearningProgressStore.legacySetKey: jsonEncode(
        _legacySet(setId: 'set-a', ids: ['a', 'b'], currentId: 'b'),
      ),
      LearningProgressStore.legacyConfirmationQuizKey:
          jsonEncode(_legacyQuiz(sentenceId: 'a')),
    });

    final record = await LearningProgressStore().load();

    expect(record.confirmationQuiz, isNull);
  });

  test('1.4.8以前の分割キーからもカーソルを畳む', () async {
    SharedPreferences.setMockInitialValues({
      'daily_set_id': 'set-old',
      'daily_set_ids': ['a', 'b', 'c'],
      'daily_set_cursor': 1,
      'completed_daily_set_ids': ['set-older'],
    });

    final record = await LearningProgressStore().load();

    expect(record.set.active?.setId, 'set-old');
    expect(record.set.activeSentenceId, 'b');
    expect(record.set.completedSetIds, ['set-older']);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('daily_set_ids'), isNull);
  });

  test('複数の書き手が同時に書いても互いの変更を消さない', () async {
    // カーソル・段・クイズは別々の場所から書かれる。読んで書き戻す間に
    // 割り込まれると、後勝ちで片方が消える。
    SharedPreferences.setMockInitialValues({});
    final store = LearningProgressStore();

    await Future.wait([
      store.update((r) => r.copyWith(
            set: const DailySetProgressSnapshot(
              active: DailySetRef(setId: 'set-a', sentenceIds: ['a', 'b']),
              activeSentenceId: 'a',
            ),
          )),
      store.update((r) => r.copyWith(stage: LearningStage.summaryQuiz)),
      store.update((r) => r.copyWith(summaryQuiz: {'phase': 'summary'})),
    ]);

    final record = await store.load();
    expect(record.set.active?.setId, 'set-a');
    expect(record.stage, LearningStage.summaryQuiz);
    expect(record.summaryQuiz?['phase'], 'summary');
  });

  test('clear は新旧すべてのキーを消す', () async {
    SharedPreferences.setMockInitialValues({
      LearningProgressStore.key: jsonEncode(
        const LearningProgressRecord(stage: LearningStage.summaryQuiz).toJson(),
      ),
      LearningProgressStore.legacySetKey: jsonEncode(
        _legacySet(setId: 'set-a', ids: ['a'], currentId: 'a'),
      ),
      'daily_set_ids': ['a'],
    });
    final store = LearningProgressStore();

    await store.clear();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LearningProgressStore.key), isNull);
    expect(prefs.getString(LearningProgressStore.legacySetKey), isNull);
    expect(prefs.getStringList('daily_set_ids'), isNull);
  });
}
