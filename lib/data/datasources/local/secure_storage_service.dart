import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/config/app_config.dart';

/// Service for securely storing sensitive data like API keys
class SecureStorageService {
  SecureStorageService._privateConstructor();
  static final SecureStorageService instance =
      SecureStorageService._privateConstructor();

  /// Flutter secure storage instance
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // ==================== Last Generation Timestamp ====================

  /// Save the timestamp of the last sentence generation
  Future<void> saveLastGenerationTimestamp(DateTime timestamp) async {
    try {
      await _storage.write(
        key: AppConfig.secureStorageLastGeneration,
        value: timestamp.millisecondsSinceEpoch.toString(),
      );
    } catch (e) {
      throw SecureStorageException('Failed to save last generation timestamp: $e');
    }
  }

  /// Get the timestamp of the last sentence generation
  Future<DateTime?> getLastGenerationTimestamp() async {
    try {
      final timestampString =
          await _storage.read(key: AppConfig.secureStorageLastGeneration);
      if (timestampString == null) return null;

      final milliseconds = int.tryParse(timestampString);
      if (milliseconds == null) return null;

      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    } catch (e) {
      throw SecureStorageException(
          'Failed to read last generation timestamp: $e');
    }
  }

  /// Check if a new generation is due (based on configured frequency)
  Future<bool> isGenerationDue() async {
    try {
      final lastGeneration = await getLastGenerationTimestamp();
      if (lastGeneration == null) return true;

      final now = DateTime.now();
      final difference = now.difference(lastGeneration);

      return difference >= AppConfig.backgroundTaskFrequency;
    } catch (e) {
      // If there's an error, assume generation is due
      return true;
    }
  }

}

/// Custom exception for secure storage operations
class SecureStorageException implements Exception {
  final String message;

  SecureStorageException(this.message);

  @override
  String toString() => 'SecureStorageException: $message';
}
