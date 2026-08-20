// =============================================================================
// pitch_recorder_service.dart
// マイク収録（ネイティブ）と、そこからのF0（基本周波数）抽出。
//
// 判定ロジック（lib/core/pronunciation/）はマイクに依存しない純粋関数として
// 分けてあり、この層は「PCMを集めてフレームごとのF0にする」ところまでを持つ。
//
// マイクを握るのは SpeechCaptureService（ネイティブ）1箇所だけ。録音と音声認識で
// マイクを奪い合わないよう、ネイティブ側で1本の音声を両方へ分岐させている。
//
// F0抽出は重い。YINは窓長の2乗のオーダーで、5秒の録音では数億回の演算になる。
// 必ず別isolate（compute）で回すこと。UIスレッドで回すと録音の直後に画面が固まる。
// =============================================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/pronunciation/pitch_track.dart';
import '../core/pronunciation/yin.dart';
import 'speech_capture_service.dart';

/// 収録のサンプリングレート（Hz）。ネイティブ側の SAMPLE_RATE と一致させること。
///
/// 音声のF0は高くても400Hz程度なので16kHzで足りる。上げても精度は変わらず、
/// YINの計算量だけが増える。
const int kRecordSampleRate = 16000;

/// 解析窓の長さ（サンプル数）。16kHzで40ms。
///
/// 短くすると低い声を取り逃し、長くすると下降声のような速い動きが鈍る。
/// 40msはその折り合い。
const int kFrameSize = 640;

/// 窓をずらす幅（サンプル数）。16kHzで10ms。
const int kHopSize = 160;

/// 有声と認めるYINの確信度の下限。
///
/// **自前の YIN（[estimateF0]）は確信度を階調で返す**ので、ここが実際に効く。
/// ライブラリ版（`pitch_detector_dart`）は絶対閾値 0.20 を切らないフレームを
/// 確信度0で返しており、発話末の軋み声が全てそこに潰れていた（実機で 629
/// フレーム中 429 が無声判定、うち確信度 0.1 以上は 0 件）。
const double kMinPitchProbability = 0.5;

/// 人の声として妥当なF0の範囲（Hz）。外れた値は検出誤りとして捨てる。
const double kMinPlausibleF0 = 60;
const double kMaxPlausibleF0 = 450;

/// 1回の録音の上限（秒）。
///
/// 解析時間を頭打ちにするためのもの。例文1文はどれだけ遅くても10秒に収まる。
const int kMaxRecordingSeconds = 15;

/// F0抽出のためにisolateへ渡す引数。
class PitchExtractionRequest {
  final Uint8List pcm16;
  final int sampleRate;

  const PitchExtractionRequest(this.pcm16, this.sampleRate);
}

/// PCM16のバイト列を符号付き16bitの配列として読む。
///
/// プラットフォームから届くバイト列は先頭が2バイト境界に乗っているとは限らない。
/// 乗っていない場合に [Int16List.view] は例外を投げるので、そのときだけ複製する。
Int16List pcm16ToSamples(Uint8List bytes) {
  if (bytes.offsetInBytes % 2 == 0) {
    return Int16List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 2,
    );
  }
  return Int16List.view(Uint8List.fromList(bytes).buffer);
}

/// 波形の最大振幅（0.0〜1.0）。
///
/// 収録が無音かどうかの切り分けに使う。0 のままなら、マイクから音が
/// 届いていない（ネイティブ側の問題）。音はあるのにF0が取れないなら、
/// 形式か抽出側の問題、と切り分けられる。
double peakAmplitude(Int16List samples) {
  var peak = 0;
  for (final s in samples) {
    final v = s.abs();
    if (v > peak) peak = v;
  }
  return peak / 32768.0;
}

/// F0抽出の結果。フレーム数は揃っている。
class PitchExtractionResult {
  /// フレームごとのF0（Hz）。無声・低信頼は null。
  final List<double?> f0Hz;

