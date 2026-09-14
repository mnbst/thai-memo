import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/services/daily_set_progress_store.dart';

DailySetRef _set(String id, [List<String>? sentenceIds]) => DailySetRef(
      setId: id,
      sentenceIds: sentenceIds ?? ['$id-1', '$id-2'],
    );

void main() {
  test('同じセットを別端末で進めても大きいカーソルを維持する', () {
    final ids = ['a-1', 'a-2', 'a-3', 'a-4'];
    final merged = mergeDailySetProgress(
      DailySetProgressSnapshot(
        active: _set('a', ids),
        activeSentenceId: 'a-4',
      ),
      DailySetProgressSnapshot(
        active: _set('a', ids),
        activeSentenceId: 'a-2',
      ),
    );

    expect(merged.active?.setId, 'a');
    expect(merged.activeIndex, 3);
    expect(merged.activeSentenceId, 'a-4');
  });

  test('片方の並びが1本欠けていても、位置は例文IDで揃える', () {
    // 欠けた並び [a-2, a-3] のカーソル1（= a-3）と、そろった正本のカーソル1
    // （= a-2）。番号をそのまま max すると a-4 まで飛ぶ。
    final merged = mergeDailySetProgress(
      DailySetProgressSnapshot(
        active: _set('a', ['a-1', 'a-2', 'a-3', 'a-4']),
        activeSentenceId: 'a-2',
      ),
      DailySetProgressSnapshot(
        active: _set('a', ['a-2', 'a-3']),
        activeSentenceId: 'a-3',
      ),
    );

    expect(merged.active?.sentenceIds.length, 4);
    expect(merged.activeSentenceId, 'a-3');
    expect(merged.activeIndex, 2);
  });

  test('読んでいる1本は、クラウドの長い並びを採っても動かない', () {
    final merged = mergeDailySetProgressPreservingLocalActive(
      DailySetProgressSnapshot(
        active: _set('a', ['a-1', 'a-2', 'a-3']),
        activeSentenceId: 'a-3',
      ),
      DailySetProgressSnapshot(
        active: _set('a', ['a-2', 'a-3']),
        activeSentenceId: 'a-2',
      ),
    );

    expect(merged.activeSentenceId, 'a-2');
    expect(merged.activeIndex, 1);
  });

  test('番号しか持たない旧データは、その並びの例文IDへ読み替える', () {
    final restored = DailySetProgressSnapshot.fromJson({
      'active': {
        'set_id': 'a',
        'sentence_ids': ['a-1', 'a-2', 'a-3'],
      },
      'active_index': 2,
    });

    expect(restored.activeSentenceId, 'a-3');
    expect(restored.activeIndex, 2);
    // 旧バージョンが同じdocを読んでも先頭に戻らないよう、番号も書き続ける。
    expect(restored.toJson()['active_index'], 2);
  });

  test('完了したセットは古い端末の進行中・待機中状態から復活しない', () {
    final merged = mergeDailySetProgress(
      DailySetProgressSnapshot(
        active: _set('b'),
        completedSetIds: const ['a'],
      ),
      DailySetProgressSnapshot(
        active: _set('a'),
        pending: [_set('b')],
      ),
    );

    expect(merged.active?.setId, 'b');
    expect(merged.pending, isEmpty);
    expect(merged.completedSetIds, contains('a'));
  });

  test('異なる端末で受け取った待機セットを欠落なく一意にまとめる', () {
    final merged = mergeDailySetProgress(
      DailySetProgressSnapshot(
        active: _set('a'),
        pending: [_set('b')],
      ),
      DailySetProgressSnapshot(
        active: _set('a'),
        pending: [_set('b'), _set('c')],
      ),
    );

    expect(merged.active?.setId, 'a');
    expect(merged.pending.map((set) => set.setId), ['b', 'c']);
  });

  test('同じセットの一部だけ持つ端末と完全版をマージすると完全版を残す', () {
    final merged = mergeDailySetProgress(
      DailySetProgressSnapshot(active: _set('a', ['a-1'])),
      DailySetProgressSnapshot(active: _set('a', ['a-1', 'a-2', 'a-3'])),
    );

    expect(merged.active?.sentenceIds, ['a-1', 'a-2', 'a-3']);
  });

  test('一方が現セットを完了して次へ進んだ場合は次セットを正本にする', () {
    final merged = mergeDailySetProgress(
      DailySetProgressSnapshot(active: _set('a')),
      DailySetProgressSnapshot(
        active: _set('b'),
        completedSetIds: const ['a'],
      ),
    );

    expect(merged.active?.setId, 'b');
    expect(merged.completedSetIds, contains('a'));
  });

  test('学習中の取り込みは表示中セットを維持し、クラウドの次セットを待機させる', () {
    final merged = mergeDailySetProgressPreservingLocalActive(
      DailySetProgressSnapshot(
        active: _set('b'),
        completedSetIds: const ['a'],
      ),
      DailySetProgressSnapshot(active: _set('a'), activeSentenceId: 'a-2'),
    );

    expect(merged.active?.setId, 'a');
    expect(merged.activeIndex, 1);
    expect(merged.pending.map((set) => set.setId), ['b']);
    expect(merged.completedSetIds, isNot(contains('a')));
  });

  test('学習中は同一セットのクラウド側カーソルでも表示位置を動かさない', () {
    final merged = mergeDailySetProgressPreservingLocalActive(
      DailySetProgressSnapshot(active: _set('a'), activeSentenceId: 'a-1'),
      DailySetProgressSnapshot(active: _set('a'), activeSentenceId: 'a-2'),
    );

    expect(merged.active?.setId, 'a');
    expect(merged.activeIndex, 1);
  });

  test('通信中に完了したセットを古いクラウド結果から復活させない', () {
    final merged = mergeDailySetProgressPreservingLocalActive(
      DailySetProgressSnapshot(active: _set('a')),
      const DailySetProgressSnapshot(completedSetIds: ['a']),
    );

    expect(merged.active, isNull);
    expect(merged.completedSetIds, contains('a'));
  });

  // 進行位置を失った端末の救済。配信docの束から直近のセットを組み直す。
  group('latestDeliveredSetRef', () {
    MapEntry<String, Map<String, dynamic>> doc(
      String id, {
      required String setId,
      required int index,
      required int day,
    }) =>
        MapEntry(id, {
          'daily_set_id': setId,
          'daily_set_index': index,
          'created_at': Timestamp.fromDate(DateTime(2026, 9, day)),
        });

    test('いちばん新しいセットを daily_set_index の順で返す', () {
      final ref = latestDeliveredSetRef([
        doc('old-1', setId: 'OLD', index: 0, day: 1),
        doc('new-2', setId: 'NEW', index: 1, day: 5),
        doc('new-1', setId: 'NEW', index: 0, day: 5),
      ]);

      expect(ref?.setId, 'NEW');
      expect(ref?.sentenceIds, ['new-1', 'new-2']);
    });

    test('daily_set_id を持たない旧形式は doc 単体のセットとして扱う', () {
      final ref = latestDeliveredSetRef([
        MapEntry('legacy', {
          'created_at': Timestamp.fromDate(DateTime(2026, 9, 9)),
        }),
      ]);

      expect(ref?.setId, 'legacy');
      expect(ref?.sentenceIds, ['legacy']);
    });

    test('配信が無ければ null', () {
      expect(latestDeliveredSetRef(const []), isNull);
    });
  });
}
