// =============================================================================
// store_mock_screens.dart
// ストア用スクショの素材（アプリの画面）を、差し込んだデータで描く。
// 通常の `flutter test` では拾われない。
//
//   flutter test test/screenshots/store_mock_screens.dart
//
// - 01_today:         学習タブ（プレミアム・642語）
// - 02_detail:        例文の詳細（単語の分解と使い方）
// - 03_pronunciation: 発音練習の結果（1音節だけ惜しい）。判定は本物の採点に
//                     合成したピッチを通して出す
// - 04_quiz:          まとめクイズで正解した直後
// - 05_topics:        テーマ選択（タイBLドラマを選択中）
// - 06_ranking:       語彙ランキング（学習者が十分いる状態）
//
// 例文・クイズの中身は store_mock_data.dart。出力は
// build/store_shots/raw/<device>/<lang>/<id>.png で、その後
// store_screenshots.dart で見出しと端末の枠を合成する。
// =============================================================================

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/core/constants/generation_constants.dart';
import 'package:thai_memo/domain/sentence_tone_spans.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';
import 'package:thai_memo/data/datasources/local/database_helper.dart';
import 'package:thai_memo/data/models/quiz_question.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/auth_provider.dart';
import 'package:thai_memo/presentation/providers/daily_set_provider.dart';
import 'package:thai_memo/presentation/providers/leaderboard_provider.dart';
import 'package:thai_memo/presentation/providers/pronunciation_provider.dart';
import 'package:thai_memo/presentation/providers/quiz_provider.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/sentence_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/tts_provider.dart';
import 'package:thai_memo/presentation/providers/vocab_stats_provider.dart';
import 'package:thai_memo/presentation/screens/detail_screen.dart';
import 'package:thai_memo/presentation/screens/quiz_screen.dart';
import 'package:thai_memo/presentation/screens/ranking_screen.dart';
import 'package:thai_memo/presentation/screens/today_screen.dart';
import 'package:thai_memo/presentation/widgets/tablet_width_limit.dart';
import 'package:thai_memo/presentation/widgets/topic_picker.dart';
import 'package:thai_memo/services/analytics_service.dart';
import 'package:thai_memo/services/daily_sentence_service.dart';
import 'package:thai_memo/services/pitch_recorder_service.dart';
import 'package:thai_memo/services/tts_service.dart';

import '../helpers/f0_synthesizer.dart';
import 'store_mock_data.dart';

const String _rawDir = 'build/store_shots/raw';
const List<String> _fallbacks = [
  'NotoSans_regular',
  'NotoSansJP',
  'Sarabun_regular',
];

/// 端末ごとの論理サイズ・倍率・セーフエリア。寸法はストアが求める値になる。
class _Device {
  const _Device(this.id, this.size, this.ratio, this.top, this.bottom);

  final String id;
  final Size size;
  final double ratio;
  final double top;
  final double bottom;
}

const _devices = [
  _Device('iphone', Size(440, 956), 3, 62, 34), // 1320x2868
  _Device('ipad', Size(1032, 1376), 2, 24, 20), // 2064x2752
];

/// 自分の語彙スコアと順位。分布の総数と合わせて「上位7%」程度に見せる。
const int _myVocab = 642;
const int _myRank = 86;

/// 1枚ぶんの描き方。[act] は描いた後の操作（スクロール・録音など）。
class _Shot {
  const _Shot(this.id, this.build, {this.topic, this.act});

  final String id;
  final Widget Function(ThaiSentence sentence, String lang) build;

  /// 「次のテーマ」に出すテーマ。
  final String? topic;
  final Future<void> Function(WidgetTester tester, L10n l10n)? act;
}

final _shots = [
  _Shot(
    '01_today',
    (s, lang) => const _TabShell(child: TodayScreen()),
    topic: GenerationConstants.travelTopic,
  ),
  _Shot(
    '02_detail',
    (s, lang) => DetailScreen(sentence: s, source: 'store'),
  ),
  _Shot(
    '03_pronunciation',
    (s, lang) => DetailScreen(sentence: s, source: 'store'),
    act: _practice,
  ),
  _Shot(
    '04_quiz',
    (s, lang) => _TabShell(child: QuizScreen(title: lookupL10n(Locale(lang)).navLearn)),
  ),
  _Shot(
    '05_topics',
    (s, lang) => const _TopicPickerHost(),
    topic: GenerationConstants.pickerTopics.first,
  ),
  _Shot('06_ranking', (s, lang) => const RankingScreen()),
];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
  });

  for (final device in _devices) {
    for (final lang in ['ja', 'en']) {
      for (final shot in _shots) {
        testWidgets('${device.id}/$lang ${shot.id}', (tester) async {
          _setView(tester, device);
          final sentence = DailySentenceService.toSentence(
            'store-sentence',
            storeSentenceJson(lang),
          );
          await tester.pumpWidget(_host(lang, device, shot, sentence));
          await tester.pumpAndSettle();
          await shot.act?.call(tester, lookupL10n(Locale(lang)));
          await tester.pumpAndSettle();
          await _save(tester, device, lang, shot.id);
        }, variant: _ios);
      }
    }
  }
}