  /// ピッチが取れなかったフレーム（YINが無声・低確信・範囲外と判断）。
  ///
  /// 音量で落としたフレーム（[energyRejected]）と**分けて数える**。発話末で
  /// 声が失われるとき、軋み声でピッチが取れないのか、音量が落ちて足切りされたのかで
  /// 直し方が変わる。
  final List<bool> pitchRejected;

  /// ピッチは取れたが音量が足りずに落としたフレーム。
  final List<bool> energyRejected;

  /// 周期性が弱くて落としたフレーム（YINが無声、または確信度が
  /// [kMinPitchProbability] 未満）。**軋み声はここに出る。**
  final List<bool> unpitched;

  /// 周期は取れたが、値が人の声の範囲（[kMinPlausibleF0]〜[kMaxPlausibleF0]）を
  /// 外れて落としたフレーム。**低すぎる声（発話末の落ち込み）はここに出る。**
  final List<bool> outOfRange;

  /// フレームごとの YIN の確信度。
  ///
  /// 落としたフレームの確信度が閾値のすぐ下に溜まっているなら、閾値を下げれば
  /// 戻る。ほぼ0なら本当に周期が無いので、下げても無駄で暗騒音を拾うだけ。
  /// **どちらかを見ないと閾値を動かせない。**
  final List<double> probability;

  /// フレームごとの音量（RMS）。
  ///
  /// **有声判定に使ったあと捨ててはいけない。** 共鳴音で繋がる音節の切れ目
  /// （`ชิ้น` น → `นี้` น）は F0 にも無声区間にも現れないが、**音量の谷には出る**
  /// （鼻音・側音は母音より弱い）。分割の手がかりとして最後まで運ぶ。
  final List<double> energy;

  const PitchExtractionResult({
    required this.f0Hz,
    required this.energy,
    this.pitchRejected = const [],
    this.energyRejected = const [],
    this.unpitched = const [],
    this.outOfRange = const [],
    this.probability = const [],
  });
}

/// PCM16のバイト列からフレームごとのF0（Hz）を取り出す。
///
/// 無声・低信頼のフレームは null。isolateで実行するためトップレベル関数にしてある。
///
/// **信頼度だけで有声を決めない。** YINは暗騒音にも高い信頼度を返すことがあり、
/// 押しはじめの無音が発声した区間として取り込まれる。音量の伴わないピッチは
/// 声ではないので、[gateByEnergy] で落とす。
Future<PitchExtractionResult> extractF0Frames(
  PitchExtractionRequest request,
) async {
  final samples = pcm16ToSamples(request.pcm16);

  final frames = <double?>[];
  final levels = <double>[];
  final unpitched = <bool>[];
  final outOfRange = <bool>[];
  final probabilities = <double>[];
  for (var start = 0; start + kFrameSize <= samples.length; start += kHopSize) {
    final window = List<double>.generate(
      kFrameSize,
      (i) => samples[start + i] / 32768.0,
      growable: false,
    );

    final result = estimateF0(window, request.sampleRate.toDouble());
    final pitch = result.f0Hz ?? 0;
    // **YIN の有声判定（`pitched`）で切らない。** 軋み声は閾値を切らないが
    // 周期は残っている。確信度で決める。
    final periodic = result.confidence >= kMinPitchProbability;
    final inRange = pitch >= kMinPlausibleF0 && pitch <= kMaxPlausibleF0;
    frames.add(periodic && inRange ? pitch : null);
    levels.add(frameRms(window));
    unpitched.add(!periodic);
    outOfRange.add(periodic && !inRange);
    probabilities.add(result.confidence);
  }
  final gated = gateByEnergy(frames, levels);
  return PitchExtractionResult(
    f0Hz: gated,
    energy: levels,
    pitchRejected: [for (final f in frames) f == null],
    unpitched: unpitched,
    outOfRange: outOfRange,
    probability: probabilities,
    // ピッチは取れていたのに、音量で落ちたフレーム。
    energyRejected: [
      for (var i = 0; i < frames.length; i++)
        frames[i] != null && gated[i] == null,
    ],
  );
}

