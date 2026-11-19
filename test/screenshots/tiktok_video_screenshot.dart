// =============================================================================
// tiktok_video_screenshot.dart
// 例文の縦動画のフレームを書き出す。例文詳細でお手本を聞き、各欄を
// スクロールして見せ、学習単語の詳細を開き、確認クイズに答えるまでを1本にする。
// 通常の `flutter test` では拾われない（_test.dart で終わらない）。
//
//   flutter test test/screenshots/tiktok_video_screenshot.dart \
//     --dart-define=X_POST_SENTENCE=build/tiktok/sentence.json \
//     --dart-define=TIKTOK_QUIZ=build/tiktok/quiz.json \
//     --dart-define=TIKTOK_OUT=build/tiktok \
//     --dart-define=X_POST_AUDIO_MS=4200
//
// 出力:
//   frames/frame_0001.png ...  連番フレーム
//   frames.json                フレームレートと音声を差し込む位置
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/data/models/quiz_question.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/quiz_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/tts_provider.dart';
import 'package:thai_memo/presentation/screens/detail_screen.dart';
import 'package:thai_memo/presentation/screens/quiz_screen.dart';

import 'x_post_common.dart';

const int _fps = 20;
const Duration _frameGap = Duration(milliseconds: 1000 ~/ _fps);

/// 秒をフレーム数に。
int _f(double seconds) => (seconds * _fps).round();

const String _lang = String.fromEnvironment('X_POST_LANG', defaultValue: 'ja');
final _l10n = lookupL10n(const Locale(_lang));

/// 画面の比率は 9:16（1080x1920）。X・Threads・TikTok で共通。
const double _viewHeight = postLogicalWidth * 16 / 9;

/// お手本を読み上げる回数（リピート再生のまま流す）。
const int _plays = 3;

/// 使い方の欄を見せる秒数と、単語の欄全体に使う秒数。全体で約1分にする。
/// 英語は訳が長くなりがちなので使い方を長めに取る。
const double _usageSeconds = _lang == 'en' ? 6.0 : 5.0;
const double _wordsTotalSeconds = 18;

/// 確認クイズで正解を押すまでの考える間。見ている人が自分で答えを考えられる長さにする。
const double _quizThinkSeconds = 5.0;

/// 動画全体の上限。単語の欄の1語の時間をここから逆算して詰める。
const int _maxTotalMs = 60000;

/// 単語の欄のあとに残す時間の見込み（多めに取る）。学習単語の詳細は
/// 開く・下まで送る・閉じるまで、クイズは考える間・正解後の間まで。
const int _detailReserveMs = 10200;
const int _quizReserveMs = 12200;
const int _scrollReserveMs = 900;

const _contentKey = ValueKey('tiktok-content');

