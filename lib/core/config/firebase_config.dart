/// Firebase-related configuration settings
class FirebaseConfig {
  FirebaseConfig._();

  /// Cloud Functions region (Tokyo for low latency)
  static const String functionsRegion = 'asia-northeast1';

  /// Function names
  static const String generateSentenceFunctionName = 'generateThaiSentence';
  static const String generateQuizFunctionName = 'generateQuiz';
  static const String verifySubscriptionFunctionName = 'verifySubscription';
  static const String subscriptionStatusFunctionName = 'subscriptionStatus';
  static const String updateUvmFunctionName = 'updateUvm';

  /// Timeout for Cloud Functions calls
  static const Duration functionTimeout = Duration(seconds: 45);

  // AdMob test IDs
  static const String admobBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';
}
