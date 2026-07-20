/// テスト用のFirebase系フェイク実装
///
/// Firebase.initializeApp なしでユニットテストを実行するため、
/// 使用するメンバーのみを最小実装している。
library;

// テスト用フェイクとして意図的にFirestoreのsealedクラスを実装する
// ignore_for_file: subtype_of_sealed_class

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

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    assert(collectionPath == 'users');
    return _FakeCollection(users);
  }
}

class _FakeCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _FakeCollection(this._store);

  final Map<String, Map<String, dynamic>> _store;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _FakeDoc(_store, path!);
}

class _FakeDoc extends Fake implements DocumentReference<Map<String, dynamic>> {
  _FakeDoc(this._store, this._id);

  final Map<String, Map<String, dynamic>> _store;
  final String _id;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
          [GetOptions? options]) async =>
      _FakeSnapshot(_store[_id]);
}

class _FakeSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeSnapshot(this._data);

  final Map<String, dynamic>? _data;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() => _data;
}

// ==================== Analytics / Purchase ====================

class FakeAnalyticsService extends Fake implements AnalyticsService {
  final List<String> tiers = [];
  final List<Map<String, Object?>> generateSentenceEvents = [];

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
}

class FakePurchaseService extends Fake implements PurchaseService {
  bool restoreCalled = false;
  bool buyCalled = false;

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
  Future<bool> initialize() async => true;

  @override
  Future<ProductDetails?> fetchProduct() async => ProductDetails(
        id: kProductIdPremiumMonthly,
        title: 'プレミアム',
        description: 'プレミアムプラン',
        price: '¥800',
        rawPrice: 800,
        currencyCode: 'JPY',
      );

  @override
  Future<void> buy(ProductDetails product) async {
    buyCalled = true;
  }

  @override
  Future<void> restore() async {
    restoreCalled = true;
    onRestore?.call();
  }

  @override
  void dispose() {}
}
