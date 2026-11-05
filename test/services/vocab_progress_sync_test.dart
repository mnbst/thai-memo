import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/data/models/vocab_word.dart';
import 'package:thai_memo/services/vocab_progress_sync.dart';

void main() {
  late List<String?> cursors;
  late List<String> saved;
  late int clears;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cursors = [];
    saved = [];
    clears = 0;
  });

  Future<void> run(
    String uid,
    SharedPreferences prefs,
    List<VocabProgressPage> pages,
  ) {
    var i = 0;
    return VocabProgressSync.run(
      uid: uid,
      prefs: prefs,
      fetch: (cursor) async {
        cursors.add(cursor);
        if (i >= pages.length) throw Exception('offline');
        return pages[i++];
      },
      save: (words) async => saved.addAll(words.map((w) => w.word)),
      clear: () async => clears++,
    );
  }

  VocabProgressPage page(String word, String cursor, {bool done = true}) =>
      VocabProgressPage(
        words: [VocabWord(word: word, rank: 1, p: 0.4, answered: false)],
        nextCursor: cursor,
        done: done,
      );

  test('続きがある間は読み、次回は続きから取る', () async {
    final prefs = await SharedPreferences.getInstance();
    await run('a', prefs, [page('x', 'c1', done: false), page('y', 'c2')]);
    expect(cursors, [null, 'c1']);
    expect(saved, ['x', 'y']);

    cursors.clear();
    await run('a', prefs, [page('z', 'c3')]);
    expect(cursors, ['c2']);
    expect(clears, 1); // 最初の持ち主登録のときだけ
  });

  test('アカウントが替わったら捨てて最初から取る', () async {
    final prefs = await SharedPreferences.getInstance();
    await run('a', prefs, [page('x', 'c1')]);
    cursors.clear();
    await run('b', prefs, [page('y', 'c9')]);
    expect(cursors, [null]);
    expect(clears, 2);
  });

  test('通信に失敗しても続きの位置は失わない', () async {
    final prefs = await SharedPreferences.getInstance();
    await run('a', prefs, [page('x', 'c1', done: false)]);
    expect(prefs.getString(VocabProgressSync.cursorKey), 'c1');
  });

  test('forget の次は最初から取り直す', () async {
    final prefs = await SharedPreferences.getInstance();
    await run('a', prefs, [page('x', 'c1')]);
    await VocabProgressSync.forget(prefs);
    cursors.clear();
    await run('a', prefs, [page('y', 'c2')]);
    expect(cursors, [null]);
    expect(clears, 2);
  });
}
