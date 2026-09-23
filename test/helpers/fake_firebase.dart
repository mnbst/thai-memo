/// テスト用のFirebase系フェイク実装
///
/// Firebase.initializeApp なしでユニットテストを実行するため、
/// 使用するメンバーのみを最小実装している。
library;

// テスト用フェイクとして意図的にFirestoreのsealedクラスを実装する
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:thai_memo/services/analytics_service.dart';
import 'package:thai_memo/services/purchase_service.dart';

// ==================== FirebaseAuth ====================

class FakeUser extends Fake implements User {
  FakeUser({required this.uid, required this.isAnonymous});

  @override
  final String uid;

  @override
  final bool isAnonymous;

  /// linkWithCredential の挙動をテスト側で差し替える
  Future<UserCredential> Function(AuthCredential credential)?
      onLinkWithCredential;

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) =>
      onLinkWithCredential!(credential);
}

class FakeUserCredential extends Fake implements UserCredential {
  FakeUserCredential(this.user);

  @override
  final User? user;
}

class FakeFirebaseAuth extends Fake implements FirebaseAuth {
  User? user;

  @override
  User? get currentUser => user;

  /// signInWithCredential の挙動をテスト側で差し替える
  Future<UserCredential> Function(AuthCredential credential)?
      onSignInWithCredential;

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) =>
      onSignInWithCredential!(credential);
}

// ==================== Firestore ====================

/// users コレクションのみを持つフェイク Firestore
class FakeFirestore extends Fake implements FirebaseFirestore {
  /// uid → ドキュメントデータ
  final Map<String, Map<String, dynamic>> users = {};
  final Map<String, StreamController<DocumentSnapshot<Map<String, dynamic>>>>
      _userStreams = {};
  Completer<void>? getGate;

  /// snapshots() が開かれた doc の数。listener を増やしていないことの確認に使う。
  int get listenerCount => _userStreams.length;

  void emitUser(String uid) {
    _userStreams[uid]?.add(_FakeSnapshot(users[uid]));
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    assert(collectionPath == 'users');
    return _FakeCollection(users, getGate, _userStreams);
  }
}

class _FakeCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _FakeCollection(this._store, this._getGate, this._streams);

  final Map<String, Map<String, dynamic>> _store;
  final Completer<void>? _getGate;
  final Map<String, StreamController<DocumentSnapshot<Map<String, dynamic>>>>
      _streams;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _FakeDoc(_store, path!, _getGate, _streams);
}

class _FakeDoc extends Fake implements DocumentReference<Map<String, dynamic>> {
  _FakeDoc(this._store, this._id, this._getGate, this._streams);

  final Map<String, Map<String, dynamic>> _store;
  final String _id;
  final Completer<void>? _getGate;
  final Map<String, StreamController<DocumentSnapshot<Map<String, dynamic>>>>
      _streams;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
      [GetOptions? options]) async {
    await _getGate?.future;
    return _FakeSnapshot(_store[_id]);
  }

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) async* {
    final controller = _streams.putIfAbsent(
      _id,
      () =>
          StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast(),
    );
    await _getGate?.future;
    yield _FakeSnapshot(_store[_id]);
    yield* controller.stream;
  }

  /// merge 指定のみ想定。SetOptions なしの上書きは使っていない。
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    final current = _store[_id];
    if (options?.merge == true && current != null) {
      current.addAll(data);
    } else {
      _store[_id] = Map<String, dynamic>.from(data);
    }
    _streams[_id]?.add(_FakeSnapshot(_store[_id]));
  }
}

class _FakeSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeSnapshot(this._data);

  final Map<String, dynamic>? _data;

  @override
  bool get exists => _data != null;

  @override
  SnapshotMetadata get metadata => _FakeSnapshotMetadata();

  @override
  Map<String, dynamic>? data() => _data;
}

class _FakeSnapshotMetadata extends Fake implements SnapshotMetadata {
  @override
  bool get isFromCache => false;

  @override
  bool get hasPendingWrites => false;
}

// ==================== Analytics / Purchase ====================

class FakeAnalyticsService extends Fake implements AnalyticsService {
  final List<String> tiers = [];
  final List<Map<String, Object?>> generateSentenceEvents = [];
  final List<Map<String, Object?>> quizStartEvents = [];
  final List<Map<String, Object?>> quizAnswerEvents = [];
  final List<Map<String, String>> quizOfferEvents = [];
  final List<Map<String, Object?>> confirmationQuizQuestionEvents = [];
  final List<Map<String, Object?>> interviewEvents = [];
  final List<Map<String, Object?>> vocabTestEvents = [];

  /// 購入導線の計測。source を控えるだけ（月額／買い切りの判別に使う）。
  final List<String> subscribeEvents = [];

  @override
  Future<void> setUserAppLanguage(String lang) async {}

  @override
  Future<void> logSubscribe({required String source}) async {
    subscribeEvents.add(source);
  }

  @override
  Future<void> logTapPaywall({required String source}) async {}

  @override
  Future<void> logPaywallView({
    required String source,
    required bool productLoaded,
  }) async {}

