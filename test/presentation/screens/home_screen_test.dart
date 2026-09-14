import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/presentation/providers/daily_set_provider.dart';
import 'package:thai_memo/presentation/screens/home_screen.dart';
import 'package:thai_memo/presentation/screens/learning_screen.dart';
import 'package:thai_memo/services/daily_sentence_service.dart';

ThaiSentence _sentence(String id) => ThaiSentence(
      id: id,
      thaiText: id,
      pronunciation: '',
      japaneseTranslation: '',
      wordBreakdowns: const [],
    );

void main() {
  group('shouldAdvanceDailySetCursor', () {
    final sentences = [_sentence('a'), _sentence('b'), _sentence('c')];
    final active = DailySetState(sentences: sentences, index: 0);

    test('確認クイズを解いた1本がカーソルと同じなら進める', () {
      expect(
        shouldAdvanceDailySetCursor(set: active, answered: _sentence('a')),
        isTrue,
      );
    });

    test('確認クイズを経ていなければ進めない', () {
      // 終了済みのまとめクイズが再起動で復元され、その「次のセット」を押した
      // 場合。ここで進めると1本目と、その確認クイズが飛ぶ。
      expect(
        shouldAdvanceDailySetCursor(set: active, answered: null),
        isFalse,
      );
    });

    test('解いた1本がカーソルと違えば進めない', () {
      expect(
        shouldAdvanceDailySetCursor(set: active, answered: _sentence('c')),
        isFalse,
      );
    });

    test('セットを消化していなければ従来どおり進める', () {
      expect(
        shouldAdvanceDailySetCursor(
          set: const DailySetState(),
          answered: null,
        ),
        isTrue,
      );
    });
  });

  group('isSameDailySet', () {
    test('同じ並びの通知を再度開いても消化中セットを作り直さない', () {
      final sentences = [_sentence('a'), _sentence('b'), _sentence('c')];
      final active = DailySetState(sentences: sentences, index: 1);
      final delivered = DailySentenceSet(
        setId: 'a',
        sentences: [_sentence('a'), _sentence('b'), _sentence('c')],
      );

      expect(isSameDailySet(active, delivered), isTrue);
    });

    test('本数または順序が違う新着セットは置き換える', () {
      final active = DailySetState(
        sentences: [_sentence('a'), _sentence('b')],
      );

      expect(
        isSameDailySet(
          active,
          DailySentenceSet(
            setId: 'x',
            sentences: [_sentence('b'), _sentence('a')],
          ),
        ),
        isFalse,
      );
    });

    test('通信断で通知対象の1本だけ返っても進行中セットを保つ', () {
      final active = DailySetState(
        sentences: [_sentence('a'), _sentence('b'), _sentence('c')],
        index: 2,
      );

      expect(
        isSameDailySet(
          active,
          DailySentenceSet(setId: 'a', sentences: [_sentence('a')]),
        ),
        isTrue,
      );
    });

    test('関係のない旧形式の1本配信は進行中セットと別物', () {
      final active = DailySetState(
        sentences: [_sentence('a'), _sentence('b')],
        index: 1,
      );

      expect(
        isSameDailySet(
          active,
          DailySentenceSet(setId: 'old', sentences: [_sentence('old')]),
        ),
        isFalse,
      );
    });
  });

  group('mergeDeliveredOutcome', () {
    test('1セットでも表示できていれば表示扱いにする', () {
      expect(
        mergeDeliveredOutcome(
          (displayed: false, imported: true),
          (displayed: true, imported: true),
        ),
        (displayed: true, imported: true),
      );
    });

    test('待機列へ回しただけなら取り込み扱いに留める', () {
      // 表示していないのに「表示した」と答えると、呼び出し側が空の画面のまま
      // 先へ進んでしまう（起動直後にサンプルのまま固まる原因だった）。
      expect(
        mergeDeliveredOutcome(noDelivery, (displayed: false, imported: true)),
        (displayed: false, imported: true),
      );
    });

    test('新着が無ければ何もしていない', () {
      expect(mergeDeliveredOutcome(noDelivery, noDelivery), noDelivery);
    });
  });

  group('runInitialLoad', () {
    test('成功したら復帰処理は走らず、完了として記録する', () async {
      var recovered = false;
      var completed = false;

      await runInitialLoad(
        load: () async {},
        recover: () async => recovered = true,
        markCompleted: () => completed = true,
      );

      expect(recovered, isFalse);
      expect(completed, isTrue);
    });

    test('起動ロードが落ちても復帰処理を通し、完了として記録する', () async {
      // ここで完了を記録し損ねると、フォアグラウンド復帰の再ロードも配信・
      // クォータのリスナーも全て素通りになり、再起動するまで直らない。
      var recovered = false;
      var completed = false;

      await runInitialLoad(
        load: () async => throw StateError('boom'),
        recover: () async => recovered = true,
        markCompleted: () => completed = true,
      );

      expect(recovered, isTrue);
      expect(completed, isTrue);
    });

    test('復帰処理まで落ちても完了として記録する', () async {
      var completed = false;

      await runInitialLoad(
        load: () async => throw StateError('boom'),
        recover: () async => throw StateError('boom again'),
        markCompleted: () => completed = true,
      );

      expect(completed, isTrue);
    });
  });

  group('shouldAutoLoadAfterSentenceQuotaRefresh', () {
    test('0から正数に戻り、当日未生成なら自動ロードする', () {
      expect(
        shouldAutoLoadAfterSentenceQuotaRefresh(
          previous: const AsyncData(0),
          next: const AsyncData(5),
          dailySentenceGenerated: false,
        ),
        isTrue,
      );
    });

    test('0から正数に戻っても当日生成済みなら自動ロードしない', () {
      expect(
        shouldAutoLoadAfterSentenceQuotaRefresh(
          previous: const AsyncData(0),
          next: const AsyncData(5),
          dailySentenceGenerated: true,
        ),
        isFalse,
      );
    });

    test('残数が正数へ変わっていない場合は自動ロードしない', () {
      expect(
        shouldAutoLoadAfterSentenceQuotaRefresh(
          previous: const AsyncData(2),
          next: const AsyncData(5),
          dailySentenceGenerated: false,
        ),
        isFalse,
      );
    });

    test('tier反映で残数が戻っても進行中セットを上書きしない', () {
      expect(
        shouldAutoLoadAfterSentenceQuotaRefresh(
          previous: const AsyncData(0),
          next: const AsyncData(20),
          dailySentenceGenerated: false,
          hasActiveSet: true,
        ),
        isFalse,
      );
    });
  });

}
