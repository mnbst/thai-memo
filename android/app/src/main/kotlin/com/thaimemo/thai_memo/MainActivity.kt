package com.thaimemo.thai_memo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private lateinit var speechCapture: SpeechCaptureChannel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        speechCapture = SpeechCaptureChannel(this)
        MethodChannel(messenger, SpeechCaptureChannel.CHANNEL_NAME)
            .setMethodCallHandler(speechCapture)
        MethodChannel(messenger, ReviewPromptChannel.CHANNEL_NAME)
            .setMethodCallHandler(ReviewPromptChannel(this))
        MethodChannel(messenger, "thai_memo/tts_settings").setMethodCallHandler { call, result ->
            if (call.method == "openVoiceInstaller") {
                openVoiceInstaller()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    /** 読み上げエンジンの音声データのダウンロード画面。無ければ読み上げの設定画面。 */
    private fun openVoiceInstaller() {
        try {
            startActivity(Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA))
        } catch (_: ActivityNotFoundException) {
            try {
                startActivity(Intent("com.android.settings.TTS_SETTINGS"))
            } catch (_: ActivityNotFoundException) {
                // 開ける画面が無い端末。案内文だけで終える。
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        speechCapture.onRequestPermissionsResult(requestCode, grantResults)
    }

    /**
     * FCM の既定チャンネル（AndroidManifest の default_notification_channel_id）。
     *
     * 未作成のまま届くと FCM が「その他」チャンネルへ入れてしまい、設定画面で
     * 何の通知か分からなくなる。作成は何度呼んでも名前の更新だけで済む。
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            getString(R.string.notification_channel_id),
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = getString(R.string.notification_channel_description)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
