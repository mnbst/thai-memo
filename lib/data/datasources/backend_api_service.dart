// =============================================================================
// backend_api_service.dart
// バックエンドAPI通信サービス。
// Firebase Cloud Functionsと通信し、以下の機能を提供する:
//   - generateThaiSentence: Gemini AIによるタイ語例文生成
//   - generateQuiz: Geminiによる穴埋めクイズ生成
//   - review_queue: Firestoreから復習対象の問題数を取得
//
// データフロー（例文生成）:
//   1. Cloud Function呼び出し（Firebase Auth認証付き）
//   2. レスポンスJSONをパース
//   3. 音節データをThaiToneAnalyzerで声調分析
//   4. ThaiSentence + WordBreakdown + Syllableモデルに変換
//
// エラーハンドリング:
//   Firebase Functions例外を独自例外クラスにマッピングし、
//   UI層でユーザーフレンドリーなメッセージを表示できるようにする。
// =============================================================================

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/firebase_config.dart';
import '../models/quiz_question.dart';
import '../models/vocab_test_step.dart';
import '../models/syllable.dart';
import '../models/thai_sentence.dart';
import '../models/word_breakdown.dart';

/// Firebase Cloud Functionsと通信するサービスクラス
///
/// リージョン: asia-northeast1 (東京)
/// 認証: Firebase Authのログインユーザーが必要
class BackendApiService {
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  /// リクエストに載せる言語コード。値ではなく供給関数で持つのは、
  /// 設定画面での言語切替を次のリクエストから即座に反映させるため。
  /// 既定は 'ja'（言語を供給しない呼び出し元＝現行の挙動を変えない）。
  final String Function() _lang;

  BackendApiService({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    String Function()? lang,
  })  : _functions = functions ??
            FirebaseFunctions.instanceFor(
              region: FirebaseConfig.functionsRegion,
            ),
        _auth = auth ?? FirebaseAuth.instance,
        _lang = lang ?? _defaultLang;

  static String _defaultLang() => 'ja';

  /// Generate a new Thai sentence using backend API
  Future<ThaiSentence> generateSentence({
    Map<String, String?> generationParams = const {},
  }) async {
    try {
      // Ensure user is authenticated
      final user = _auth.currentUser;
      if (user == null) {
        throw BackendApiException('User not authenticated');
      }
      // 削除済みユーザー検知: トークンを強制更新し、失効/削除済みなら SDK が
      // 自動サインアウト → アプリ側で匿名再サインインが走るようにする。
      await user.getIdToken(true);

      // Call Cloud Function
      final callable = _functions.httpsCallable(
        FirebaseConfig.generateSentenceFunctionName,
        options: HttpsCallableOptions(
          timeout: FirebaseConfig.functionTimeout,
        ),
      );

      final params = <String, dynamic>{'lang': _lang()};
      for (final entry in generationParams.entries) {
        if (entry.value != null) {
          params[entry.key] = entry.value;
        }
      }

      final result = await callable.call(params);

      // Parse response
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] != true) {
        final error = data['error'] != null
            ? Map<String, dynamic>.from(data['error'] as Map)
            : null;
        final errorCode = error?['code'] as String? ?? 'UNKNOWN';
        final errorMessage = error?['message'] as String? ?? 'Unknown error';

        throw _mapBackendError(errorCode, errorMessage);
      }

      // Extract sentence data
      final sentenceData = Map<String, dynamic>.from(data['data'] as Map);