/// 戻るボタンの形などを iOS にそろえる。
final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);

void _setView(WidgetTester tester, _Device device) {
  tester.view.devicePixelRatio = device.ratio;
  tester.view.physicalSize = device.size * device.ratio;
  tester.view.padding = FakeViewPadding(
    top: device.top * device.ratio,
    bottom: device.bottom * device.ratio,
  );
  addTearDown(tester.view.reset);
}

/// 対象の要素がアプリバーのすぐ下に来るまでスクロールする。
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  final position =
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  final top = tester.getTopLeft(target.first).dy;
  final viewportTop = tester.getTopLeft(find.byType(Scrollable).first).dy;
  position.jumpTo(
    (position.pixels + top - viewportTop - 230)
        .clamp(0.0, position.maxScrollExtent),
  );
  await tester.pumpAndSettle();
}

/// 発音練習を開き、押したまま話して離す。録音は合成したピッチに差し替えてある。
/// 結果が出たら惜しかった語のカーブを開き、結果が画面に収まるよう送る。
Future<void> _practice(WidgetTester tester, L10n l10n) async {
  await tester.tap(find.text(l10n.sentencePractice).first);
  await tester.pumpAndSettle();
  final hold = find.text(l10n.pronunciationHoldToSpeak).first;
  final gesture = await tester.startGesture(tester.getCenter(hold));
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.up();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(
    tester.element(find.byType(DetailScreen)),
  );
  container
      .read(pronunciationControllerProvider(
              (sentenceId: 'store-sentence', scope: 'detail'))
          .notifier)
      .toggleWord(2);
  await tester.pumpAndSettle();
  await _scrollTo(tester, find.text(l10n.pronunciationTitle));
}

Widget _host(String lang, _Device device, _Shot shot, ThaiSentence sentence) {
  final quiz = QuizQuestion.fromJson(storeQuizJson(lang));
  return ProviderScope(
    overrides: [
      analyticsServiceProvider.overrideWithValue(_NoopAnalytics()),
      ttsServiceProvider.overrideWithValue(_SilentTtsService()),
      authControllerProvider.overrideWith((ref) => _StubAuthController()),
      effectivePremiumProvider.overrideWithValue(true),
      planStatusProvider
          .overrideWithValue(const AsyncValue.data(PlanStatus.premium)),
      generationParamsProvider.overrideWithValue({'topic': shot.topic}),
      vocabStatsProvider.overrideWith(
        (ref) => Stream.value(const VocabStats(estimatedVocab: _myVocab)),
      ),
      myRankProvider.overrideWith((ref) async => _myRank),
      leaderboardRowsProvider.overrideWith((ref) async => _rows),
      vocabDistributionProvider.overrideWith((ref) async => _distribution),
      sentenceControllerProvider.overrideWith(
        (ref) => _StubSentenceController(SentenceStateSuccess(sentence)),
      ),
      dailySetProvider.overrideWith(
        (ref) => _StubDailySetController(
          DailySetState(
            setId: 'store-set',
            sentences: List.filled(5, sentence),
            index: 1,
          ),
        ),
      ),
      quizControllerProvider.overrideWith(
        (ref) => _StubQuizController(
          QuizShowResult(
            List.filled(5, quiz),
            3,
            const [true, true, true],
            quiz.choices.indexOf(quiz.correctChoice),
            true,
          ),
        ),
      ),
      pronunciationControllerProvider.overrideWith(
        (ref, key) => PronunciationController(
          recorder: _SyntheticRecorder(sentence),
          database: _NoopDatabase(),
          analytics: _NoopAnalytics(),
          tts: _SilentTtsService(),
          sentenceId: key.sentenceId,
          scope: key.scope,
        ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(lang),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: _themeWithFallbacks(buildAppLightTheme(ThaiFont.sarabun)),
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('store-mock'),
        child: Stack(
          children: [
            TabletWidthLimit(child: child!),
            _StatusBar(height: device.top, isPhone: device.id == 'iphone'),
          ],
        ),
      ),
      // タブの画面は根に置き、それ以外は1つ前に空の画面を積んで戻るボタンを出す。
      initialRoute: shot.build(sentence, lang) is _TabShell ? '/' : '/screen',
      routes: {
        '/': (_) => shot.build(sentence, lang),
        '/screen': (_) => shot.build(sentence, lang),
      },
    ),
  );
}

/// 下のタブ（学習／履歴／設定）。HomeScreen と同じ並びで、学習を選んだ状態。
class _TabShell extends StatelessWidget {
  const _TabShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.school_outlined),
            selectedIcon: const Icon(Icons.school),
            label: l10n.navLearn,
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: l10n.navHistory,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}

