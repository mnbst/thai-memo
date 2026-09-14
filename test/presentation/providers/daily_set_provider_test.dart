import 'dart:async';

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
  Future<DailySetRef?> fetchLatestDeliveredSet() async => null;

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

  /// 配信docから組み直せるセット（進行位置を失った端末の救済経路）。
  DailySetRef? delivered;

  @override
  Future<ThaiSentence?> fetchSentence(String id) async => byId[id];

  @override
  Future<DailySetRef?> fetchLatestDeliveredSet() async => delivered;

  @override
  Future<DailySetProgressSnapshot?> merge(
    DailySetProgressSnapshot local,
  ) async {
    remote = mergeDailySetProgress(remote, local);
    return remote;
  }
}

class _GatedProgressStore extends _MemoryProgressStore {
  _GatedProgressStore(super.byId);

  final gate = Completer<void>();

  @override
  Future<DailySetProgressSnapshot?> merge(
    DailySetProgressSnapshot local,
  ) async {
    await gate.future;
    return super.merge(local);
  }
}

/// ID で引ける例文だけを返す。履歴から消えた例文は null になる。
class _FakeSentenceRepository extends Fake implements SentenceRepository {
  _FakeSentenceRepository(this.byId, {this.answered = const {}});

  final Map<String, ThaiSentence> byId;

  /// クイズに答えた記録のある例文ID（進行位置の再構成で使う）。
  final Set<String> answered;

  @override
  Future<ThaiSentence?> getSentenceById(String id) async => byId[id];

