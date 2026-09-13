import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/data/sentence_repository.dart';
import 'package:thai_memo/presentation/providers/daily_set_provider.dart';
import 'package:thai_memo/presentation/providers/sentence_provider.dart';
import 'package:thai_memo/services/daily_set_progress_store.dart';

class _NoopProgressStore implements DailySetProgressStore {
  @override
  Future<ThaiSentence?> fetchSentence(String id) async => null;

  @override
  Future<DailySetProgressSnapshot?> merge(
    DailySetProgressSnapshot local,
  ) async =>
      null;
}

class _MemoryProgressStore implements DailySetProgressStore {
  _MemoryProgressStore(this.byId);

  final Map<String, ThaiSentence> byId;
  DailySetProgressSnapshot remote = const DailySetProgressSnapshot();

  @override
  Future<ThaiSentence?> fetchSentence(String id) async => byId[id];

  @override
  Future<DailySetProgressSnapshot?> merge(
    DailySetProgressSnapshot local,
  ) async {
    remote = mergeDailySetProgress(remote, local);
    return remote;
  }
}

/// ID で引ける例文だけを返す。履歴から消えた例文は null になる。
class _FakeSentenceRepository extends Fake implements SentenceRepository {
  _FakeSentenceRepository(this.byId);

  final Map<String, ThaiSentence> byId;

  @override
  Future<ThaiSentence?> getSentenceById(String id) async => byId[id];
}

ThaiSentence _sentence(String id) => ThaiSentence(
      id: id,
      thaiText: 'สวัสดี',
      pronunciation: 'sawatdi',
      japaneseTranslation: 'こんにちは',
      wordBreakdowns: const [],
    );

