import Flutter
import StoreKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var reviewPromptChannel: FlutterMethodChannel?
  private let speechCaptureChannel = SpeechCaptureChannel()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerReviewPromptChannel(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ThaiMemoSpeechCapture") {
      speechCaptureChannel.register(with: registrar)
    }
  }

  private func registerReviewPromptChannel(with registry: FlutterPluginRegistry) {
    if reviewPromptChannel != nil {
      return
    }

    guard let registrar = registry.registrar(forPlugin: "ThaiMemoReviewPrompt") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "thai_memo/review_prompt",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "requestReview":
        guard let self = self else {
          result(false)
          return
        }
        self.requestReview(result: result)
      case "getAppVersion":
        result(self?.currentAppVersion() ?? "")
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    reviewPromptChannel = channel
  }

  private func requestReview(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      if #available(iOS 14.0, *) {
        guard let scene = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .first(where: { $0.activationState == .foregroundActive }) else {
          result(false)
          return
        }

        SKStoreReviewController.requestReview(in: scene)
      } else {
        SKStoreReviewController.requestReview()
      }
      result(true)
    }
  }

  private func currentAppVersion() -> String {
    let info = Bundle.main.infoDictionary
    let shortVersion = info?["CFBundleShortVersionString"] as? String ?? ""
    let buildNumber = info?["CFBundleVersion"] as? String ?? ""

    if shortVersion.isEmpty {
      return buildNumber
    }
    if buildNumber.isEmpty {
      return shortVersion
    }
    return "\(shortVersion)+\(buildNumber)"
  }
}
