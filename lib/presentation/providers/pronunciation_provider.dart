// =============================================================================
// pronunciation_provider.dart
// 発音練習の状態管理。
//
// 録音 → F0抽出 → 判定 → 永続化 の一連を受け持つ。判定そのものは
// lib/core/pronunciation/ の純粋関数で、ここはその呼び出しと副作用だけを持つ。
//
// 状態遷移:
//   idle → recording → analyzing → result
//                                    └→ idle（もう一度）
//   マイク未許可: idle → permissionDenied
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database_constants.dart';
import '../../core/pronunciation/pronunciation_analyzer.dart';
import '../../core/pronunciation/pronunciation_scorer.dart';
import '../../core/pronunciation/speaker_range.dart';
import '../../core/pronunciation/transcript_match.dart';
import '../../core/thai_tone_analyzer.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../services/analytics_service.dart';
import '../../services/pitch_recorder_service.dart';
import 'analytics_provider.dart';

/// 発音練習の画面状態。
enum PronunciationPhase {
  idle,
  recording,
  analyzing,
  result,

  /// マイクの使用が許可されていない。
  permissionDenied,
}

class PronunciationState {
  final PronunciationPhase phase;

  /// 声調（ピッチ）の判定結果。[PronunciationPhase.result] のときだけ非 null。
  final PronunciationResult? result;

  /// 語ごとの「通じたか」。声調とは別軸の検査で、語数と同じ長さ。
  /// 端末が音声認識に対応していない場合は全て [WordRecognition.unavailable]。
  final List<WordRecognition> recognition;

  /// 結果表示で選択中の語（カーブを開いている語）。未選択なら null。
  final int? selectedWordIndex;

  const PronunciationState({
    this.phase = PronunciationPhase.idle,
    this.result,
    this.recognition = const [],
    this.selectedWordIndex,
  });

  PronunciationState copyWith({
    PronunciationPhase? phase,
    PronunciationResult? result,
    List<WordRecognition>? recognition,
    int? selectedWordIndex,
    bool clearSelection = false,
  }) =>
      PronunciationState(
        phase: phase ?? this.phase,
        result: result ?? this.result,
        recognition: recognition ?? this.recognition,
        selectedWordIndex:
            clearSelection ? null : (selectedWordIndex ?? this.selectedWordIndex),
      );
}

class PronunciationController extends StateNotifier<PronunciationState> {
  /// [recorder] を渡さない場合はこのコントローラが自分で持ち、破棄まで面倒を見る。
  ///
  /// 収録サービスを別プロバイダに置いて共有すると、そちらが先に破棄されたときに
  /// 収録中のセッションが打ち切られる。録音したはずのPCMが空になり
  /// 「声が拾えませんでした」に化けるので、寿命はこのコントローラに揃える。
  PronunciationController({
    PitchRecorderService? recorder,
    required DatabaseHelper database,
    required AnalyticsService analytics,
    required this.sentenceId,
  })  : _recorder = recorder ?? PitchRecorderService(),
        _database = database,
        _analytics = analytics,
        super(const PronunciationState());

  final PitchRecorderService _recorder;
  final DatabaseHelper _database;
  final AnalyticsService _analytics;
  final String sentenceId;

  static const _uuid = Uuid();

  @override
  void dispose() {
    unawaited(_recorder.dispose());
    super.dispose();
  }

  /// 録音を開始する。マイクが未許可なら許可を求め、断られたら状態を切り替える。
  Future<void> startRecording() async {
    if (state.phase == PronunciationPhase.recording) return;

    if (!await _recorder.hasPermission()) {
      state = const PronunciationState(
        phase: PronunciationPhase.permissionDenied,
      );
      return;
    }

    try {
      await _recorder.start();
    } catch (error) {
      // 収録が始められなければ、黙って idle に留まらせない。押しても何も
      // 起きない状態は原因が分からず、いちばん困る。
      debugPrint('pronunciation: failed to start capture: $error');
      if (!mounted) return;
      state = PronunciationState(
        phase: PronunciationPhase.result,
        result: PronunciationResult.failed(PronunciationFailure.captureFailed),
      );
      return;
    }
    if (!mounted) return;
    state = const PronunciationState(phase: PronunciationPhase.recording);
  }