/// 録音の代わりに、例文の声調どおりのピッチを返す。
/// [storeMissedSyllable] の音節だけ別の声調で言ったことにして「惜しい」を作る。
class _SyntheticRecorder extends Fake implements PitchRecorderService {
  _SyntheticRecorder(this.sentence);

  final ThaiSentence sentence;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start({VoidCallback? onLimit}) async {}

  @override
  Future<PronunciationCapture> stopAndExtract() async {
    final spans = buildSentenceToneSpans(
      sentence.wordBreakdowns,
      thaiText: sentence.thaiText,
    );
    return PronunciationCapture(
      f0Hz: synthesizeF0(
        tones: spans.tones,
        shortSyllables: spans.shortSyllables,
        syllablePoints: spans.syllablePoints,
        substitutions: {storeMissedSyllable: ThaiTone.rising},
        unvoicedOnsetFrames: 3,
      ),
      transcript: sentence.thaiText,
      transcriptAvailable: true,
      recognitionStatus: 'ok',
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _NoopDatabase extends Fake implements DatabaseHelper {
  @override
  Future<Map<String, dynamic>?> getSpeakerPitchProfile() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// サインイン済み（バナーを出さない）。
class _StubAuthController extends StateNotifier<AuthState>
    implements AuthController {
  _StubAuthController() : super(const AuthState(isLinked: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _StubSentenceController extends StateNotifier<SentenceState>
    implements SentenceController {
  _StubSentenceController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _StubDailySetController extends StateNotifier<DailySetState>
    implements DailySetController {
  _StubDailySetController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _StubQuizController extends StateNotifier<QuizState>
    implements QuizController {
  _StubQuizController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// TTS はプラグイン実体を持たないので、呼ばれても何もしない。
class _SilentTtsService extends Fake implements TtsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();

  @override
  void dispose() {}
}

const _rows = [
  LeaderboardEntry(
      uid: 'a', nickname: 'Ploy Srisuk', vocab: 1864, rank: 1, isMe: false),
  LeaderboardEntry(
      uid: 'b', nickname: 'Nattapong Kaew', vocab: 1752, rank: 2, isMe: false),
  LeaderboardEntry(
      uid: 'c', nickname: 'Mali Chaiyo', vocab: 1689, rank: 3, isMe: false),
  LeaderboardEntry(
      uid: 'd', nickname: 'Arthit Boonmee', vocab: 655, rank: 85, isMe: false),
  LeaderboardEntry(
      uid: 'me', nickname: 'Fah Rattana', vocab: _myVocab, rank: _myRank, isMe: true),
  LeaderboardEntry(
      uid: 'e', nickname: 'Kanya Somsri', vocab: 631, rank: 87, isMe: false),
];

const _distribution = VocabDistribution(
  total: 1240,
  bands: [
    VocabBand(min: 1, max: 99, count: 412, isMine: false),
    VocabBand(min: 100, max: 100, count: 168, isMine: false),
    VocabBand(min: 101, max: 300, count: 297, isMine: false),
    VocabBand(min: 301, max: 600, count: 236, isMine: false),
    VocabBand(min: 601, max: 1000, count: 94, isMine: true),
    VocabBand(min: 1001, max: null, count: 33, isMine: false),
  ],
);

/// 開いた直後にテーマ選択ダイアログを出す。背後は空の画面。
class _TopicPickerHost extends ConsumerStatefulWidget {
  const _TopicPickerHost();

  @override
  ConsumerState<_TopicPickerHost> createState() => _TopicPickerHostState();
}

class _TopicPickerHostState extends ConsumerState<_TopicPickerHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => showTopicPicker(context, ref),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).settingsTopic)),
    );
  }
}

/// iOS のステータスバー（9:41・電波・Wi-Fi・電池満タン）。
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.height, required this.isPhone});

