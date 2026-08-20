package com.thaimemo.thai_memo

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.concurrent.thread

/**
 * マイクからピッチ解析用のPCMを取る。
 *
 * **Android は音声認識に対応していない**（transcriptAvailable = false を返す）。
 * SpeechRecognizer へ収録済みの音声を渡す EXTRA_AUDIO_SOURCE は API 33 以降でしか
 * 使えず、マイクを2重に握ることもできないため。Android は未リリースなので、
 * ここでは声調判定に必要なPCM取得だけを実装している。
 *
 * 発音（子音・母音）の判定を Android にも入れる場合は、API 33 以降で
 * ParcelFileDescriptor のパイプを SpeechRecognizer に渡す実装を足すことになる。
 */
class SpeechCapture(private val context: Context) {

  companion object {
    /** Dart 側の kRecordSampleRate と一致させること。 */
    const val SAMPLE_RATE = 16000

    private const val PERMISSION_REQUEST_CODE = 4711
  }

  private var audioRecord: AudioRecord? = null
  private var captureThread: Thread? = null
  private val pcm = ByteArrayOutputStream()

  @Volatile private var capturing = false

  fun hasPermission(): Boolean =
    ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
      PackageManager.PERMISSION_GRANTED

  /**
   * 権限を要求する。要求結果は待たず、現在の状態を返す。
   *
   * 初回は false を返してダイアログだけが出る。ユーザーが許可したあと、
   * 次に録音ボタンを押した時点で true になる。
   */
  fun requestPermission(): Boolean {
    if (hasPermission()) return true
    (context as? Activity)?.let {
      ActivityCompat.requestPermissions(
        it,
        arrayOf(Manifest.permission.RECORD_AUDIO),
        PERMISSION_REQUEST_CODE
      )
    }
    return false
  }

  fun start() {
    if (capturing) return
    synchronized(pcm) { pcm.reset() }

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

    audioRecord = record
    record.startRecording()
    capturing = true

    captureThread = thread(name = "speech-capture") {
      val buffer = ByteArray(bufferSize)
      while (capturing) {
        val read = record.read(buffer, 0, buffer.size)
        if (read <= 0) continue
        synchronized(pcm) { pcm.write(buffer, 0, read) }
      }
    }
  }

  fun stop(): ByteArray {
    if (!capturing) return snapshot()
    capturing = false

    captureThread?.join(500)
    captureThread = null
    releaseRecord()
    return snapshot()
  }

  fun cancel() {
    capturing = false
    captureThread?.join(500)
    captureThread = null
    releaseRecord()
    synchronized(pcm) { pcm.reset() }
  }

  private fun releaseRecord() {
    audioRecord?.let {
      try {
        it.stop()
      } catch (_: IllegalStateException) {
        // 既に停止している場合は無視する。
      }
      it.release()
    }
    audioRecord = null
  }

  private fun snapshot(): ByteArray = synchronized(pcm) { pcm.toByteArray() }
}

/** Dart との橋渡し。 */
class SpeechCaptureChannel(context: Context) : MethodChannel.MethodCallHandler {

  companion object {
    const val CHANNEL_NAME = "thai_memo/speech_capture"
  }

  private val capture = SpeechCapture(context)

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "hasPermission" -> result.success(capture.hasPermission())

      "requestPermission" -> result.success(capture.requestPermission())

      "start" -> try {
        capture.start()
        result.success(null)
      } catch (e: Exception) {
        result.error("start_failed", e.message, null)
      }

      "stop" -> result.success(
        mapOf(
          "pcm" to capture.stop(),
          "transcript" to "",
          // Android は音声認識に未対応。判定できないことを Dart 側へ伝える。
          "transcriptAvailable" to false,
          "recognitionStatus" to "android_unsupported",
          "inputPeak" to 0.0
        )
      )

      "cancel" -> {
        capture.cancel()
        result.success(null)
      }

      else -> result.notImplemented()
    }
  }
}