  @override
  Future<void> logReviewPrompt({
    required String source,
    required String outcome,
  }) async {}

  @override
  Future<void> logGuide({
    required String action,
    required String source,
  }) async {}

  @override
  Future<void> logSummaryQuizComplete({
    required int score,
    required int questionCount,
    int? vocabBefore,
    int? vocabAfter,
  }) async {}

  @override
  Future<void> logInterview({
    required String action,
    String? question,
    String? answer,
    int? answeredCount,
  }) async {
    interviewEvents.add({
      'action': action,
      'question': question,
      'answer': answer,
      'answeredCount': answeredCount,
    });
  }

  @override
  Future<void> logVocabTest({
    required String action,
    required String source,
    int? value,
  }) async {
    vocabTestEvents.add({
      'action': action,
      'source': source,
      'value': value,
    });
  }

  @override
  Future<void> setUserTier(String tier) async {
    tiers.add(tier);
  }

  @override
  Future<void> logGenerateSentence({
    required String tier,
    String? topic,
    required String source,
    int? count,
  }) async {
    generateSentenceEvents.add({
      'tier': tier,
      'topic': topic,
      'source': source,
      'count': count,
    });
  }

  @override
  Future<void> logQuizStart({
    required String category,
    int? questionCount,
    String? source,
  }) async {
    quizStartEvents.add({
      'category': category,
      'question_count': questionCount,
      'source': source,
    });
  }

  @override
  Future<void> logQuizAnswer({
    required bool correct,
    required String category,
    int? questionIndex,
    String? source,
    String? quizFormat,
    int? srsInterval,
    int? responseMs,
  }) async {
    quizAnswerEvents.add({
      'correct': correct,
      'category': category,
      'question_index': questionIndex,
      'source': source,
      'quiz_format': quizFormat,
      'srs_interval': srsInterval,
      'response_ms': responseMs,
    });
  }

  @override
  Future<void> logQuizOffer({
    required String action,
    required String source,
  }) async {
    quizOfferEvents.add({'action': action, 'source': source});
  }

  @override
  Future<void> logConfirmationQuizQuestion({
    required String action,
    required String quizFormat,
    int? responseMs,
    bool? correct,
    String? exitReason,
  }) async {
    confirmationQuizQuestionEvents.add({
      'action': action,
      'quiz_format': quizFormat,
      'response_ms': responseMs,
      'correct': correct,
      'exit_reason': exitReason,
    });
  }
}

class FakePurchaseService extends Fake implements PurchaseService {
  bool restoreCalled = false;
  bool buyCalled = false;
  int fetchProductCalls = 0;
  bool initializeAvailable = true;
  int initializeCalls = 0;
  Object? fetchProductError;

  /// restore() 時のサーバー側処理（verifySubscription→Firestore更新）を模擬する
  void Function()? onRestore;

  @override
  PurchaseCallback? onPurchaseCompleted;

  @override
  void Function(String message)? onPurchaseError;

  @override
  PurchaseCallback? onPurchaseCanceled;

  @override
  void Function(String message)? onPurchasePending;

  @override
  Future<bool> initialize() async {
    initializeCalls++;
    return initializeAvailable;
  }

  /// 買い切り商品も返すか（iOS 相当の環境を模す）
  bool includeLifetimeProduct = true;

  /// 年額商品も返すか（ストアに登録済みの環境を模す）
  bool includeYearlyProduct = true;

  @override
  Future<PremiumProducts> fetchProducts() async {
    fetchProductCalls++;
    final error = fetchProductError;
    if (error != null) throw error;
    return PremiumProducts(
      monthly: ProductDetails(
        id: kProductIdPremiumMonthly,
        title: 'プレミアム',
        description: 'プレミアムプラン',
        price: '¥800',
        rawPrice: 800,
        currencyCode: 'JPY',
      ),
      yearly: includeYearlyProduct
          ? ProductDetails(
              id: kProductIdPremiumYearly,
              title: 'プレミアム年額',
              description: 'プレミアム年額プラン',
              price: '¥4,800',
              rawPrice: 4800,
              currencyCode: 'JPY',
            )
          : null,
      lifetime: includeLifetimeProduct
          ? ProductDetails(
              id: kProductIdPremiumLifetime,
              title: 'プレミアム買い切り',
              description: 'プレミアム買い切りプラン',
              price: '¥1,800',
              rawPrice: 1800,
              currencyCode: 'JPY',
            )
          : null,
    );
  }

  /// 直近に購入した商品（どのプランを買ったかの判別に使う）
  ProductDetails? lastBought;

  @override
  Future<void> buy(ProductDetails product) async {
    buyCalled = true;
    lastBought = product;
  }

  @override
  Future<void> restore() async {
    restoreCalled = true;
    onRestore?.call();
  }

  @override
  Future<void> waitForPendingVerifications({
    Duration settleDelay = const Duration(milliseconds: 500),
    Duration timeout = const Duration(seconds: 35),
  }) async {
    await Future<void>.delayed(settleDelay);
  }

  @override
  void dispose() {}
}