      return createThaiSentenceFromJson(sentenceData);
    } on FirebaseFunctionsException catch (e) {
      throw _mapFirebaseFunctionsException(e);
    } on BackendApiException {
      rethrow;
    } catch (e) {
      throw BackendApiException('Failed to generate sentence: $e');
    }
  }

  /// Create ThaiSentence object from parsed JSON
  static ThaiSentence createThaiSentenceFromJson(Map<String, dynamic> json) {
    try {
      // Parse word breakdowns
      final wordBreakdownsJson = json['word_breakdown'] as List<dynamic>?;
      final wordBreakdowns = <WordBreakdown>[];

      if (wordBreakdownsJson != null) {
        for (var i = 0; i < wordBreakdownsJson.length; i++) {
          final wordJson =
              Map<String, dynamic>.from(wordBreakdownsJson[i] as Map);

          // Parse syllables if present (string array from API)
          final syllables =
              parseSyllables(wordJson['syllables'] as List<dynamic>?);

          wordBreakdowns.add(
            WordBreakdown(
              wordText: wordJson['word'] as String? ?? '',
              pronunciation: wordJson['pronunciation'] as String? ?? '',
              meaning: wordJson['meaning'] as String? ?? '',
              grammaticalRole: wordJson['grammatical_role'] as String?,
              wordOrder: i,
              syllables: syllables,
              notes: wordJson['notes'] as String?,
            ),
          );
        }
      }

      // Parse context
      final contextJson = json['context'] != null
          ? Map<String, dynamic>.from(json['context'] as Map)
          : null;
      final context = contextJson != null
          ? SentenceContext(
              topic: contextJson['topic'] as String?,
              style: contextJson['style'] as String?,
              emotion: contextJson['emotion'] as String?,
              usageScenarios: contextJson['usage_scenarios'] as String?,
              culturalNotes: contextJson['cultural_notes'] as String?,
            )
          : null;

      // Parse target words
      final targetWordsJson = json['target_words'] as List<dynamic>?;
      final targetWords = targetWordsJson?.map((e) => e as String).toList();

      // Create ThaiSentence
      final sentence = ThaiSentence(
        thaiText: json['thai_text'] as String? ?? '',
        pronunciation: json['pronunciation'] as String? ?? '',
        japaneseTranslation: json['japanese_translation'] as String? ?? '',
        wordBreakdowns: wordBreakdowns,
        context: context,
        createdAt: DateTime.now(),
        generationTier: json['generation_tier'] as String?,
        targetWords: targetWords,
      );

      return sentence;
    } catch (e) {
      throw BackendApiInvalidResponseException(
          'Failed to create ThaiSentence: $e');
    }
  }

  /// Map Firebase Functions exceptions to custom exceptions
  BackendApiException _mapFirebaseFunctionsException(
      FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return BackendApiUnauthenticatedException(
            'Authentication required. Please restart the app.');
      case 'permission-denied':
        return BackendApiPermissionDeniedException(
            'Permission denied. Please check your account.');
      case 'deadline-exceeded':
        return BackendApiTimeoutException('Request timeout. Please try again.');
      case 'unavailable':
        return BackendApiServerException('Service temporarily unavailable.');
      case 'resource-exhausted':
        return BackendApiRateLimitException(e.message ?? '本日の生成上限に達しました。');
      default:
        return BackendApiException('${e.code}: ${e.message}');
    }
  }

  /// Map backend error codes to custom exceptions
  BackendApiException _mapBackendError(String code, String message) {
    switch (code) {
      case 'UNAUTHENTICATED':
        return BackendApiUnauthenticatedException(message);
      case 'API_ERROR':
        return BackendApiServerException(message);
      case 'INTERNAL':
        return BackendApiServerException(message);
      case 'QUOTA_EXCEEDED':
        return BackendApiQuotaExceededException(message);
      default:
        return BackendApiException(message);
    }
  }

  /// クイズをオンデマンド生成（generateQuiz Cloud Function呼び出し）
  Future<List<QuizQuestion>> generateQuiz() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw BackendApiUnauthenticatedException('User not authenticated');
      }
      // 削除済みユーザー検知（generateSentence と同様）
      await user.getIdToken(true);

      final callable = _functions.httpsCallable(
        FirebaseConfig.generateQuizFunctionName,
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 60),
        ),
      );

      final result = await callable.call({'lang': _lang()});
      final data = _deepCast(result.data) as Map<String, dynamic>;

      if (data['no_user_sentences'] == true) {
        throw BackendApiNoUserSentencesException();
      }

      final questionsList = data['questions'] as List<dynamic>? ?? [];

      return questionsList
          .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
          .toList();
    } on FirebaseFunctionsException catch (e) {
      throw _mapFirebaseFunctionsException(e);
    } on BackendApiException {
      rethrow;
    } catch (e) {
      throw BackendApiException('Failed to generate quiz: $e');
    }
  }

  /// 学習中の例文から1問だけクイズを生成
  Future<List<QuizQuestion>> generateLearningQuiz(ThaiSentence sentence) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw BackendApiUnauthenticatedException('User not authenticated');
      }
      await user.getIdToken(true);

      final sentenceId = sentence.id;
      final targetWords = sentence.targetWords ?? const <String>[];
      final keyWord = targetWords.isNotEmpty
          ? targetWords.first
          : sentence.wordBreakdowns.isNotEmpty
              ? sentence.wordBreakdowns.first.wordText
              : null;
      if (sentenceId == null || sentenceId.isEmpty || keyWord == null) {
        throw BackendApiException('クイズに使える例文データがありません。');
      }

      final callable = _functions.httpsCallable(
        FirebaseConfig.generateLearningQuizFunctionName,
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 60),
        ),
      );

      final result = await callable.call({
        'lang': _lang(),
        'sentence': {
          'sentence_id': sentenceId,
          'thai_text': sentence.thaiText,
          'pronunciation': sentence.pronunciation,
          'japanese_translation': sentence.japaneseTranslation,
          'key_word': keyWord,
          'key_word_pronunciation': _findWordPronunciation(sentence, keyWord),
          'key_word_meaning': _findWordMeaning(sentence, keyWord),
          'word_breakdown': sentence.wordBreakdowns
              .map((word) => {
                    'word': word.wordText,
                    'pronunciation': word.pronunciation,
                    'meaning': word.meaning,
                    if (word.grammaticalRole != null)
                      'grammatical_role': word.grammaticalRole,
                  })
              .toList(),
          if (sentence.generationTier != null)
            'generation_tier': sentence.generationTier,
        },
      });
      final data = _deepCast(result.data) as Map<String, dynamic>;
      final questionsList = data['questions'] as List<dynamic>? ?? [];

      return questionsList
          .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
          .toList();
    } on FirebaseFunctionsException catch (e) {
      throw _mapFirebaseFunctionsException(e);
    } on BackendApiException {
      rethrow;
    } catch (e) {
      throw BackendApiException('Failed to generate learning quiz: $e');
    }
  }

  String _findWordPronunciation(ThaiSentence sentence, String word) {
    for (final breakdown in sentence.wordBreakdowns) {
      if (breakdown.wordText.trim() == word.trim()) {
        return breakdown.pronunciation;
      }
    }
    return '';
  }

  String _findWordMeaning(ThaiSentence sentence, String word) {
    for (final breakdown in sentence.wordBreakdowns) {
      if (breakdown.wordText.trim() == word.trim()) {
        return breakdown.meaning;
      }
    }
    return '';
  }

  /// クイズ結果からUVMを更新
  Future<void> updateUvm({
    required List<Map<String, dynamic>> results,
    String? quizType,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final callable = _functions.httpsCallable(
        FirebaseConfig.updateUvmFunctionName,
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 30),
        ),
      );

      final payload = <String, dynamic>{'results': results};
      if (quizType != null) payload['quiz_type'] = quizType;
      await callable.call(payload);
    } catch (e) {
      // fire-and-forget: UVM更新失敗はログのみ
      debugPrint('Failed to update UVM: $e');
    }
  }

  Future<void> resetLearningData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw BackendApiUnauthenticatedException('User not authenticated');
      }

      final callable = _functions.httpsCallable(
        FirebaseConfig.resetLearningDataFunctionName,
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 60),
        ),
      );

      await callable.call();
    } on FirebaseFunctionsException catch (e) {
      throw _mapFirebaseFunctionsException(e);
    } on BackendApiException {
      rethrow;
    } catch (e) {
      throw BackendApiException('学習データのリセットに失敗しました: $e');
    }
  }

  /// 語彙テストを開始し、最初の1段を受け取る。
  ///
  /// [level] はヒアリングの level 回答。開始段が決まるだけで結果には効かない。
  /// プレミアム限定・1日の回数上限があるので、断られたときは
  /// [VocabTestUnavailableException] にサーバーの文言が入る。
  Future<VocabTestStep> startVocabTest() =>
      _vocabTestCall(FirebaseConfig.startVocabTestFunctionName, {
        'lang': _lang(),
      });

  /// 1段ぶんの回答を送り、次の段か最終結果を受け取る。
  /// [answers] は出題順の選択肢 index。未回答は -1。
  ///
  /// [stage] はこの回答がどの段のものか。サーバーが自分の段と照合して、
  /// 採点済みの段への二重送信を弾く（弾いた場合はいま出すべき段が返る）。
  Future<VocabTestStep> submitVocabTest(List<int> answers, {int? stage}) =>
      _vocabTestCall(FirebaseConfig.submitVocabTestFunctionName, {
        'answers': answers,
        if (stage != null) 'stage': stage,
      });

  Future<VocabTestStep> _vocabTestCall(
      String name, Map<String, dynamic> params) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw BackendApiUnauthenticatedException('User not authenticated');
      }

      final callable = _functions.httpsCallable(
        name,
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final result = await callable.call(params);
      return VocabTestStep.fromJson(
          _deepCast(result.data) as Map<String, dynamic>);
    } on FirebaseFunctionsException catch (e) {
      // プレミアム限定・回数上限・セッション切れは、理由をそのまま出したい
      // ので分ける。
      if (e.code == 'permission-denied' ||
          e.code == 'failed-precondition' ||
          e.code == 'resource-exhausted') {
        throw VocabTestUnavailableException(e.message ?? '');
      }
      throw _mapFirebaseFunctionsException(e);
    } on BackendApiException {
      rethrow;
    } catch (e) {
      throw BackendApiException('語彙テストに失敗しました: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    // Nothing to dispose for Cloud Functions
  }
}

