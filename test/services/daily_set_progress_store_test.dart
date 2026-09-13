import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/services/daily_set_progress_store.dart';

DailySetRef _set(String id, [List<String>? sentenceIds]) => DailySetRef(
      setId: id,
      sentenceIds: sentenceIds ?? ['$id-1', '$id-2'],
    );

void main() {
  test('同じセットを別端末で進めても大きいカーソルを維持する', () {
    final merged = mergeDailySetProgress(
      DailySetProgressSnapshot(active: _set('a'), activeIndex: 3),
      DailySetProgressSnapshot(active: _set('a'), activeIndex: 1),
    );

    expect(merged.active?.setId, 'a');
    expect(merged.activeIndex, 3);
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
      DailySetProgressSnapshot(active: _set('a'), activeIndex: 4),
      DailySetProgressSnapshot(
        active: _set('b'),
        completedSetIds: const ['a'],
      ),
    );

    expect(merged.active?.setId, 'b');
    expect(merged.completedSetIds, contains('a'));
  });
}