void main() {
  const sentencePath = String.fromEnvironment(
    'X_POST_SENTENCE',
    defaultValue: 'build/tiktok/sentence.json',
  );
  const quizPath = String.fromEnvironment(
    'TIKTOK_QUIZ',
    defaultValue: 'build/tiktok/quiz.json',
  );
  const outDir = String.fromEnvironment(
    'TIKTOK_OUT',
    defaultValue: 'build/tiktok',
  );
  const audioMs = int.fromEnvironment('X_POST_AUDIO_MS', defaultValue: 4000);

  testWidgets('例文→単語詳細→確認クイズを連番PNGに書き出す', (tester) async {
    final sentence = await preparePostSentence(sentencePath);
    // クイズを作れなかった例文（tools/x_post/build_quiz.py が書かない）は、
    // 単語の詳細を見せたところで終える。
    final quizFile = File(quizPath);
    final quiz = quizFile.existsSync()
        ? QuizQuestion.fromJson(
            json.decode(quizFile.readAsStringSync()) as Map<String, dynamic>,
          )
        : null;
    setPostView(tester, height: _viewHeight);

    final frames = Directory('$outDir/frames');
    if (frames.existsSync()) frames.deleteSync(recursive: true);
    frames.createSync(recursive: true);

    final rec = _Recorder(tester, frames);
    final finger = ValueNotifier<Offset?>(null);
    addTearDown(finger.dispose);

    // ---- 1. 例文詳細でお手本を聞く ----
    final tts = ScriptedPostTtsService(
      const Duration(milliseconds: audioMs),
      sentence.thaiText.length,
    );
    await tester.pumpWidget(
      _host(
        DetailScreen(sentence: sentence, source: 'tiktok'),
        finger: finger,
        overrides: [ttsServiceProvider.overrideWithValue(tts)],
      ),
    );
    await tester.pumpAndSettle();

    // 冒頭の間は置かず、1フレーム目からお手本を押しにいく。
    final listen = find.text(_l10n.sentenceListenModel).first;
    // アプリはリピート再生が既定。クイズに移るまで流しっぱなしにし、
    // 読み上げが始まった位置を全部記録して音声を重ねる。
    final speaks = <int>[];
    tts.onSpeak = () => speaks.add(rec.ms);
    await rec.tap(finger, listen, then: () => tester.tap(listen));
    // [_plays] 回目の読み上げが始まるまで待ち、言い終わってから止める
    // （途中で切ると頭の一音だけ鳴って聞き苦しい）。リピートが回らなくても
    // 止まらないよう、1周（読み上げ＋間1秒）×回数の倍を上限にする。
    final playsDeadline = rec.ms + (audioMs + 1000) * _plays * 2;
    while (speaks.length < _plays && rec.ms < playsDeadline) {
      await rec.hold(1);
    }
    final spokenUntil = speaks.last + audioMs;
    if (rec.ms < spokenUntil) {
      await rec
          .hold(((spokenUntil - rec.ms) / _frameGap.inMilliseconds).ceil());
    }
    final pause = find.byIcon(Icons.pause);
    if (pause.evaluate().isNotEmpty) {
      await rec.tap(finger, pause.first, then: () => tester.tap(pause.first));
    }
    tts.silenced = true;
    final audioEnd = rec.ms;
    await rec.hold(_f(0.5));

    // ---- 2. 各項目を画面の中央に送って見せる ----
    // 使い方の欄 → 単語を1つずつ。学習単語の行では詳細を開く。
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    await rec.scrollTo(
        position, _centerOffset(tester, position, _usageRect(tester)));
    await rec.hold(_f(_usageSeconds));

    final keyWordText =
        sentence.targetWords?.firstOrNull ?? quiz?.correctAnswer;
    final words = sentence.wordBreakdowns;
    // 1語の時間は、残りの語と後ろの場面（詳細・クイズ）を 60 秒から引いて
    // 均等に割る。長くても 3 秒（かつ単語の欄全体で約 18 秒）、短くても 1.5 秒。
    final maxWordMs =
        (_wordsTotalSeconds * 1000 / words.length).clamp(1500.0, 3000.0);
    var detailDone = !words.any((w) => w.wordText == keyWordText);
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final row = _wordRow(word.wordText);
      if (row.evaluate().isEmpty) continue;
      await rec.scrollTo(
        position,
        _centerOffset(tester, position, tester.getRect(row)),
      );
      final left = words.length - i;
      final reserve = (quiz != null ? _quizReserveMs : 1000) +
          (detailDone ? 0 : _detailReserveMs) +
          _scrollReserveMs * (left - 1);
      final wordMs = ((_maxTotalMs - reserve - rec.ms) / left)
          .clamp(1500.0, maxWordMs);
      await rec.hold((wordMs / _frameGap.inMilliseconds).round());
      if (word.wordText == keyWordText && !detailDone) {
        await _openWordDetail(rec, finger, row);
        detailDone = true;
      }
    }

    // ---- 3. 確認クイズに答える ----
    if (quiz != null) await _answerQuiz(rec, finger, sentence, quiz);
    if (quiz == null) await rec.hold(_f(1.0));

    File('$outDir/frames.json').writeAsStringSync(
      json.encode({
        'fps': _fps,
        'count': rec.count,
        'audio': [
          for (final at in speaks)
            {'file': 'audio.mp3', 'at_ms': at, 'end_ms': audioEnd},
        ],
      }),
    );
  });
}