List<ThaiSentence> _set(List<String> ids) =>
    [for (final id in ids) _sentence(id)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerWith(
    Map<String, ThaiSentence> byId, {
    DailySetProgressStore? progressStore,
  }) {
    final container = ProviderContainer(
      overrides: [
        sentenceRepositoryProvider
            .overrideWithValue(_FakeSentenceRepository(byId)),
        dailySetProgressStoreProvider.overrideWithValue(
          progressStore ?? _NoopProgressStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('セット開始でまとめクイズまでの消化本数を0へ戻す', () async {
    // 閾値を変えたバージョンへ上げると旧値が残り、1本目でまとめクイズへ
    // 誘導されてしまう。新しいセットの開始が節目の起点になる。
    SharedPreferences.setMockInitialValues({learningCompletedCountKey: 4});
    final container = containerWith({});

    await container
        .read(dailySetProvider.notifier)
        .start(_set(['a', 'b', 'c', 'd', 'e']));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(learningCompletedCountKey), 0);
  });

  test('セットを受け取ったら1本目から数える', () async {
    final container = containerWith({});
    final controller = container.read(dailySetProvider.notifier);

    await controller.start(_set(['a', 'b', 'c', 'd', 'e']));

    final state = container.read(dailySetProvider);
    expect(state.isActive, isTrue);
    expect(state.position, 1);
    expect(state.total, 5);
    expect(state.current?.id, 'a');
    // 1本目はセットの最後ではないので、まとめクイズはまだ出さない。
    expect(state.isLast, isFalse);
  });

  test('最後の1本まで進めたら isLast になり、その次で使い切る', () async {
    final container = containerWith({});
    final controller = container.read(dailySetProvider.notifier);
    await controller.start(_set(['a', 'b', 'c']));

    expect((await controller.advance())?.id, 'b');
    expect((await controller.advance())?.id, 'c');
    expect(container.read(dailySetProvider).isLast, isTrue);

    // 使い切ったら null。呼び出し側はここで従来どおり生成へ落ちる。
    expect(await controller.advance(), isNull);
    expect(container.read(dailySetProvider).isActive, isFalse);
  });

  test('アプリを閉じても途中から再開する', () async {
    final container = containerWith({});
    await container
        .read(dailySetProvider.notifier)
        .start(_set(['a', 'b', 'c']));
    await container.read(dailySetProvider.notifier).advance();

    // 再起動相当。SharedPreferences の内容だけが引き継がれる。
    final restarted = containerWith({
      'a': _sentence('a'),
      'b': _sentence('b'),
      'c': _sentence('c'),
    });
    await restarted.read(dailySetProvider.notifier).restore();

    final state = restarted.read(dailySetProvider);
    expect(state.position, 2);
    expect(state.total, 3);
    expect(state.current?.id, 'b');
  });

  test('進行中に届いた新しい配信は表示を奪わず待機させる', () async {
    final container = containerWith({});
    final controller = container.read(dailySetProvider.notifier);
    await controller.start(_set(['a', 'b', 'c']), setId: 'old');
    await controller.advance();

    final shown = await controller.acceptDeliveredSet(
      setId: 'new',
      sentences: _set(['d', 'e', 'f']),
    );

    final state = container.read(dailySetProvider);
    expect(shown, isFalse);
    expect(state.current?.id, 'b');
    expect(state.position, 2);
    expect(state.pendingSets.single.setId, 'new');
  });

  test('進行中セットを使い切ると待機中セットの先頭へ進む', () async {
    final container = containerWith({});
    final controller = container.read(dailySetProvider.notifier);
    await controller.start(_set(['a', 'b']), setId: 'old');
    await controller.acceptDeliveredSet(
      setId: 'new',
      sentences: _set(['c', 'd']),
    );

    expect((await controller.advance())?.id, 'b');
    expect((await controller.advance())?.id, 'c');

    final state = container.read(dailySetProvider);
    expect(state.setId, 'new');
    expect(state.position, 1);
    expect(state.pendingSets, isEmpty);
  });

  test('待機中セットも再起動後に復元される', () async {
    final container = containerWith({});
    final controller = container.read(dailySetProvider.notifier);
    await controller.start(_set(['a', 'b']), setId: 'old');
    await controller.acceptDeliveredSet(
      setId: 'new',
      sentences: _set(['c', 'd']),
    );

    final restarted = containerWith({
      for (final id in ['a', 'b', 'c', 'd']) id: _sentence(id),
    });
    await restarted.read(dailySetProvider.notifier).restore();

    final state = restarted.read(dailySetProvider);
    expect(state.setId, 'old');
    expect(state.current?.id, 'a');
    expect(state.pendingSets.single.setId, 'new');
    expect(state.pendingSets.single.sentences.map((s) => s.id), ['c', 'd']);
  });

  test('別端末ではFirestore正本のカーソルと待機セットを復元する', () async {
    final sentences = {
      for (final id in ['a', 'b', 'c', 'd']) id: _sentence(id),
    };
    final cloud = _MemoryProgressStore(sentences);
    final firstDevice = containerWith(sentences, progressStore: cloud);
    final first = firstDevice.read(dailySetProvider.notifier);
    await first.start(_set(['a', 'b']), setId: 'old');
    await first.acceptDeliveredSet(
      setId: 'new',
      sentences: _set(['c', 'd']),
    );
    await first.advance();

    // SharedPreferencesを持たない別端末相当。
    SharedPreferences.setMockInitialValues({});
    final secondDevice = containerWith(sentences, progressStore: cloud);
    await secondDevice.read(dailySetProvider.notifier).restore();

    final restored = secondDevice.read(dailySetProvider);
    expect(restored.current?.id, 'b');
    expect(restored.pendingSets.single.setId, 'new');
  });

  test('同じ配信を復帰処理と通知処理が受け取っても二重に待機させない', () async {
    final container = containerWith({});
    final controller = container.read(dailySetProvider.notifier);
    await controller.start(_set(['a', 'b']), setId: 'old');

    await controller.acceptDeliveredSet(
      setId: 'new',
      sentences: _set(['c', 'd']),
    );
    await controller.acceptDeliveredSet(
      setId: 'new',
      sentences: _set(['c', 'd']),
    );

    expect(container.read(dailySetProvider).pendingSets, hasLength(1));
  });

  test('復帰処理と通知処理が並行しても受け取った順に直列化する', () async {
    final container = containerWith({});
    final controller = container.read(dailySetProvider.notifier);
    await controller.start(_set(['a', 'b']), setId: 'current');

    await Future.wait([
      controller.acceptDeliveredSet(
        setId: 'next-1',
        sentences: _set(['c', 'd']),
      ),
      controller.acceptDeliveredSet(
        setId: 'next-2',
        sentences: _set(['e', 'f']),
      ),
    ]);

    expect(
      container.read(dailySetProvider).pendingSets.map((set) => set.setId),
      ['next-1', 'next-2'],
    );
  });

  test('完了済みセットの古い通知を開いても再び待機列へ戻さない', () async {
    final container = containerWith({});
    final controller = container.read(dailySetProvider.notifier);
    await controller.start(_set(['a', 'b']), setId: 'done');
    await controller.advance();
    await controller.advance();
    await controller.start(_set(['c', 'd']), setId: 'current');

    final shown = await controller.acceptDeliveredSet(
      setId: 'done',
      sentences: _set(['a', 'b']),
    );

    expect(shown, isFalse);
    expect(container.read(dailySetProvider).setId, 'current');
    expect(container.read(dailySetProvider).pendingSets, isEmpty);
  });

  test('消えた例文は詰めて復元し、全部消えていればセットを捨てる', () async {
    final container = containerWith({});
    await container
        .read(dailySetProvider.notifier)
        .start(_set(['a', 'b', 'c']));
    await container.read(dailySetProvider.notifier).advance();

    // 1本目が履歴から消えた場合、カーソルも1つ前へ詰める。
    final partial = containerWith({'b': _sentence('b'), 'c': _sentence('c')});
    await partial.read(dailySetProvider.notifier).restore();
    expect(partial.read(dailySetProvider).current?.id, 'b');
    expect(partial.read(dailySetProvider).total, 2);

    final none = containerWith({});
    await none.read(dailySetProvider.notifier).restore();
    expect(none.read(dailySetProvider).isActive, isFalse);
  });

  test('生成したセットもカーソルに乗る', () async {
    final container = containerWith({});
    final controller = container.read(dailySetProvider.notifier);
    // listener を張るため、先に provider を読んでおく。
    container.read(dailySetProvider);

    await controller.start(_set(['g1', 'g2', 'g3', 'g4', 'g5']));

    expect(container.read(dailySetProvider).total, 5);
    expect(container.read(dailySetProvider).current?.id, 'g1');
  });

  test('1本しか作れなければセット扱いにせず、前のカーソルも残さない', () async {
    final container = containerWith({});
    final controller = container.read(dailySetProvider.notifier);
    await controller.start(_set(['a', 'b', 'c']));

    await controller.start(const []);

    expect(container.read(dailySetProvider).isActive, isFalse);
  });

  test('消化中に新しいセットを始めても、クラウドの旧セットに巻き戻らない', () async {
    final byId = {
      for (final id in ['a1', 'a2', 'b1', 'b2']) id: _sentence(id),
    };
    final store = _MemoryProgressStore(byId);
    final container = containerWith(byId, progressStore: store);
    final controller = container.read(dailySetProvider.notifier);

    await controller.start(_set(['a1', 'a2']), setId: 'A');
    await controller.advance();
    // 旧セットを完了扱いにしないと、Firestore に残る A が merge で正本になる。
    await controller.start(_set(['b1', 'b2']), setId: 'B');

    final state = container.read(dailySetProvider);
    expect(state.setId, 'B');
    expect(state.current?.id, 'b1');
    expect(state.pendingSets, isEmpty);
  });

  test('待機中の1本だけのセットは、消化後にクラウドから復活しない', () async {
    final byId = {
      for (final id in ['a1', 'a2', 'x1']) id: _sentence(id),
    };
    final store = _MemoryProgressStore(byId);
    final container = containerWith(byId, progressStore: store);
    final controller = container.read(dailySetProvider.notifier);

    await controller.start(_set(['a1', 'a2']), setId: 'A');
    await controller.acceptDeliveredSet(setId: 'X', sentences: _set(['x1']));
    await controller.advance();
    await controller.advance();

    final state = container.read(dailySetProvider);
    expect(state.isActive, isFalse);
    expect(state.pendingSets, isEmpty);
    expect(store.remote.active, isNull);
    expect(store.remote.pending, isEmpty);
  });

  test('1.4.8以前の分割キーからも続きを復元する', () async {
    // 統合キーが無い＝アップデート直後。旧キーを読み切ったら捨てる。
    SharedPreferences.setMockInitialValues({
      'daily_set_ids': ['a', 'b', 'c'],
      'daily_set_cursor': 1,
      'daily_set_id': 'old',
      'pending_daily_sets': '[{"set_id":"new","sentence_ids":["d","e"]}]',
      'completed_daily_set_ids': ['done'],
    });
    final container = containerWith({
      for (final id in ['a', 'b', 'c', 'd', 'e']) id: _sentence(id),
    });

    await container.read(dailySetProvider.notifier).restore();

    final state = container.read(dailySetProvider);
    expect(state.setId, 'old');
    expect(state.current?.id, 'b');
    expect(state.pendingSets.single.setId, 'new');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('daily_set_ids'), isNull);
  });

  test('復元するものが無ければ何もしない', () async {
    SharedPreferences.setMockInitialValues({});
    final container = containerWith({});
    await container.read(dailySetProvider.notifier).restore();
    expect(container.read(dailySetProvider).isActive, isFalse);
  });
}