/// 収録1回ぶんの解析入力。
class PronunciationCapture {
  /// フレームごとのF0（Hz）。無声・低信頼は null。
  final List<double?> f0Hz;

  /// フレームごとの音量（RMS）。[f0Hz] と同じ長さ。
  ///
  /// 共鳴音で繋がる音節の切れ目は F0 に出ないが、音量の谷には出る。
  final List<double> energy;

  /// 音声認識の結果。非対応端末では空文字。
  final String transcript;

  /// この端末で音声認識まで行えたか。
  final bool transcriptAvailable;

  /// 認識が使えなかった理由（実機での切り分け用）。
  final String recognitionStatus;

  const PronunciationCapture({
    required this.f0Hz,
    this.energy = const [],
    required this.transcript,
    required this.transcriptAvailable,
    this.recognitionStatus = 'not_started',
  });

  static const empty = PronunciationCapture(
    f0Hz: [],
    transcript: '',
    transcriptAvailable: false,
  );
}

/// マイク収録からF0系列と認識結果を得るサービス。
class PitchRecorderService {
  PitchRecorderService({SpeechCaptureService? capture})
      : _capture = capture ?? SpeechCaptureService();

  final SpeechCaptureService _capture;

  Timer? _limitTimer;
  bool _recording = false;

  bool get isRecording => _recording;

  /// マイクの使用許可の有無。ダイアログは出さない。
  Future<bool> hasPermission() => _capture.hasPermission();

  /// マイクの使用許可を求める。許可されたら true。
  Future<bool> requestPermission() => _capture.requestPermission();

  /// 収録を開始する。上限時間に達すると自動的に停止する。
  ///
  /// 上限で打ち切ったときは [onLimit] を呼ぶ。呼び出し側に伝えないと、
  /// 収録は止まっているのに画面だけ録音中のまま残る。
  Future<void> start({VoidCallback? onLimit}) async {
    if (_recording) return;

    await _capture.start();
    _recording = true;
    _limitTimer = Timer(
      const Duration(seconds: kMaxRecordingSeconds),
      () => unawaited(_capture.cancel().then((_) {
        _recording = false;
        onLimit?.call();
      })),
    );
  }

