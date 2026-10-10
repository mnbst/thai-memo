package com.thaimemo.thai_memo

import android.app.Activity
import android.os.Build
import com.google.android.play.core.review.ReviewManagerFactory
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * レビュー依頼（Play In-App Review）。iOS の AppDelegate と同じチャンネル・メソッドを持つ。
 *
 * Play は表示回数を内部で制限しており、ダイアログが実際に出たかはアプリから
 * 分からない。依頼フローが最後まで進めば true を返す（iOS と同じく
 * 「依頼した」扱いにして、Dart 側のクールダウンを効かせる）。
 */
class ReviewPromptChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

  companion object {
    const val CHANNEL_NAME = "thai_memo/review_prompt"
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "requestReview" -> requestReview(result)
      "getAppVersion" -> result.success(appVersion())
      else -> result.notImplemented()
    }
  }

  private fun requestReview(result: MethodChannel.Result) {
    val manager = ReviewManagerFactory.create(activity)
    manager.requestReviewFlow().addOnCompleteListener { request ->
      if (!request.isSuccessful) {
        result.success(false)
        return@addOnCompleteListener
      }
      manager.launchReviewFlow(activity, request.result)
        .addOnCompleteListener { result.success(true) }
    }
  }

  private fun appVersion(): String {
    val pm = activity.packageManager
    val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      pm.getPackageInfo(activity.packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
    } else {
      @Suppress("DEPRECATION")
      pm.getPackageInfo(activity.packageName, 0)
    }
    return info.versionName ?: ""
  }
}