  @override
  Future<Set<String>> answeredSentenceIds(List<String> ids) async =>
      {for (final id in ids) if (answered.contains(id)) id};
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
    Set<String> answered = const {},
  }) {
    final container = ProviderContainer(
      overrides: [
        sentenceRepositoryProvider.overrideWithValue(
          _FakeSentenceRepository(byId, answered: answered),
        ),
        dailySetProgressStoreProvider.overrideWithValue(
          progressStore ?? _NoopProgressStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  test('Firestore同期が遅くても次の例文へ進める', () async {
    final byId = {
      for (final id in ['a', 'b']) id: _sentence(id)
    };
    final store = _GatedProgressStore(byId);
    final container = containerWith(byId, progressStore: store);
    final controller = container.read(dailySetProvider.notifier);

    await controller.start(_set(['a', 'b']), setId: 'A');

    final next = await controller.advance().timeout(
          const Duration(milliseconds: 200),
        );
    expect(next?.id, 'b');

    store.gate.complete();
    await controller.settled;
  });

  test('別端末が次セットへ進んでいても表示中セットを途中で差し替えない', () async {
    final byId = {
      for (final id in ['a1', 'a2', 'b1', 'b2']) id: _sentence(id),
    };
    final store = _MemoryProgressStore(byId)
      ..remote = DailySetProgressSnapshot(
        active: DailySetRef.fromSentences('B', _set(['b1', 'b2'])),
        completedSetIds: const ['A'],
      );
    final container = containerWith(byId, progressStore: store);
    final controller = container.read(dailySetProvider.notifier);

    await controller.start(_set(['a1', 'a2']), setId: 'A');
    await controller.settled;

    final state = container.read(dailySetProvider);
    expect(state.setId, 'A');
    expect(state.current?.id, 'a1');
    expect(state.pendingSets.map((set) => set.setId), ['B']);
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

  test('欠けていた1本を拾い直しても読んでいる例文は動かない', () async {
    // 前回の起動で 'a' を引けず、詰めた並び [b, c] のカーソル1（= c）で保存
    // された状態。クラウドには5本そろった正本がある。
    final sentences = {
      for (final id in ['a', 'b', 'c']) id: _sentence(id),
    };
    final cloud = _MemoryProgressStore(sentences);
    cloud.remote = DailySetProgressSnapshot(
      active: DailySetRef(setId: 's1', sentenceIds: const ['a', 'b', 'c']),
      activeSentenceId: 'c',
    );

    final container = containerWith(sentences, progressStore: cloud);
    final controller = container.read(dailySetProvider.notifier);
    await controller.start(_set(['b', 'c']), setId: 's1');
    await controller.advance();
    await controller.settled;

    final state = container.read(dailySetProvider);
    expect(state.current?.id, 'c');
    expect(state.total, 3, reason: '欠けていた1本はクラウドから戻す');
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
    // Firestore への反映は表示を待たせない後追い。読み出す前に落ち着かせる。
    await first.settled;

    // SharedPreferencesを持たない別端末相当。
    SharedPreferences.setMockInitialValues({});
    final secondDevice = containerWith(sentences, progressStore: cloud);
    final second = secondDevice.read(dailySetProvider.notifier);
    await second.restore();
    await second.settled;

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

  test('待機中の1本だけの配信も順番に出し、消化後はクラウドから復活しない', () async {
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

    // 1本だけの配信も飛ばさず出す。ただしセットの締めではないので、
    // 1本読んだだけでまとめクイズへは送らない。
    final promoted = container.read(dailySetProvider);
    expect(promoted.setId, 'X');
    expect(promoted.current?.id, 'x1');
    expect(promoted.isLast, isFalse);

    await controller.advance();
    await controller.settled;

    final state = container.read(dailySetProvider);
    expect(state.isActive, isFalse);
    expect(state.pendingSets, isEmpty);
    expect(store.remote.active, isNull);
    expect(store.remote.pending, isEmpty);
  });

  test('消化中に自動生成が走っても、進行中セットを奪わず待機列へ回す', () async {
    final byId = {
      for (final id in ['a1', 'a2', 'g1', 'g2']) id: _sentence(id),
    };
    final container = containerWith(byId);
    final controller = container.read(dailySetProvider.notifier);

    await controller.start(_set(['a1', 'a2']), setId: 'A');
    final accepted = await controller.acceptGeneratedSet(_set(['g1', 'g2']));

    expect(accepted, isFalse);
    final state = container.read(dailySetProvider);
    expect(state.setId, 'A');
    expect(state.current?.id, 'a1');
    expect(state.pendingSets.single.setId, 'g1');
  });

  test('セットを消化しきっていれば、生成結果はそのまま次のセットになる', () async {
    final byId = {
      for (final id in ['g1', 'g2']) id: _sentence(id)
    };
    final container = containerWith(byId);
    final controller = container.read(dailySetProvider.notifier);

    final accepted = await controller.acceptGeneratedSet(_set(['g1', 'g2']));

    expect(accepted, isTrue);
    expect(container.read(dailySetProvider).current?.id, 'g1');
  });

  test('1本だけのセットはまとめクイズの締めにしない', () async {
    final byId = {'s1': _sentence('s1')};
    final container = containerWith(byId);
    final controller = container.read(dailySetProvider.notifier);

    await controller.acceptDeliveredSet(setId: 'S', sentences: _set(['s1']));

    final state = container.read(dailySetProvider);
    expect(state.isActive, isTrue);
    expect(state.isLast, isFalse);
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

  // 進行位置を失った端末（旧キーを読み落としたビルドを経由した場合）の救済。
  group('配信docからの再構成', () {
    Map<String, ThaiSentence> byIds(List<String> ids) =>
        {for (final id in ids) id: _sentence(id)};

    test('答えた記録の次の1本から再開する', () async {
      final byId = byIds(['a', 'b', 'c']);
      final store = _MemoryProgressStore(byId)
        ..delivered = const DailySetRef(
          setId: 'A',
          sentenceIds: ['a', 'b', 'c'],
        );
      final container = containerWith(
        byId,
        progressStore: store,
        answered: {'a'},
      );

      await container.read(dailySetProvider.notifier).restored;

      final state = container.read(dailySetProvider);
      expect(state.setId, 'A');
      expect(state.total, 3);
      expect(state.current?.id, 'b');
    });

    test('全部答え終わっているセットは復活させない', () async {
      final byId = byIds(['a', 'b']);
      final store = _MemoryProgressStore(byId)
        ..delivered =
            const DailySetRef(setId: 'A', sentenceIds: ['a', 'b']);
      final container = containerWith(
        byId,
        progressStore: store,
        answered: {'a', 'b'},
      );

      final controller = container.read(dailySetProvider.notifier);
      await controller.restored;
      await controller.settled;

      expect(container.read(dailySetProvider).isActive, isFalse);
      // 完了として覚えるので、クラウド側から同じセットが戻ってこない。
      expect(store.remote.completedSetIds, contains('A'));
    });

    test('例文がローカルに揃っていなければ取り込み経路に任せる', () async {
      final byId = byIds(['a']);
      final store = _MemoryProgressStore(byId)
        ..delivered =
            const DailySetRef(setId: 'A', sentenceIds: ['a', 'b']);
      final container = containerWith(byId, progressStore: store);

      await container.read(dailySetProvider.notifier).restored;

      expect(container.read(dailySetProvider).isActive, isFalse);
      expect(store.remote.completedSetIds, isEmpty);
    });

    test('端末に記録が残っていれば配信docを見に行かない', () async {
      final byId = byIds(['a', 'b', 'x', 'y']);
      final store = _MemoryProgressStore(byId)
        ..delivered =
            const DailySetRef(setId: 'OLD', sentenceIds: ['x', 'y']);
      final container = containerWith(byId, progressStore: store);
      final controller = container.read(dailySetProvider.notifier);

      await controller.start(_set(['a', 'b']), setId: 'A');
      await controller.restored;

      expect(container.read(dailySetProvider).setId, 'A');
    });
  });
}
