import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/tts_provider.dart';
import 'package:thai_memo/presentation/widgets/sentence_audio_player.dart';
import 'package:thai_memo/services/tts_service.dart';

/// 発話は stop されるまで終わらない、という実機の挙動だけを再現する。
class _FakeTtsService extends TtsService {
  final List<String> spoken = [];
  Completer<void>? _speaking;
  bool waitedForCancel = false;

  @override
  Future<void> speak(String text, {bool slow = false, bool keepVoice = false}) {
    spoken.add(text);
    return (_speaking = Completer<void>()).future;
  }

  @override
  Future<void> stop({bool waitForCancel = false}) async {
    waitedForCancel |= waitForCancel;
    if (_speaking?.isCompleted == false) _speaking!.complete();
    _speaking = null;
  }

  @override
  void dispose() {}
}

Widget _host(_FakeTtsService tts, {required Widget child}) {
  return ProviderScope(
    overrides: [ttsServiceProvider.overrideWithValue(tts)],
    child: MaterialApp(
      // テストは日本語の文言を検証する。実行環境のロケール（en）に
      // 引きずられないよう明示的に ja で描画する。
      locale: const Locale('ja'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('wordStartOffsets', () {
    test('本文に現れる順で開始位置を返す', () {
      expect(
        wordStartOffsets('ผมกินข้าว', ['ผม', 'กิน', 'ข้าว']),
        [0, 2, 5],
      );
    });

    test('空白を挟む本文でも位置が合う', () {
      expect(wordStartOffsets('ผม กิน', ['ผม', 'กิน']), [0, 3]);
    });

    test('同じ単語が2回出ても後ろの出現を拾う', () {
      expect(wordStartOffsets('กินกิน', ['กิน', 'กิน']), [0, 3]);
    });

    test('本文と分解がずれていたら頭出し不可として空を返す', () {
      expect(wordStartOffsets('ผมกิน', ['ผม', 'ดื่ม']), isEmpty);
    });

    test('単語が無ければ空', () {
      expect(wordStartOffsets('ผมกิน', const []), isEmpty);
    });
  });

  group('wordIndexAtProgress', () {
    const offsets = [0, 2, 5];
    const textLength = 9;

    test('位置以前で最後に始まる単語を選ぶ', () {
      for (final (progress, expected) in [
        (0.0, 0),
        (0.1, 0), // 0.9文字目 → 1語目
        (0.3, 1), // 2.7文字目 → 2語目
        (0.6, 2), // 5.4文字目 → 3語目
        (1.0, 2),
      ]) {
        expect(
          wordIndexAtProgress(
            offsets: offsets,
            textLength: textLength,
            progress: progress,
          ),
          expected,
          reason: 'progress=$progress',
        );
      }
    });

    test('頭出し不可なら先頭', () {
      expect(
        wordIndexAtProgress(
          offsets: const [],
          textLength: textLength,
          progress: 0.8,
        ),
        0,
      );
    });
  });

  group('SentenceAudioPlayer', () {
    testWidgets('単語分解があれば頭出しバーを出す', (tester) async {
      await tester.pumpWidget(_host(
        _FakeTtsService(),
        child: const SentenceAudioPlayer(
          text: 'ผมกินข้าว',
          words: ['ผม', 'กิน', 'ข้าว'],
        ),
      ));

      expect(find.byType(Slider), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.repeat), findsNothing);
      expect(find.byType(Chip), findsNothing);
      expect(find.text('再生時間'), findsNothing);
      expect(find.textContaining('残り'), findsNothing);
    });

    testWidgets('頭出しできない場合も無効な再生位置バーを固定表示する', (tester) async {
      await tester.pumpWidget(_host(
        _FakeTtsService(),
        child: const SentenceAudioPlayer(
          text: 'ผมกินข้าว',
          words: ['ผม', 'ดื่ม'],
        ),
      ));

      expect(find.byType(Slider), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('狭いカード幅でもコントロールが収まる', (tester) async {
      await tester.pumpWidget(_host(
        _FakeTtsService(),
        child: const SizedBox(
          width: 280,
          child: SentenceAudioPlayer(
            text: 'ผมกินข้าว',
            words: ['ผม', 'กิน', 'ข้าว'],
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(find.text('再生時間'), findsNothing);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('再生中は一時停止アイコンになり、一時停止で発話も止まる', (tester) async {
      final tts = _FakeTtsService();
      var playCount = 0;
      await tester.pumpWidget(_host(
        tts,
        child: SentenceAudioPlayer(
          text: 'ผมกินข้าว',
          words: const ['ผม', 'กิน', 'ข้าว'],
          onPlay: () => playCount++,
        ),
      ));

      final buttonCenter = tester.getCenter(find.byType(IconButton));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(playCount, 1);
      expect(tts.spoken, ['ผมกินข้าว']);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(tester.getCenter(find.byType(IconButton)), buttonCenter);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
      // 停止後にリピートが走らない
      expect(tts.spoken, ['ผมกินข้าว']);
    });

    testWidgets('読み終わると間を置いて先頭から繰り返す', (tester) async {
      final tts = _FakeTtsService();
      await tester.pumpWidget(_host(
        tts,
        child: const SentenceAudioPlayer(
          text: 'ผมกินข้าว',
          words: ['ผม', 'กิน', 'ข้าว'],
          repeatInterval: Duration(milliseconds: 500),
        ),
      ));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      // 読み終わり（発話完了）
      await tts.stop();
      await tester.pump();
      expect(tts.spoken.length, 1, reason: '間を置く前に読み直さない');
      expect(find.byIcon(Icons.pause), findsOneWidget, reason: '再生状態は続く');
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0);

      await tester.pump(const Duration(milliseconds: 500));
      expect(tts.spoken, ['ผมกินข้าว', 'ผมกินข้าว']);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
    });

    testWidgets('外から stopAll されるとリピートも止まり再生表示が戻る', (tester) async {
      final tts = _FakeTtsService();
      await tester.pumpWidget(_host(
        tts,
        child: const SentenceAudioPlayer(
          text: 'ผมกินข้าว',
          words: ['ผม', 'กิน', 'ข้าว'],
          repeatInterval: Duration(milliseconds: 500),
        ),
      ));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      // 画面遷移・タブ切り替え相当。
      await tts.stopAll();
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      expect(tts.spoken.length, 1, reason: '次の周回を再開しない');
    });

    testWidgets('長押しで1回だけ再生へ切り替えられる', (tester) async {
      final tts = _FakeTtsService();
      await tester.pumpWidget(_host(
        tts,
        child: const SentenceAudioPlayer(
          text: 'ผมกินข้าว',
          words: ['ผม', 'กิน', 'ข้าว'],
          repeatInterval: Duration(milliseconds: 500),
        ),
      ));

      await tester.longPress(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.text('リピート'), findsOneWidget);
      expect(find.text('1回だけ'), findsOneWidget);
      final repeatCenter = tester.getCenter(find.text('リピート'));
      final onceCenter = tester.getCenter(find.text('1回だけ'));
      expect(repeatCenter.dy, onceCenter.dy);
      expect(repeatCenter.dx, lessThan(onceCenter.dx));

      await tester.tap(find.text('1回だけ'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      await tts.stop();
      await tester.pump();

      expect(tts.spoken, ['ผมกินข้าว']);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0);

      await tester.pump(const Duration(milliseconds: 500));
      expect(tts.spoken, ['ผมกินข้าว']);
    });

    testWidgets('バーを動かすとその単語から読み直す', (tester) async {
      final tts = _FakeTtsService();
      var playCount = 0;
      await tester.pumpWidget(_host(
        tts,
        child: SentenceAudioPlayer(
          text: 'ผมกินข้าว',
          words: const ['ผม', 'กิน', 'ข้าว'],
          onPlay: () => playCount++,
        ),
      ));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      // つまみを右端までドラッグ → 最後の単語から
      final slider = tester.getCenter(find.byType(Slider));
      await tester.dragFrom(slider, const Offset(500, 0));
      await tester.pump();

      expect(tts.spoken, ['ผมกินข้าว', 'ข้าว']);
      expect(tts.waitedForCancel, isTrue);
      expect(playCount, 1, reason: 'シーク再開は新しい再生操作として記録しない');
      expect(find.byIcon(Icons.pause), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
    });

    testWidgets('途中へシークしても次の周回は必ず全文を先頭から再生する', (tester) async {
      final tts = _FakeTtsService();
      await tester.pumpWidget(_host(
        tts,
        child: const SentenceAudioPlayer(
          text: 'ผมกินข้าว',
          words: ['ผม', 'กิน', 'ข้าว'],
          repeatInterval: Duration(milliseconds: 500),
        ),
      ));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      final slider = tester.getCenter(find.byType(Slider));
      await tester.dragFrom(slider, const Offset(500, 0));
      await tester.pump();
      expect(tts.spoken, ['ผมกินข้าว', 'ข้าว']);

      // シーク位置から始めた現在の周を完了する。
      await tts.stop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // リピート範囲にシーク位置を残さず、次の周は全文へ戻る。
      expect(tts.spoken, ['ผมกินข้าว', 'ข้าว', 'ผมกินข้าว']);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
    });
  });
}
