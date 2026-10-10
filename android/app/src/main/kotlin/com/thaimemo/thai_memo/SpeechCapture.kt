package com.thaimemo.thai_memo

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import kotlin.math.abs

/**
 * マイクを1本だけ握り、そこから取れた音声をピッチ解析用のPCMと音声認識の両方へ流す。
 * iOS の SpeechCapture.swift と同じ役割・同じ戻り値。
 *
 * マイクを2重に握れないので、AudioRecord で取ったPCMをパイプ経由で
 * SpeechRecognizer に渡す（EXTRA_AUDIO_SOURCE、API 33 以降）。
 * 音声認識は端末内実行だけを使う（iOS と同じく発音の音声を端末外へ出さない）。
 * API 33 未満と、端末内認識にタイ語が入っていない端末では認識だけを諦め、
 * ピッチ判定は続ける。
 */
class SpeechCapture(private val context: Context) {

  companion object {
    /** Dart 側の kRecordSampleRate と一致させること。 */
    const val SAMPLE_RATE = 16000

    const val PERMISSION_REQUEST_CODE = 4711

    /** 音声の投入を止めてから最終結果を待つ上限（iOS と同じ）。 */
    private const val FINAL_RESULT_WAIT_MS = 1200L
  }

  private val main = Handler(Looper.getMainLooper())

  private var audioRecord: AudioRecord? = null
  private var captureThread: Thread? = null
  private val pcm = ByteArrayOutputStream()

  /** 収録中か。セッションごとに別の旗を持ち、止め損ねた古いスレッドが次の収録に混ざらない。 */
  private var running: AtomicBoolean? = null
  private val capturing get() = running?.get() == true
  @Volatile private var inputPeak = 0f

  private var recognizer: SpeechRecognizer? = null
  @Volatile private var recognizerInput: OutputStream? = null

  /**
   * 認識器へ渡したパイプの読み取り側。startListening は Intent を後でメインループから
   * 送るので、送る前に閉じると Bad file descriptor で落ちる。認識器を破棄するまで持つ。
   */
  private var recognizerSource: ParcelFileDescriptor? = null
  private var transcript = ""
  private var transcriptAvailable = false
  private var recognitionStatus = "not_started"
  private var finalResult: (() -> Unit)? = null

  /** 認識器が結果かエラーを出し終えたか。済んでいれば stop で待たない。 */
  private var recognitionDone = false

  // MARK: 権限

  fun hasPermission(): Boolean =
    ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
      PackageManager.PERMISSION_GRANTED

  /** 権限ダイアログを出す。結果は Activity の onRequestPermissionsResult に届く。 */
  fun requestPermission(): Boolean {
    if (hasPermission()) return true
    val activity = context as? Activity ?: return false
    ActivityCompat.requestPermissions(
      activity,
      arrayOf(Manifest.permission.RECORD_AUDIO),
      PERMISSION_REQUEST_CODE
    )
    return false
  }

  // MARK: 収録

  /** メインスレッドから呼ぶ（SpeechRecognizer の制約）。 */
  fun start(localeId: String) {
    if (capturing) return
    // 前回の stop が最終結果を待っている間に始めたら、先に前回分を返し切る。
    // 待ちが残っていると、前回の後片付けが今回の認識器を壊す。
    finalResult?.let { main.removeCallbacks(it); it() }
    synchronized(pcm) { pcm.reset() }
    inputPeak = 0f
    transcript = ""
    transcriptAvailable = false
    recognitionStatus = "not_started"
    recognitionDone = false

    val minBuffer = AudioRecord.getMinBufferSize(
      SAMPLE_RATE,
      AudioFormat.CHANNEL_IN_MONO,
      AudioFormat.ENCODING_PCM_16BIT
    )
    val bufferSize = if (minBuffer > 0) minBuffer * 2 else SAMPLE_RATE * 2

    val record = AudioRecord(
      MediaRecorder.AudioSource.VOICE_RECOGNITION,
      SAMPLE_RATE,
      AudioFormat.CHANNEL_IN_MONO,
      AudioFormat.ENCODING_PCM_16BIT,
      bufferSize
    )
    if (record.state != AudioRecord.STATE_INITIALIZED) {
      record.release()
      throw IllegalStateException("AudioRecord could not be initialized")
    }

    startRecognition(localeId)

    audioRecord = record
    record.startRecording()
    val session = AtomicBoolean(true)
    running = session

    captureThread = thread(name = "speech-capture") {
      val buffer = ByteArray(bufferSize)
      while (session.get()) {
        val read = record.read(buffer, 0, buffer.size)
        if (read <= 0) continue
        synchronized(pcm) { pcm.write(buffer, 0, read) }
        updateInputPeak(buffer, read)
        feedRecognizer(buffer, read)
      }
    }
  }

  /** 収録を止め、認識の最終結果を少し待ってから [completion] を呼ぶ（メインスレッド）。 */
  fun stop(completion: (ByteArray, String, Boolean, String, Float) -> Unit) {
    val deliver = {
      completion(snapshot(), transcript, transcriptAvailable, recognitionStatus, inputPeak)
    }
    if (!capturing) {
      deliver()
      return
    }
    stopRecording()

    if (recognizer == null || recognitionDone) {
      destroyRecognizer()
      deliver()
      return
    }
    var delivered = false
    val finish = finish@{
      if (delivered) return@finish
      delivered = true
      finalResult = null
      destroyRecognizer()
      deliver()
    }
    finalResult = finish
    main.postDelayed(finish, FINAL_RESULT_WAIT_MS)
  }

  fun cancel() {
    stopRecording()
    finalResult?.let { main.removeCallbacks(it) }
    finalResult = null
    destroyRecognizer()
    synchronized(pcm) { pcm.reset() }
  }