  /// 録音を止めて判定する。
  ///
  /// 声調（ピッチ）と発音（通じたか）は別軸の検査なので、それぞれ独立に出す。
  /// 混ぜて1つの点数にすると、学習者はどちらを直せばよいか分からなくなる。
  Future<void> stopAndAnalyze({
    required List<ThaiTone> tones,
    required List<String> expectedWords,
  }) async {
    if (state.phase != PronunciationPhase.recording) return;
    state = const PronunciationState(phase: PronunciationPhase.analyzing);

    final capture = await _recorder.stopAndExtract();
    final profile = await _loadProfile();

    final result = analyzePronunciation(
      f0Hz: capture.f0Hz,
      tones: tones,
      profile: profile,
    );
    if (!capture.transcriptAvailable) {
      // シミュレータでは必ずここに来る（端末内認識のアセットが無い）。
      // 非対応なのか壊れているのかを実機で切り分けられるよう理由を出す。
      debugPrint(
        'pronunciation: speech recognition unavailable '
        '(${capture.recognitionStatus})',
      );
    }
    final recognition = matchTranscript(
      expectedWords: expectedWords,
      transcript: capture.transcript,
      available: capture.transcriptAvailable,
    );
    if (!mounted) return;

    state = PronunciationState(
      phase: PronunciationPhase.result,
      result: result,
      recognition: recognition,
    );

    if (result.isScored) {
      await _persist(result, profile, recognition);
    }
  }

  /// 結果を捨ててもう一度録音できる状態に戻す。
  void reset() {
    state = const PronunciationState();
  }

  /// 語のカーブ表示を開閉する。
  void toggleWord(int wordIndex) {
    if (state.selectedWordIndex == wordIndex) {
      state = state.copyWith(clearSelection: true);
    } else {
      state = state.copyWith(selectedWordIndex: wordIndex);
    }
  }

  Future<SpeakerPitchProfile?> _loadProfile() async {
    final row = await _database.getSpeakerPitchProfile();
    if (row == null) return null;

    return SpeakerPitchProfile(
      range: SpeakerRange(
        medianSemitone:
            (row[DatabaseConstants.columnProfileMedianSemitone] as num)
                .toDouble(),
        rangeSemitone:
            (row[DatabaseConstants.columnProfileRangeSemitone] as num)
                .toDouble(),
      ),
      sampleCount: row[DatabaseConstants.columnProfileSampleCount] as int? ?? 0,
    );
  }

  Future<void> _persist(
    PronunciationResult result,
    SpeakerPitchProfile? profile,
    List<WordRecognition> recognition,
  ) async {
    await _database.insertPronunciationAttempt(
      id: _uuid.v4(),
      sentenceId: sentenceId,
      overallScore: result.overallScore,
    );

    await _database.accumulateToneStats(_toneOutcomesOf(result.syllables));

    // 声域を推定できた回だけプロファイルへ反映する。蓄積プロファイルで
    // 代替した回まで書き戻すと、推定値を推定値で上書きして誤差が積み上がる。
    final fresh = result.freshRange;
    if (fresh != null) {
      final updated = profile?.merge(fresh) ??
          SpeakerPitchProfile(range: fresh, sampleCount: 1);
      await _database.saveSpeakerPitchProfile(
        medianSemitone: updated.range.medianSemitone,
        rangeSemitone: updated.range.rangeSemitone,
        sampleCount: updated.sampleCount,
      );
    }

    await _analytics.logPronunciationAttempt(
      sentenceId: sentenceId,
      score: result.overallScore,
      syllableCount: result.syllables.length,
      monotone: result.isMonotone,
      worstTone: worstToneOf(result.syllables),
      recognizedRatio: recognizedRatio(recognition),
    );
  }
}

/// 声調ごとの試行数と正解数を数える。
Map<String, ({int attempts, int correct})> _toneOutcomesOf(
  List<SyllableScore> scores,
) {
  final outcomes = <String, ({int attempts, int correct})>{};
  for (final score in scores) {
    if (score.verdict == ToneVerdict.unscored) continue;
    final key = score.tone.name;
    final previous = outcomes[key] ?? (attempts: 0, correct: 0);
    outcomes[key] = (
      attempts: previous.attempts + 1,
      correct: previous.correct +
          (score.verdict == ToneVerdict.correct ? 1 : 0),
    );
  }
  return outcomes;
}

/// 最も正答率が低かった声調の名前。採点対象が無ければ空文字。
///
/// 「上昇声が苦手」レポートの入口になる値で、GA4にも送る。
String worstToneOf(List<SyllableScore> scores) {
  final outcomes = _toneOutcomesOf(scores);
  if (outcomes.isEmpty) return '';

  String worst = '';
  double worstRate = double.infinity;
  for (final entry in outcomes.entries) {
    final rate = entry.value.correct / entry.value.attempts;
    if (rate < worstRate) {
      worstRate = rate;
      worst = entry.key;
    }
  }
  return worst;
}

/// 例文ごとの発音練習コントローラ。
///
/// 収録サービスはこのコントローラが所有する。別プロバイダに切り出すと、
/// そちらの寿命が尽きた拍子に収録中のセッションが打ち切られる。
final pronunciationControllerProvider = StateNotifierProvider.autoDispose
    .family<PronunciationController, PronunciationState, String>(
  (ref, sentenceId) => PronunciationController(
    database: DatabaseHelper.instance,
    analytics: ref.read(analyticsServiceProvider),
    sentenceId: sentenceId,
  ),
);
