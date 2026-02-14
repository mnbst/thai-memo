/// Firebase-related configuration settings
class FirebaseConfig {
  FirebaseConfig._();

  /// Cloud Functions region (Tokyo for low latency)
  static const String functionsRegion = 'asia-northeast1';

  /// Function names
  static const String generateSentenceFunctionName = 'generateThaiSentence';

  /// Timeout for Cloud Functions calls
  static const Duration functionTimeout = Duration(seconds: 45);
}