  // MARK: 内部

  /**
   * 収録を止める。メインスレッドを待たせないよう、読み取りを先に解いてから待つ。
   *
   * パイプを閉じて書き込みの詰まりを解き、AudioRecord.stop() で read() を
   * 返させてから、短くスレッドの終了を待つ。待ちきれなくても旗はセッションごと
   * なので、古いスレッドは次の read() のあとで抜ける。
   */
  private fun stopRecording() {
    running?.set(false)
    running = null
    closeRecognizerInput()
    val record = audioRecord
    audioRecord = null
    try {
      record?.stop()
    } catch (_: IllegalStateException) {
      // 既に停止している場合は無視する。
    }
    captureThread?.join(200)
    captureThread = null
    record?.release()
  }

  private fun startRecognition(localeId: String) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      // 収録済み音声を認識器へ渡す手段（EXTRA_AUDIO_SOURCE）が無い。
      recognitionStatus = "android_unsupported"
      return
    }
    if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
      recognitionStatus = "no_on_device_asset"
      return
    }

    val pipe = ParcelFileDescriptor.createPipe()
    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
      putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
      putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeId)
      putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
      putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, pipe[0])
      putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
      putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
      putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, SAMPLE_RATE)
    }

    val sr = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
    sr.setRecognitionListener(object : RecognitionListener {
      override fun onPartialResults(partialResults: Bundle?) = take(partialResults)

      override fun onResults(results: Bundle?) {
        take(results)
        recognitionDone = true
        finalResult?.let { main.removeCallbacks(it); it() }
      }

      override fun onError(error: Int) {
        when (error) {
          // 何も聞き取れなかった。判定はできており「通じなかった」が正しい。
          SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> Unit
          // その端末の端末内認識にタイ語が無い。
          SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
          SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> {
            transcriptAvailable = false
            recognitionStatus = "no_on_device_asset"
          }
          else -> {
            transcriptAvailable = false
            recognitionStatus = "recognizer_unavailable"
          }
        }
        recognitionDone = true
        finalResult?.let { main.removeCallbacks(it); it() }
      }

      override fun onReadyForSpeech(params: Bundle?) = Unit
      override fun onBeginningOfSpeech() = Unit
      override fun onRmsChanged(rmsdB: Float) = Unit
      override fun onBufferReceived(buffer: ByteArray?) = Unit
      override fun onEndOfSpeech() = Unit
      override fun onEvent(eventType: Int, params: Bundle?) = Unit
    })
    sr.startListening(intent)

    recognizer = sr
    recognizerSource = pipe[0]
    recognizerInput = ParcelFileDescriptor.AutoCloseOutputStream(pipe[1])
    transcriptAvailable = true
    recognitionStatus = "ok"
  }

  private fun take(results: Bundle?) {
    val best = results
      ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
      ?.firstOrNull()
    if (!best.isNullOrEmpty()) transcript = best
  }

  private fun feedRecognizer(buffer: ByteArray, length: Int) {
    val input = recognizerInput ?: return
    try {
      input.write(buffer, 0, length)
    } catch (_: IOException) {
      // 認識器が先に終了した。PCM の収録は続ける。
      recognizerInput = null
    }
  }

  /** パイプを閉じると認識器は音声の終わりとして最終結果を出す。 */
  private fun closeRecognizerInput() {
    val input = recognizerInput ?: return
    recognizerInput = null
    try {
      input.close()
    } catch (_: IOException) {
    }
  }

  private fun destroyRecognizer() {
    recognizer?.destroy()
    recognizer = null
    try {
      recognizerSource?.close()
    } catch (_: IOException) {
    }
    recognizerSource = null
  }

  private fun updateInputPeak(buffer: ByteArray, length: Int) {
    var localMax = 0
    var i = 0
    while (i + 1 < length) {
      val sample = (buffer[i].toInt() and 0xFF) or (buffer[i + 1].toInt() shl 8)
      localMax = maxOf(localMax, abs(sample.toShort().toInt()))
      i += 2
    }
    inputPeak = maxOf(inputPeak, localMax / 32768f)
  }

  private fun snapshot(): ByteArray = synchronized(pcm) { pcm.toByteArray() }
}

/** Dart との橋渡し。 */
class SpeechCaptureChannel(context: Context) : MethodChannel.MethodCallHandler {

  companion object {
    const val CHANNEL_NAME = "thai_memo/speech_capture"
  }

  private val capture = SpeechCapture(context)

  /** 権限ダイアログの答えを待っている呼び出し。iOS と同じく許可の結果を返す。 */
  private var pendingPermission: MethodChannel.Result? = null

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "hasPermission" -> result.success(capture.hasPermission())

      "requestPermission" -> {
        if (capture.requestPermission()) {
          result.success(true)
        } else {
          pendingPermission?.success(false)
          pendingPermission = result
        }
      }

      "start" -> try {
        capture.start(call.argument<String>("localeId") ?: "th-TH")
        result.success(null)
      } catch (e: Exception) {
        result.error("start_failed", e.message, null)
      }

      "stop" -> capture.stop { pcm, transcript, available, status, inputPeak ->
        result.success(
          mapOf(
            "pcm" to pcm,
            "transcript" to transcript,
            "transcriptAvailable" to available,
            "recognitionStatus" to status,
            "inputPeak" to inputPeak.toDouble()
          )
        )
      }

      "cancel" -> {
        capture.cancel()
        result.success(null)
      }

      else -> result.notImplemented()
    }
  }

  /** MainActivity から転送される。 */
  fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
    if (requestCode != SpeechCapture.PERMISSION_REQUEST_CODE) return
    val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
    pendingPermission?.success(granted)
    pendingPermission = null
  }
}
