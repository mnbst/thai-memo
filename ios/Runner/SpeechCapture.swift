import AVFoundation
import Flutter
import Speech

/// マイクを1本だけ握り、そこから取れた音声をピッチ解析用のPCMと音声認識の両方へ流す。
///
/// 録音プラグインと音声認識プラグインを並べると、2つがマイクを奪い合って片方しか
/// 動かない。AVAudioEngine のタップを1つだけ張り、同じバッファを
/// SFSpeechAudioBufferRecognitionRequest とPCMバッファの両方へ渡すことで避ける。
///
/// 音声認識は端末内実行（requiresOnDeviceRecognition）を優先する。発音の音声を
/// サーバーへ送らないため。対応していない端末では認識だけを諦め、ピッチ判定は続ける。
final class SpeechCapture {
  /// ピッチ解析に渡すPCMの形式。Dart側の kRecordSampleRate と一致させること。
  private static let targetSampleRate: Double = 16000

  private let audioEngine = AVAudioEngine()
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var converter: AVAudioConverter?

  private var pcmData = Data()
  private var transcript = ""
  private var transcriptAvailable = false
  private var capturing = false

  /// タップに届いた**変換前**の音声の最大振幅。
  ///
  /// 変換後のPCMが無音だったときに、マイクが無音なのか変換が壊しているのかを
  /// 切り分けるための計測。シミュレータでは macOS 側で Simulator に
  /// マイク使用を許可していないと、エラーにならず無音が流れてくる。
  private var inputPeak: Float = 0

  /// 認識が使えなかった理由。実機での切り分け用に Dart 側へ返す。
  ///
  /// シミュレータには端末内認識のアセットが無いため必ず no_on_device になる。
  /// 実機でも、その端末にタイ語の音声認識アセットが入っていなければ同じ。
  private var recognitionStatus = "not_started"

  // MARK: - 権限

  /// マイクと、使える端末でだけ音声認識の許可を要求する。
  ///
  /// マイクが取れれば true。音声認識が拒否されてもピッチ判定はできるので、
  /// ここでは false にしない。
  ///
  /// 音声認識は端末内実行でしか使わない（[startRecognition]）。その端末に
  /// タイ語の端末内アセットが無ければ、許可を取っても認識は動かないので
  /// 聞かない。許可ダイアログを2つ続けて出す価値がない。
  func requestPermission(localeId: String, completion: @escaping (Bool) -> Void) {
    requestMicrophonePermission { micGranted in
      guard Self.canRecognizeOnDevice(localeId: localeId) else {
        DispatchQueue.main.async { completion(micGranted) }
        return
      }
      SFSpeechRecognizer.requestAuthorization { _ in
        DispatchQueue.main.async { completion(micGranted) }
      }
    }
  }

