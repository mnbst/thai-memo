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

  // ==================== API Key Management ====================

  /// Save Gemini API key securely
  Future<void> saveApiKey(String apiKey) async {
    try {
      await _storage.write(
        key: AppConfig.secureStorageApiKey,
        value: apiKey,
      );
    } catch (e) {
      throw SecureStorageException('Failed to save API key: $e');
    }
  }

  /// Get Gemini API key
  Future<String?> getApiKey() async {
    try {
      return await _storage.read(key: AppConfig.secureStorageApiKey);
    } catch (e) {
      throw SecureStorageException('Failed to read API key: $e');
    }
  }

  /// Check if API key exists
  Future<bool> hasApiKey() async {
    try {
      final apiKey = await getApiKey();
      return apiKey != null && apiKey.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Delete API key
  Future<void> deleteApiKey() async {
    try {
      await _storage.delete(key: AppConfig.secureStorageApiKey);
    } catch (e) {
      throw SecureStorageException('Failed to delete API key: $e');
    }
  }

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

  // ==================== General Storage Operations ====================

  /// Write a value to secure storage
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      throw SecureStorageException('Failed to write to secure storage: $e');
    }
  }

  /// Read a value from secure storage
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      throw SecureStorageException('Failed to read from secure storage: $e');
    }
  }

  /// Delete a value from secure storage
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      throw SecureStorageException('Failed to delete from secure storage: $e');
    }
  }

  /// Check if a key exists in secure storage
  Future<bool> containsKey(String key) async {
    try {
      return await _storage.containsKey(key: key);
    } catch (e) {
      return false;
    }
  }

  /// Get all keys stored in secure storage
  Future<Map<String, String>> readAll() async {
    try {
      return await _storage.readAll();
    } catch (e) {
      throw SecureStorageException('Failed to read all from secure storage: $e');
    }
  }

  /// Delete all data from secure storage
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      throw SecureStorageException('Failed to delete all from secure storage: $e');
    }
  }

  // ==================== Validation ====================

  /// Validate API key format (basic validation)
  bool isValidApiKeyFormat(String apiKey) {
    // Gemini API keys typically start with "AI" and are at least 20 characters
    return apiKey.startsWith('AI') && apiKey.length >= 20;
  }
}

/// Custom exception for secure storage operations
class SecureStorageException implements Exception {
  final String message;

  SecureStorageException(this.message);

  @override
  String toString() => 'SecureStorageException: $message';
}