  /// 収録を止め、F0系列と認識結果を返す。
  ///
  /// F0抽出は別isolateで行う。
  Future<PronunciationCapture> stopAndExtract() async {
    _limitTimer?.cancel();
    _limitTimer = null;
    if (!_recording) return PronunciationCapture.empty;
    _recording = false;

    final result = await _capture.stop();

    // 失敗したときにどの段階で落ちたかを切り分けるための計測。
    final samples = pcm16ToSamples(result.pcm16);
    final peak = samples.isEmpty ? 0.0 : peakAmplitude(samples);
    // debugPrint(
      // 'pronunciation capture: ${result.pcm16.lengthInBytes} bytes, '
      // '${samples.length} samples '
      // '(${(samples.length / kRecordSampleRate).toStringAsFixed(2)}s), '
      // 'peak=${peak.toStringAsFixed(4)}, '
      // 'inputPeak=${result.inputPeak.toStringAsFixed(4)}, '
      // 'recognition=${result.recognitionStatus}',
    // );

    // 振幅がちょうど0＝マイクからデジタル無音が届いている。声が小さいのではなく
    // 入力経路が繋がっていない（シミュレータで macOS 側の権限が無い場合など）。
    // 「静かな場所でもう一度」と案内しても直らないので、F0を返さず失敗にする。
    if (samples.isNotEmpty && peak == 0) {
      return PronunciationCapture(
        f0Hz: const [],
        transcript: result.transcript,
        transcriptAvailable: result.transcriptAvailable,
        recognitionStatus: result.recognitionStatus,
      );
    }

    if (result.pcm16.lengthInBytes < kFrameSize * 2) {
      return PronunciationCapture(
        f0Hz: const [],
        transcript: result.transcript,
        transcriptAvailable: result.transcriptAvailable,
        recognitionStatus: result.recognitionStatus,
      );
    }

    final extracted = await compute(
      extractF0Frames,
      PitchExtractionRequest(result.pcm16, kRecordSampleRate),
    );
    final frames = extracted.f0Hz;
    // final voiced = frames.where((f) => f != null).length;
    // // 発話を3等分して、どこでどう失っているかを出す。末尾だけ落ちるなら
    // // 発話末の現象（軋み声か音量の減衰）で、全体に散るなら収録環境の問題。
    // final third = frames.length ~/ 3;
    // if (third > 0) {
      // final parts = <String>[];
      // for (var p = 0; p < 3; p++) {
        // final from = p * third;
        // final to = p == 2 ? frames.length : (p + 1) * third;
        // var weak = 0;
        // var range = 0;
        // var energyLost = 0;
        // for (var i = from; i < to; i++) {
          // if (i < extracted.energyRejected.length &&
              // extracted.energyRejected[i]) {
            // energyLost++;
          // } else if (i < extracted.outOfRange.length &&
              // extracted.outOfRange[i]) {
            // range++;
          // } else if (i < extracted.unpitched.length && extracted.unpitched[i]) {
            // weak++;
          // }
        // }
        // parts.add('${to - from - weak - range - energyLost}有声'
            // '/周期弱$weak/範囲外$range/音量欠$energyLost');
      // }
      // debugPrint('pronunciation loss: 前${parts[0]} 中${parts[1]} 後${parts[2]}');
      // // 落としたフレームの確信度がどこに溜まっているか。閾値のすぐ下に集まって
      // // いれば下げれば戻る。ほぼ0なら周期が本当に無い。
      // final bands = <String>[];
      // for (var p = 0; p < 3; p++) {
        // final from = p * third;
        // final to = p == 2 ? frames.length : (p + 1) * third;
        // var near = 0; // 0.3〜0.5（閾値のすぐ下）
        // var mid = 0; // 0.1〜0.3
        // var none = 0; // 0.1未満
        // for (var i = from; i < to; i++) {
          // if (i >= extracted.unpitched.length || !extracted.unpitched[i]) {
            // continue;
          // }
          // final value =
              // i < extracted.probability.length ? extracted.probability[i] : 0.0;
          // if (value >= 0.3) {
            // near++;
          // } else if (value >= 0.1) {
            // mid++;
          // } else {
            // none++;
          // }
        // }
        // bands.add('惜$near/中$mid/無$none');
      // }
      // debugPrint(
        // 'pronunciation confidence: 前${bands[0]} 中${bands[1]} 後${bands[2]}',
      // );
    // }
    // // 押しはじめの無音がどれだけ取り込まれずに済んだか。判定がずれたときに
    // // 「声の前に何フレーム捨てたか」を見られるよう常設する。
    // final lead = frames.indexWhere((f) => f != null);
    // debugPrint(
      // 'pronunciation f0: $voiced/${frames.length} voiced frames, '
      // 'lead silence=${lead < 0 ? frames.length : lead}',
    // );

    return PronunciationCapture(
      f0Hz: frames,
      energy: extracted.energy,
      transcript: result.transcript,
      transcriptAvailable: result.transcriptAvailable,
      recognitionStatus: result.recognitionStatus,
    );
  }

  /// 収録を破棄する（結果を使わない場合）。
  Future<void> cancel() async {
    _limitTimer?.cancel();
    _limitTimer = null;
    if (!_recording) return;
    _recording = false;
    await _capture.cancel();
  }

  Future<void> dispose() => cancel();
}
