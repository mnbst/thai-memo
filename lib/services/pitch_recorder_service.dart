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
import 'package:pitch_detector_dart/pitch_detector.dart';

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

/// 有声と認めるYINの信頼度の下限。
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

/// PCM16のバイト列からフレームごとのF0（Hz）を取り出す。
///
/// 無声・低信頼のフレームは null。isolateで実行するためトップレベル関数にしてある。
Future<List<double?>> extractF0Frames(PitchExtractionRequest request) async {
  final samples = pcm16ToSamples(request.pcm16);

  final detector = PitchDetector(
    audioSampleRate: request.sampleRate.toDouble(),
    bufferSize: kFrameSize,
  );

  final frames = <double?>[];
  for (var start = 0; start + kFrameSize <= samples.length; start += kHopSize) {
    final window = List<double>.generate(
      kFrameSize,
      (i) => samples[start + i] / 32768.0,
      growable: false,
    );

    final result = await detector.getPitchFromFloatBuffer(window);
    final pitch = result.pitch;
    final usable = result.pitched &&
        result.probability >= kMinPitchProbability &&
        pitch >= kMinPlausibleF0 &&
        pitch <= kMaxPlausibleF0;
    frames.add(usable ? pitch : null);
  }
  return frames;
}

/// 収録1回ぶんの解析入力。
class PronunciationCapture {
  /// フレームごとのF0（Hz）。無声・低信頼は null。
  final List<double?> f0Hz;

  /// 音声認識の結果。非対応端末では空文字。
  final String transcript;

  /// この端末で音声認識まで行えたか。
  final bool transcriptAvailable;

  /// 認識が使えなかった理由（実機での切り分け用）。
  final String recognitionStatus;

  const PronunciationCapture({
    required this.f0Hz,
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

  /// マイクの使用許可。未許可なら要求ダイアログが出る。
  Future<bool> hasPermission() => _capture.hasPermission();

  /// 収録を開始する。上限時間に達すると自動的に停止する。
  Future<void> start() async {
    if (_recording) return;

    await _capture.start();
    _recording = true;
    _limitTimer = Timer(
      const Duration(seconds: kMaxRecordingSeconds),
      () => unawaited(_capture.cancel().then((_) => _recording = false)),
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
    debugPrint(
      'pronunciation capture: ${result.pcm16.lengthInBytes} bytes, '
      '${samples.length} samples '
      '(${(samples.length / kRecordSampleRate).toStringAsFixed(2)}s), '
      'peak=${peak.toStringAsFixed(4)}, '
      'inputPeak=${result.inputPeak.toStringAsFixed(4)}, '
      'recognition=${result.recognitionStatus}',
    );

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

    final frames = await compute(
      extractF0Frames,
      PitchExtractionRequest(result.pcm16, kRecordSampleRate),
    );
    final voiced = frames.where((f) => f != null).length;
    debugPrint(
      'pronunciation f0: $voiced/${frames.length} voiced frames',
    );

    return PronunciationCapture(
      f0Hz: frames,
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