  /// その言語の端末内認識が使えるか。
  ///
  /// 未許可（notDetermined）でも参照できる値なので、聞く前の判定に使える。
  /// シミュレータと、アセットが入っていない実機では false。
  private static func canRecognizeOnDevice(localeId: String) -> Bool {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))
    else { return false }
    return recognizer.supportsOnDeviceRecognition
  }

  private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
    if #available(iOS 17.0, *) {
      AVAudioApplication.requestRecordPermission { completion($0) }
    } else {
      AVAudioSession.sharedInstance().requestRecordPermission { completion($0) }
    }
  }

  private var hasMicrophonePermission: Bool {
    if #available(iOS 17.0, *) {
      return AVAudioApplication.shared.recordPermission == .granted
    } else {
      return AVAudioSession.sharedInstance().recordPermission == .granted
    }
  }

  func hasPermission() -> Bool {
    return hasMicrophonePermission
  }

  // MARK: - 収録

  func start(localeId: String) throws {
    if capturing { return }

    pcmData = Data()
    transcript = ""
    transcriptAvailable = false
    recognitionStatus = "not_started"
    inputPeak = 0

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    startRecognition(localeId: localeId)

    let input = audioEngine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    guard let targetFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: SpeechCapture.targetSampleRate,
      channels: 1,
      interleaved: true
    ) else {
      throw NSError(domain: "SpeechCapture", code: 1)
    }
    converter = AVAudioConverter(from: inputFormat, to: targetFormat)

    input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
      guard let self = self else { return }
      // 認識器には元のバッファをそのまま渡す（内部で必要な変換を行う）。
      self.request?.append(buffer)
      self.updateInputPeak(buffer)
      self.appendPcm(buffer: buffer, targetFormat: targetFormat)
    }

    audioEngine.prepare()
    try audioEngine.start()
    capturing = true
  }

  /// 収録を止め、PCMと認識結果を返す。
  ///
  /// 認識は音声の投入を止めてから最終結果が届くまでに間があるため、
  /// 少しだけ待ってから返す。届かなければその時点の途中経過を使う。
  func stop(completion: @escaping (Data, String, Bool, String, Float) -> Void) {
    guard capturing else {
      completion(pcmData, transcript, transcriptAvailable, recognitionStatus, inputPeak)
      return
    }
    capturing = false

    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    request?.endAudio()

    let deadline = DispatchTime.now() + .milliseconds(1200)
    DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
      guard let self = self else { return }
      self.task?.cancel()
      self.task = nil
      self.request = nil
      self.converter = nil
      self.releaseSession()
      completion(self.pcmData, self.transcript, self.transcriptAvailable,
                 self.recognitionStatus, self.inputPeak)
    }
  }

  func cancel() {
    guard capturing else { return }
    capturing = false
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    task?.cancel()
    task = nil
    request = nil
    converter = nil
    pcmData = Data()
    releaseSession()
  }

  /// 収録用に握ったオーディオセッションを手放し、再生向けのカテゴリに戻す。
  ///
  /// カテゴリとモードはセッションを非アクティブにしても残る。収録の
  /// playAndRecord + measurement のまま放置すると、その後のTTS発話が
  /// 出力処理を通らず極端に小さくなる。
  private func releaseSession() {
    let session = AVAudioSession.sharedInstance()
    try? session.setActive(false, options: .notifyOthersOnDeactivation)
    try? session.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
  }

  // MARK: - 内部

  private func startRecognition(localeId: String) {
    guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
      recognitionStatus = "auth_denied"
      return
    }
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)) else {
      recognitionStatus = "no_recognizer_for_locale"
      return
    }
    guard recognizer.isAvailable else {
      recognitionStatus = "recognizer_unavailable"
      return
    }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    // 音声を端末外へ出さない。対応していない端末では認識自体を諦める。
    // シミュレータと、タイ語の認識アセットが入っていない実機はここで落ちる。
    guard recognizer.supportsOnDeviceRecognition else {
      recognitionStatus = "no_on_device_asset"
      return
    }
    request.requiresOnDeviceRecognition = true
    recognitionStatus = "ok"

    self.recognizer = recognizer
    self.request = request
    self.transcriptAvailable = true
    self.task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
      guard let self = self, let result = result else { return }
      self.transcript = result.bestTranscription.formattedString
    }
  }

  /// タップに届いた生のバッファの最大振幅を控える。
  private func updateInputPeak(_ buffer: AVAudioPCMBuffer) {
    let frames = Int(buffer.frameLength)
    guard frames > 0 else { return }

    var localMax: Float = 0
    if let channel = buffer.floatChannelData {
      for i in 0..<frames { localMax = max(localMax, abs(channel[0][i])) }
    } else if let channel = buffer.int16ChannelData {
      for i in 0..<frames {
        localMax = max(localMax, abs(Float(channel[0][i])) / 32768.0)
      }
    }
    inputPeak = max(inputPeak, localMax)
  }

  /// タップのバッファを16kHz/mono/Int16 に変換して溜める。
  private func appendPcm(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
    guard let converter = converter else { return }

    let ratio = targetFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
    guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
      return
    }

    var consumed = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
      if consumed {
        status.pointee = .noDataNow
        return nil
      }
      consumed = true
      status.pointee = .haveData
      return buffer
    }
    if error != nil { return }

    guard let channel = output.int16ChannelData else { return }
    let byteCount = Int(output.frameLength) * MemoryLayout<Int16>.size
    pcmData.append(Data(bytes: channel[0], count: byteCount))
  }
}

/// Dart との橋渡し。
final class SpeechCaptureChannel {
  static let channelName = "thai_memo/speech_capture"

  private let capture = SpeechCapture()

  func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: SpeechCaptureChannel.channelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    // 問い合わせと要求を分ける。問い合わせでダイアログまで出すと、
    // 押しっぱなし録音の指がダイアログ表示中に離れ、離した合図が
    // 届かないまま録音が始まって止まらなくなる。
    case "hasPermission":
      result(capture.hasPermission())

    case "requestPermission":
      let permissionArgs = call.arguments as? [String: Any]
      let permissionLocale = permissionArgs?["localeId"] as? String ?? "th-TH"
      capture.requestPermission(localeId: permissionLocale) { result($0) }

    case "start":
      let args = call.arguments as? [String: Any]
      let localeId = args?["localeId"] as? String ?? "th-TH"
      do {
        try capture.start(localeId: localeId)
        result(nil)
      } catch {
        result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
      }

    case "stop":
      capture.stop { pcm, transcript, available, status, inputPeak in
        result([
          "pcm": FlutterStandardTypedData(bytes: pcm),
          "transcript": transcript,
          "transcriptAvailable": available,
          "recognitionStatus": status,
          "inputPeak": Double(inputPeak),
        ])
      }

    case "cancel":
      capture.cancel()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