/// 確認クイズの画面に切り替え、考える間を置いて正解を押す。
Future<void> _answerQuiz(
  _Recorder rec,
  ValueNotifier<Offset?> finger,
  ThaiSentence sentence,
  QuizQuestion quiz,
) async {
  final tester = rec.tester;
  await tester.pumpWidget(
    _host(
      Scaffold(
        appBar: AppBar(
          title: Text(_l10n.navLearn),
          automaticallyImplyLeading: false,
          actions: const [QuizProgressCounter()],
        ),
        body: QuizScreen(
          showAppBar: false,
          title: _l10n.learnQuizTitle,
          learningSentence: sentence,
          onBackToLearningStart: () {},
          nextButtonLabel: _l10n.learnNextSentence,
          onNextSentence: () async {},
        ),
      ),
      finger: finger,
      overrides: [
        ttsServiceProvider.overrideWithValue(SilentPostTtsService()),
        quizControllerProvider.overrideWith(
          (ref) => _ScriptedQuizController(QuizAnswering([quiz], 0, const [])),
        ),
      ],
    ),
  );
  await tester.pump();
  await rec.hold(_f(1.2));

  // 選択肢が長くて下が切れるときは、考える間に下まで送って全部見せる。
  final quizScroll = find.descendant(
    of: find.byType(QuizScreen),
    matching: find.byType(Scrollable),
  );
  if (quizScroll.evaluate().isNotEmpty) {
    final position = tester.state<ScrollableState>(quizScroll.first).position;
    if (position.maxScrollExtent > 0) {
      await rec.scrollTo(position, position.maxScrollExtent);
    }
  }

  // 考える間を置いてから正解を押す。指マークを選択肢の上に止めると
  // 押したように見えるので、押す直前まで出さない。
  await rec.hold(_f(_quizThinkSeconds));
  final correct = find.text(quiz.correctChoice).first;
  finger.value = tester.getCenter(correct);
  await rec.hold(_f(0.5));
  await tester.tap(correct);
  finger.value = null;
  await rec.hold(_f(4.0));
}

/// 学習単語の詳細（声調解説）を開いて見せ、閉じる。
Future<void> _openWordDetail(
  _Recorder rec,
  ValueNotifier<Offset?> finger,
  Finder row,
) async {
  final tester = rec.tester;
  await rec.tap(finger, row, then: () => tester.tap(row));
  await rec.hold(_f(3.0));
  // 2音節以上だと解説が画面に収まらない。下まで送って見せる。
  final inDialog = find.descendant(
    of: find.byType(Dialog).first,
    matching: find.byType(Scrollable),
  );
  if (inDialog.evaluate().isNotEmpty) {
    final position = tester.state<ScrollableState>(inDialog.first).position;
    if (position.maxScrollExtent > 0) {
      await rec.scrollTo(position, position.maxScrollExtent);
      await rec.hold(_f(3.0));
    }
  }
  await rec.hold(_f(1.5));
  Navigator.of(tester.element(find.byType(Dialog).first)).pop();
  await rec.hold(_f(0.8));
}

/// 単語の欄の1行（押すと詳細が開く InkWell）。本文中の同じ語とは別に、
/// 単語の欄は画面の下の方にあるので最後の一致を使う。
Finder _wordRow(String wordText) => find
    .ancestor(of: find.text(wordText).last, matching: find.byType(InkWell))
    .first;