  final double height;
  final bool isPhone;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF111111);
    final size = isPhone ? 17.0 : 14.0;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isPhone ? 44 : 22),
        child: Row(
          crossAxisAlignment:
              isPhone ? CrossAxisAlignment.center : CrossAxisAlignment.end,
          children: [
            Text(
              '9:41',
              style: TextStyle(
                fontFamily: 'NotoSans_600',
                fontSize: size,
                color: color,
                decoration: TextDecoration.none,
              ),
            ),
            const Spacer(),
            Icon(Icons.signal_cellular_alt, size: size + 1, color: color),
            const SizedBox(width: 5),
            Icon(Icons.wifi, size: size + 1, color: color),
            const SizedBox(width: 5),
            _Battery(height: size * 0.72),
          ],
        ),
      ),
    );
  }
}

class _Battery extends StatelessWidget {
  const _Battery({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF111111);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: height * 2.1,
          height: height,
          padding: const EdgeInsets.all(1.6),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
            borderRadius: BorderRadius.circular(height * 0.3),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(height * 0.2),
            ),
          ),
        ),
        Container(
          width: 1.5,
          height: height * 0.36,
          margin: const EdgeInsets.only(left: 1),
          color: color.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}

Future<void> _save(
  WidgetTester tester,
  _Device device,
  String lang,
  String id,
) async {
  final png = (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('store-mock')),
    );
    final image = await boundary.toImage(pixelRatio: device.ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;
  final file = File('$_rawDir/${device.id}/$lang/$id.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png);
  // ignore: avoid_print
  print('WROTE ${file.path}');
}

class _NoopAnalytics extends Fake implements AnalyticsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// 日本語・IPA のグリフを持たないフォントで豆腐にならないよう、フォールバックを足す。
ThemeData _themeWithFallbacks(ThemeData theme) {
  TextStyle? withFallbacks(TextStyle? style) => style?.copyWith(
        fontFamily: style.fontFamily ?? _fallbacks.first,
        fontFamilyFallback: _fallbacks,
      );
  ButtonStyle? patch(ButtonStyle? style) {
    if (style == null) return null;
    final original = style.textStyle;
    return style.copyWith(
      textStyle: WidgetStateProperty.resolveWith(
        (states) => withFallbacks(original?.resolve(states)),
      ),
    );
  }

  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamilyFallback: _fallbacks),
    primaryTextTheme:
        theme.primaryTextTheme.apply(fontFamilyFallback: _fallbacks),
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: withFallbacks(theme.appBarTheme.titleTextStyle),
    ),
    dialogTheme: theme.dialogTheme.copyWith(
      titleTextStyle: withFallbacks(
        theme.dialogTheme.titleTextStyle ?? theme.textTheme.titleLarge,
      ),
    ),
    navigationBarTheme: theme.navigationBarTheme.copyWith(
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => withFallbacks(
          theme.navigationBarTheme.labelTextStyle?.resolve(states) ??
              theme.textTheme.labelMedium,
        ),
      ),
    ),
    listTileTheme: theme.listTileTheme.copyWith(
      titleTextStyle: withFallbacks(
        theme.listTileTheme.titleTextStyle ?? theme.textTheme.bodyLarge,
      ),
      subtitleTextStyle: withFallbacks(
        theme.listTileTheme.subtitleTextStyle ?? theme.textTheme.bodyMedium,
      ),
    ),
    elevatedButtonTheme:
        ElevatedButtonThemeData(style: patch(theme.elevatedButtonTheme.style)),
    filledButtonTheme:
        FilledButtonThemeData(style: patch(theme.filledButtonTheme.style)),
    outlinedButtonTheme:
        OutlinedButtonThemeData(style: patch(theme.outlinedButtonTheme.style)),
    textButtonTheme:
        TextButtonThemeData(style: patch(theme.textButtonTheme.style)),
  );
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths,
      {bool firstOnly = false}) async {
    final loader = FontLoader(family);
    var any = false;
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      any = true;
      loader
          .addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      if (firstOnly) break;
    }
    if (any) await loader.load();
  }

  const weights = {
    'Regular': 'regular',
    'Medium': '500',
    'SemiBold': '600',
    'Bold': '700',
  };
  for (final entry in weights.entries) {
    await load(
        'Sarabun_${entry.value}', ['google_fonts/Sarabun-${entry.key}.ttf']);
    await load(
        'NotoSans_${entry.value}', ['google_fonts/NotoSans-${entry.key}.ttf']);
  }
  await load('MaterialIcons', _materialIconsCandidates(), firstOnly: true);
  await load('NotoSansJP', ['tools/x_post/fonts/NotoSansJP-Regular.otf']);
}

List<String> _materialIconsCandidates() {
  const relative = 'artifacts/material_fonts/MaterialIcons-Regular.otf';
  final paths = <String>[];
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) paths.add('$root/bin/cache/$relative');
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    paths.add('${dir.path}/$relative');
    dir = dir.parent;
  }
  return paths;
}