// ==================== Custom Exceptions ====================

/// Base exception for backend API errors
class BackendApiException implements Exception {
  final String message;
  final Object? originalError;

  BackendApiException(this.message, {this.originalError});

  @override
  String toString() =>
      'BackendApiException: $message${originalError != null ? ' (Original: $originalError)' : ''}';
}

/// Exception for unauthenticated requests
class BackendApiUnauthenticatedException extends BackendApiException {
  BackendApiUnauthenticatedException(super.message);

  @override
  String toString() => 'BackendApiUnauthenticatedException: $message';
}

/// Exception for permission denied
class BackendApiPermissionDeniedException extends BackendApiException {
  BackendApiPermissionDeniedException(super.message);

  @override
  String toString() => 'BackendApiPermissionDeniedException: $message';
}

/// Exception for rate limit exceeded
class BackendApiRateLimitException extends BackendApiException {
  BackendApiRateLimitException(super.message);

  @override
  String toString() => 'BackendApiRateLimitException: $message';
}

/// Exception for server errors
class BackendApiServerException extends BackendApiException {
  BackendApiServerException(super.message);

  @override
  String toString() => 'BackendApiServerException: $message';
}

/// Exception for invalid response format
class BackendApiInvalidResponseException extends BackendApiException {
  BackendApiInvalidResponseException(super.message);

  @override
  String toString() => 'BackendApiInvalidResponseException: $message';
}

/// Exception for request timeout
class BackendApiTimeoutException extends BackendApiException {
  BackendApiTimeoutException(super.message);

  @override
  String toString() => 'BackendApiTimeoutException: $message';
}

/// Exception for quota exceeded (freemium limit reached)
class BackendApiQuotaExceededException extends BackendApiException {
  BackendApiQuotaExceededException(super.message);

  @override
  String toString() => 'BackendApiQuotaExceededException: $message';
}

class BackendApiNoUserSentencesException extends BackendApiException {
  BackendApiNoUserSentencesException() : super('No user sentences');

  @override
  String toString() => 'BackendApiNoUserSentencesException';
}

dynamic _deepCast(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.fromEntries(
      value.entries.map((e) => MapEntry(e.key.toString(), _deepCast(e.value))),
    );
  }
  if (value is List) {
    return value.map(_deepCast).toList();
  }
  return value;
}

/// 語彙テストを受けられない（プレミアム限定 / 本日の回数上限）。
/// [message] はサーバーが返した理由。そのまま画面に出す。
class VocabTestUnavailableException extends BackendApiException {
  VocabTestUnavailableException(super.message);
}
