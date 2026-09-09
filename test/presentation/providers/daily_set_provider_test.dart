import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/data/sentence_repository.dart';
import 'package:thai_memo/presentation/providers/daily_set_provider.dart';
import 'package:thai_memo/presentation/providers/sentence_provider.dart';

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

  ProviderContainer containerWith(Map<String, ThaiSentence> byId) {
    final container = ProviderContainer(
      overrides: [
        sentenceRepositoryProvider
            .overrideWithValue(_FakeSentenceRepository(byId)),
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

  test('復元するものが無ければ何もしない', () async {
    SharedPreferences.setMockInitialValues({});
    final container = containerWith({});
    await container.read(dailySetProvider.notifier).restore();
    expect(container.read(dailySetProvider).isActive, isFalse);
  });
}
