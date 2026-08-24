// =============================================================================
// speech_capture_service.dart
// ネイティブ側のマイク収録との橋渡し。
//
// マイクを握るのはネイティブの1箇所だけにしてある。録音プラグインと音声認識
// プラグインを並べると2つがマイクを奪い合い、片方しか動かないため。ネイティブ側で
// 1本の音声を「ピッチ解析用のPCM」と「音声認識」の両方へ分岐させている。
//
// 音声認識は iOS のみ（端末内実行）。Android は未リリースのためPCM取得だけを
// 実装しており、transcriptAvailable = false が返る。
// =============================================================================


import 'package:flutter/services.dart';

/// 収録1回ぶんの生の結果。
class SpeechCaptureResult {
  /// PCM16 / 16kHz / mono のバイト列。
  final Uint8List pcm16;

  /// 音声認識の結果。認識できなかった場合や非対応端末では空文字。
  final String transcript;

  /// この端末で音声認識まで行えたか。
  ///
  /// false のときは「発音が通じなかった」ではなく「判定していない」。
  /// UIで混同させないために分けている。
  final bool transcriptAvailable;

  /// 認識が使えなかった理由。実機での切り分け用。
  ///
  /// ok / auth_denied / no_recognizer_for_locale / recognizer_unavailable /
  /// no_on_device_asset / android_unsupported / not_started。
  ///
  /// **シミュレータでは必ず no_on_device_asset になる**（端末内認識のアセットが
  /// 無いため）。実機でも、その端末にタイ語の認識アセットが入っていなければ同じ。
  /// 壊れているのか非対応なのかを区別できるようにこの値を返している。
  final String recognitionStatus;

  /// 変換前、マイクから届いた音声の最大振幅（0.0〜1.0）。
  ///
  /// 変換後のPCMが無音だったときに、マイクが無音なのか変換が壊しているのかを
  /// 切り分けるための計測。
  final double inputPeak;

  const SpeechCaptureResult({
    required this.pcm16,
    required this.transcript,
    required this.transcriptAvailable,
    this.recognitionStatus = 'not_started',
    this.inputPeak = 0,
  });

}

class SpeechCaptureService {
  static const MethodChannel _channel =
      MethodChannel('thai_memo/speech_capture');

  /// マイク（と音声認識）の使用許可。未許可なら要求ダイアログが出る。
  /// 現在の許可状態を返すだけ。ダイアログは出さない。
  Future<bool> hasPermission() async {
    final granted = await _channel.invokeMethod<bool>('hasPermission');
    return granted ?? false;
  }

  /// 許可ダイアログを出す。許可されたら true。
  ///
  /// 音声認識の許可は、その言語の端末内認識が使える端末でだけ聞く
  /// （[localeId] を渡すのはその判定のため）。
  Future<bool> requestPermission({String localeId = 'th-TH'}) async {
    final granted = await _channel
        .invokeMethod<bool>('requestPermission', {'localeId': localeId});
    return granted ?? false;
  }

  /// 収録を開始する。
  Future<void> start({String localeId = 'th-TH'}) =>
      _channel.invokeMethod<void>('start', {'localeId': localeId});

  /// 収録を止め、PCMと認識結果を受け取る。
  Future<SpeechCaptureResult> stop() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('stop');
    if (raw == null) {
      return SpeechCaptureResult(
        pcm16: Uint8List(0),
        transcript: '',
        transcriptAvailable: false,
      );
    }

    return SpeechCaptureResult(
      pcm16: raw['pcm'] as Uint8List? ?? Uint8List(0),
      transcript: raw['transcript'] as String? ?? '',
      transcriptAvailable: raw['transcriptAvailable'] as bool? ?? false,
      recognitionStatus: raw['recognitionStatus'] as String? ?? 'not_started',
      inputPeak: (raw['inputPeak'] as num?)?.toDouble() ?? 0,
    );
  }

  /// 収録を破棄する。
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}
