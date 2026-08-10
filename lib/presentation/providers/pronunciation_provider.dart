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
import '../../services/tts_service.dart';
import 'analytics_provider.dart';
import 'tts_provider.dart';

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

  /// 発音の判定が使えなかった理由（ネイティブが返す理由コード）。
  ///
  /// 「非対応」で終わらせず、直せるものは直し方を案内するために持つ。
  /// タイ語の音声入力を入れれば使えるようになる端末が大半。
  final String recognitionStatus;

  const PronunciationState({
    this.phase = PronunciationPhase.idle,
    this.result,
    this.recognition = const [],
    this.selectedWordIndex,
    this.recognitionStatus = 'not_started',
  });

  PronunciationState copyWith({
    PronunciationPhase? phase,
    PronunciationResult? result,
    List<WordRecognition>? recognition,
    int? selectedWordIndex,
    bool clearSelection = false,
    String? recognitionStatus,
  }) =>
      PronunciationState(
        phase: phase ?? this.phase,
        result: result ?? this.result,
        recognition: recognition ?? this.recognition,
        selectedWordIndex:
            clearSelection ? null : (selectedWordIndex ?? this.selectedWordIndex),
        recognitionStatus: recognitionStatus ?? this.recognitionStatus,
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
    required TtsService tts,
    required this.sentenceId,
  })  : _recorder = recorder ?? PitchRecorderService(),
        _tts = tts,
        _database = database,
        _analytics = analytics,
        super(const PronunciationState());

  final PitchRecorderService _recorder;
  final DatabaseHelper _database;
  final AnalyticsService _analytics;
  final TtsService _tts;
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

    // お手本を再生したまま録音すると、自分の声と混ざって判定できない。
    // マイクを掴む前に必ず止める。
    await _tts.stopAll();

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
    required List<bool> shortSyllables,
    required List<int> syllablePoints,
    required List<String> expectedWords,
    List<String> syllableLabels = const [],
  }) async {
    if (state.phase != PronunciationPhase.recording) return;
    state = const PronunciationState(phase: PronunciationPhase.analyzing);

    final capture = await _recorder.stopAndExtract();
    final profile = await _loadProfile();

    if (!capture.transcriptAvailable) {
      // シミュレータでは必ずここに来る（端末内認識のアセットが無い）。
      // 非対応なのか壊れているのかを実機で切り分けられるよう理由を出す。
      debugPrint(
        'pronunciation: speech recognition unavailable '
        '(${capture.recognitionStatus})',
      );
    }
    // 総合点は声調と発音の両方から決まるので、採点より先に照合する。
    final recognition = matchTranscript(
      expectedWords: expectedWords,
      transcript: capture.transcript,
      available: capture.transcriptAvailable,
    );

    final result = analyzePronunciation(
      f0Hz: capture.f0Hz,
      energy: capture.energy,
      tones: tones,
      shortSyllables: shortSyllables,
      syllablePoints: syllablePoints,
      profile: profile,
      recognition: recognition,
    );
    // // 高さも形も「どのフレームがどの音節か」の上に乗っている。時間軸が保たれて
    // // いるか（DTWの帯が前提にしている）を追えるよう、まず全体の内訳を出す。
    // final measuredFrames = capture.f0Hz.where((v) => v != null).length;
    // final span = result.syllables.isEmpty
        // ? 0
        // : result.syllables.last.queryEnd - result.syllables.first.queryStart + 1;
    // debugPrint(
      // 'pronunciation frames: ${capture.f0Hz.length} total, '
      // '$measuredFrames measured, $span aligned',
    // );
    // // 発音がどれだけ点数に効いたかを追えるようにする。
    // debugPrint(
      // 'pronunciation score: tone=${result.toneScore.toStringAsFixed(1)} '
      // '-> overall=${result.overallScore.toStringAsFixed(1)} '
      // '(missing=${recognition.where((r) => r == WordRecognition.missing).length}'
      // '/${recognition.where((r) => r != WordRecognition.unavailable).length})',
    // );
    // // お手本の時間の取り分（budget）は音節の表記から決めている。実際の発話の
    // // 長さと食い違うと DTW の帯に張り付いて境界が動けず、隣の音節がフレームを
    // // 飲み込む。**どの音節がどれだけ食い違ったか**を割合で出す。
    // final totalPoints =
        // result.syllables.fold<int>(0, (a, s) => a + s.referencePoints);
    // final totalFrames = result.syllables.fold<int>(
      // 0,
      // (a, s) => a + (s.queryStart < 0 ? 0 : s.queryEnd - s.queryStart + 1),
    // );
    // // 音節の切れ目を録音そのものから決められるかを見る。子音（とくに閉鎖音）で
    // // 声が止まる位置は境界の手がかりになるが、共鳴音で繋がる境界には現れない。
    // // **どちらがどれだけあるか**を数えないと、境界を録音から取る案の可否が決まらない。
    // final gaps = result.voicelessGaps;
    // // 音量の谷は、共鳴音で繋がる切れ目の唯一の手がかり。何個拾えたかを出す。
    // final valleys = findEnergyValleys(capture.energy);
    // debugPrint(
      // 'pronunciation valleys: ${valleys.length}個 '
      // '${valleys.map((v) => v[0]).join(' ')}',
    // );
    // debugPrint(
      // 'pronunciation gaps: ${gaps.length}個 '
      // '(音節境界は${result.syllables.length - 1}個) '
      // '${gaps.map((g) => '${g[0]}-${g[1]}').join(' ')}',
    // );
    // // 各境界から、いちばん近い手がかり（途切れ・谷）までの距離。0 ならその境界は
    // // 録音から直接決められている。
    // final distances = <String>[];
    // for (var i = 1; i < result.syllables.length; i++) {
      // final boundary = result.syllables[i].queryStart;
      // if (boundary < 0) continue;
      // var best = -1;
      // for (final g in [...gaps, ...valleys]) {
        // final d = boundary < g[0]
            // ? g[0] - boundary
            // : boundary > g[1]
                // ? boundary - g[1]
                // : 0;
        // if (best < 0 || d < best) best = d;
      // }
      // distances.add('$i:$best');
    // }
    // debugPrint('pronunciation boundary→gap: ${distances.join(' ')}');
    // // 判定に納得がいかないときに、どの数字でそうなったかを追えるようにする。
    // for (final score in result.syllables) {
      // final correlation = score.shapeCorrelation;
      // final frames =
          // score.queryStart < 0 ? 0 : score.queryEnd - score.queryStart + 1;
      // final budgetShare = totalPoints == 0
          // ? 0.0
          // : score.referencePoints / totalPoints * 100;
      // final actualShare = totalFrames == 0 ? 0.0 : frames / totalFrames * 100;
      // final label = score.syllableIndex < syllableLabels.length
          // ? syllableLabels[score.syllableIndex]
          // : '';
      // debugPrint(
        // 'pronunciation syllable ${score.syllableIndex} ${score.tone.name} '
        // '$label: '
        // 'n=${score.queryValues.length} '
        // 'span=${score.queryStart}-${score.queryEnd} '
        // // 予算と実測の取り分。大きく開いていれば境界が帯に張り付いている。
        // 'share=${actualShare.toStringAsFixed(1)}%'
        // '/${budgetShare.toStringAsFixed(1)}% '
        // 'budget=${score.referencePoints} '
        // 'corr=${correlation?.toStringAsFixed(2) ?? '-'} '
        // 'slope=${score.shapeError.toStringAsFixed(2)} '
        // // 入り方は向きだけを見る。段差の値も出すが判定には使っていない。
        // 'step=${score.queryStep.toStringAsFixed(2)}'
        // '/${score.referenceStep.toStringAsFixed(2)} '
        // '(${stepDirectionOf(score.queryStep).name}'
        // ' vs ${stepDirectionOf(score.referenceStep).name}) '
        // 'link=${score.transitionError.toStringAsFixed(3)} '
        // // 採点が使った値をそのまま出す。ここで再計算すると、位置で中心を
        // // 決めている採点側とずれた数字が出てログが読めなくなる。
        // 'you=${score.queryLevel.toStringAsFixed(2)} '
        // 'model=${score.referenceLevel.toStringAsFixed(2)} '
        // 'lvl=${score.levelError.toStringAsFixed(2)} '
        // // どちらの根拠が効いたか。- は「根拠にできなかった」。
        // 'ok=${score.shapeAgrees == null ? "-" : score.shapeAgrees! ? "形" : "形x"}'
        // '/${score.stepAgrees == null ? "-" : score.stepAgrees! ? "入" : "入x"} '
        // '-> ${score.verdict.name}',
      // );
    // }

    if (!mounted) return;

    state = PronunciationState(
      phase: PronunciationPhase.result,
      result: result,
      recognition: recognition,
      recognitionStatus: capture.recognitionStatus,
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
    tts: ref.read(ttsServiceProvider),
    sentenceId: sentenceId,
  ),
);
