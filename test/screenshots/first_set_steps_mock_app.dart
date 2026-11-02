// =============================================================================
// first_set_steps_mock_app.dart
// 初級者の初回セット1本目の手順カード（FirstSetSteps）を、本物の学習画面
// （TodayScreen）に差し込んだデータで載せてシミュレーターに出すモック。
// Firebase なし。下のボタンで状態を切り替える（AUTO=true なら 4 秒ごとに進む）。
//
//   flutter run -t test/screenshots/first_set_steps_mock_app.dart
//   flutter run -t test/screenshots/first_set_steps_mock_app.dart \
//     --dart-define=LANG=en --dart-define=AUTO=true
//   PHASE=4 で詳細から始める。
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/core/config/app_config.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/auth_provider.dart';
import 'package:thai_memo/presentation/providers/daily_set_provider.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/sentence_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/tts_provider.dart';
import 'package:thai_memo/presentation/providers/vocab_stats_provider.dart';
import 'package:thai_memo/presentation/screens/detail_screen.dart';
import 'package:thai_memo/presentation/screens/today_screen.dart';
import 'package:thai_memo/presentation/widgets/first_set_steps.dart';
import 'package:thai_memo/services/analytics_service.dart';
import 'package:thai_memo/services/daily_sentence_service.dart';
import 'package:thai_memo/services/tts_service.dart';

import 'store_mock_data.dart';

const _lang = String.fromEnvironment('LANG', defaultValue: 'ja');
const _auto = bool.fromEnvironment('AUTO');

/// 最初に出す場面（_phases の添字）。
const _initialPhase = int.fromEnvironment('PHASE');

/// 見せる場面。2本目は別の例文なので手順カードは出ない。詳細は最初の例文の詳細。
const _phases = ['①', '②', '③', '2本目', '詳細'];

void main() => runApp(const _MockApp());

class _MockApp extends StatefulWidget {
  const _MockApp();

  @override
  State<_MockApp> createState() => _MockAppState();
}

class _MockAppState extends State<_MockApp> {
  int _phase = _initialPhase;
  Timer? _timer;
  final _sentence = DailySentenceService.toSentence(
      'mock-sentence', storeSentenceJson(_lang));
  final _second = DailySentenceService.toSentence(
      'mock-sentence-2', storeSentenceJson(_lang));

  @override
  void initState() {
    super.initState();
    if (_auto) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        setState(() => _phase = (_phase + 1) % _phases.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Set<FirstSetStep> get _done => switch (_phase) {
        0 => const {},
        1 => const {FirstSetStep.listenSentence},
        _ => const {FirstSetStep.listenSentence, FirstSetStep.openDetail},
      };

  ThaiSentence get _shown => _phase == 3 ? _second : _sentence;

  @override
  Widget build(BuildContext context) {
    final sentences = [_sentence, _second];
    return ProviderScope(
      key: ValueKey(_phase),
      overrides: [
        analyticsServiceProvider.overrideWithValue(_NoopAnalytics()),
        ttsServiceProvider.overrideWithValue(_SilentTtsService()),
        authControllerProvider.overrideWith((ref) => _StubAuthController()),
        effectivePremiumProvider.overrideWithValue(false),
        planStatusProvider
            .overrideWithValue(const AsyncValue.data(PlanStatus.free)),
        generationParamsProvider.overrideWithValue(const {}),
        vocabStatsProvider.overrideWith(
          (ref) => Stream.value(const VocabStats(estimatedVocab: 0)),
        ),
        sentenceControllerProvider.overrideWith(
          (ref) => _StubSentenceController(SentenceStateSuccess(_shown)),
        ),
        // 入門者（まったく初めて）の初回セットは2本。
        dailySetProvider.overrideWith(
          (ref) => _StubDailySetController(
            DailySetState(
              setId: 'mock-set',
              sentences: sentences,
              index: _phase < 3 ? 0 : 1,
            ),
          ),
        ),
        firstSentenceIdProvider.overrideWith(
          (ref) => FirstSentenceIdController.fixed('mock-sentence'),
        ),
        firstStepsDoneProvider
            .overrideWith((ref) => FirstStepsDoneController.fixed(_done)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale(_lang),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: buildAppLightTheme(ThaiFont.sarabun),
        home: Scaffold(
          body: _phase >= 4
              ? DetailScreen(sentence: _sentence, source: 'mock')
              : const SafeArea(bottom: false, child: TodayScreen()),
          bottomNavigationBar: _PhaseBar(
            phase: _phase,
            onSelect: (p) => setState(() => _phase = p),
          ),
        ),
      ),
    );
  }
}

/// モック用の切り替え。下のタブの位置に置く。
class _PhaseBar extends StatelessWidget {
  const _PhaseBar({required this.phase, required this.onSelect});

  final int phase;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (final (i, label) in _phases.indexed)
              ButtonSegment(value: i, label: Text(label)),
          ],
          selected: {phase},
          onSelectionChanged: (s) => onSelect(s.first),
        ),
      ),
    );
  }
}

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

class _SilentTtsService extends Fake implements TtsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();

  @override
  void dispose() {}
}

class _NoopAnalytics extends Fake implements AnalyticsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class Fake {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