/// 使い方の欄の範囲（見出しから単語の見出しの手前まで）。
Rect _usageRect(WidgetTester tester) {
  final top = tester.getTopLeft(find.text(_l10n.detailUsageSection).first).dy;
  final bottom =
      tester.getTopLeft(find.text(_l10n.detailWordsSection).first).dy;
  return Rect.fromLTRB(0, top, postLogicalWidth, bottom - 8);
}

/// [rect]（いまの画面座標）の中心が表示域の中央に来るスクロール位置。
/// 表示域より高ければ頭を上端に揃える。
double _centerOffset(WidgetTester tester, ScrollPosition position, Rect rect) {
  const viewTop = kToolbarHeight;
  final viewHeight = position.viewportDimension;
  final target = rect.height > viewHeight - 24
      ? rect.top - viewTop - 12
      : rect.center.dy - (viewTop + viewHeight / 2);
  return (position.pixels + target)
      .clamp(0.0, position.maxScrollExtent)
      .toDouble();
}

/// フレームを撮りながら時間を進める。
class _Recorder {
  _Recorder(this.tester, this.dir);

  final WidgetTester tester;
  final Directory dir;
  int count = 0;

  int get ms => count * _frameGap.inMilliseconds;

  Future<void> shoot() async {
    final png =
        (await tester.runAsync(() => capturePost(tester, _contentKey)))!;
    final name = 'frame_${(++count).toString().padLeft(4, '0')}.png';
    File('${dir.path}/$name').writeAsBytesSync(png);
  }

  Future<void> hold(int frames) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(_frameGap);
      await shoot();
    }
  }

  /// 指マークを出して少し置き、押して消す。
  Future<void> tap(
    ValueNotifier<Offset?> finger,
    Finder target, {
    required Future<void> Function() then,
  }) async {
    finger.value = tester.getCenter(target);
    await hold(_f(0.3));
    await then();
    await hold(1);
    finger.value = null;
  }

  Future<void> scrollTo(ScrollPosition position, double offset) async {
    final distance = (offset - position.pixels).abs();
    final duration = Duration(
      milliseconds: (distance * 1.6).clamp(500, 1400).round(),
    );
    unawaited(position.animateTo(
      offset,
      duration: duration,
      curve: Curves.easeInOut,
    ));
    await hold((duration.inMilliseconds / _frameGap.inMilliseconds).ceil() + 1);
  }
}

Widget _host(
  Widget screen, {
  required ValueListenable<Offset?> finger,
  required List<Override> overrides,
}) {
  // 場面ごとに差し替える override が違う。ProviderScope は override の
  // 入れ替えを許さないので、key を変えて作り直す。
  return ProviderScope(
    key: ValueKey(screen.runtimeType),
    overrides: [
      analyticsServiceProvider.overrideWithValue(NoopPostAnalytics()),
      ...overrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale(_lang),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: postThemeWithFallbacks(buildAppLightTheme(ThaiFont.sarabun)),
      // ダイアログも映すので、Navigator ごと包む。
      builder: (context, child) => RepaintBoundary(
        key: _contentKey,
        child: Stack(
          children: [
            Positioned.fill(child: child!),
            ValueListenableBuilder<Offset?>(
              valueListenable: finger,
              builder: (context, offset, _) => offset == null
                  ? const SizedBox.shrink()
                  : PostFinger(offset, dark: true),
            ),
          ],
        ),
      ),
      home: screen,
    ),
  );
}

/// 答えると本物と同じく、1問の確認クイズはすぐサマリーへ移る。
class _ScriptedQuizController extends StateNotifier<QuizState>
    implements QuizController {
  _ScriptedQuizController(super.state);

  @override
  Future<void> answerQuestion(
    int choiceIndex, {
    int hintLevel = 0,
    bool reviewedSentence = false,
  }) async {
    final s = state as QuizAnswering;
    final q = s.questions[s.index];
    final ok = q.choices[choiceIndex] == q.correctChoice;
    state = QuizSummary(s.questions, [ok], ok ? 1 : 0, const {}, [choiceIndex]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
