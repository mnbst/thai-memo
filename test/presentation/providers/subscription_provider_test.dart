/// SubscriptionController のpremium復帰フローのテスト
///
/// 検証する仕様:
/// - 匿名ユーザーはFirestoreの値に関わらずfree扱い・自動復元もしない
/// - サインイン済みならFirestoreの tier=premium を即反映（premium復帰）
/// - サインイン済みでサブスク記録がなければストアから自動復元（silent restore）
/// - 匿名ユーザーの購入・手動復元はサインイン要求エラーでブロック
/// - サインイン後の手動復元でpremiumに復帰できる
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/presentation/providers/subscription_provider.dart';
import 'package:thai_memo/services/firebase_auth_service.dart';

import '../../helpers/fake_firebase.dart';

void main() {
  late FakeFirebaseAuth auth;
  late FakeFirestore firestore;
  late FakePurchaseService purchase;
  late SubscriptionController controller;

  SubscriptionController createController() => SubscriptionController(
        analytics: FakeAnalyticsService(),
        firestore: firestore,
        purchaseService: purchase,
        restoreDelay: Duration.zero,
      );

  setUp(() {
    auth = FakeFirebaseAuth();
    FirebaseAuthService.authOverride = auth;
    firestore = FakeFirestore();
    purchase = FakePurchaseService();
    controller = createController();
  });

  tearDown(() {
    FirebaseAuthService.authOverride = null;
  });

  group('initialize（起動時のtier取得）', () {
    test('匿名ユーザーはFirestoreがpremiumでもfree扱い・自動復元しない', () async {
      auth.user = FakeUser(uid: 'anon-uid', isAnonymous: true);
      firestore.users['anon-uid'] = {'tier': 'premium'};

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.isPremium, isFalse);
      expect(purchase.restoreCalled, isFalse);
    });

    test('サインイン済み: Firestoreのpremiumを即反映（premium復帰）', () async {
      auth.user = FakeUser(uid: 'user-1', isAnonymous: false);
      firestore.users['user-1'] = {
        'tier': 'premium',
        'subscription': {'productId': 'premium_monthly'},
      };

      await controller.initialize();

      expect(controller.state.isPremium, isTrue);
      // 既にサブスク記録があるので自動復元は不要
      expect(purchase.restoreCalled, isFalse);
    });

    test('サインイン済み・サブスク記録なしは自動復元が走りpremiumに復帰する', () async {
      auth.user = FakeUser(uid: 'user-1', isAnonymous: false);
      // 復元 → verifySubscription がFirestoreを更新する流れを模擬
      purchase.onRestore = () {
        firestore.users['user-1'] = {
          'tier': 'premium',
          'subscription': {'productId': 'premium_monthly'},
        };
      };

      await controller.initialize();
      // silent restore は unawaited なので完了を待つ
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(purchase.restoreCalled, isTrue);
      expect(controller.state.isPremium, isTrue);
    });
  });

  group('purchase / restore のサインインガード', () {
    test('匿名ユーザーの購入はサインイン要求エラーでブロックされる', () async {
      auth.user = FakeUser(uid: 'anon-uid', isAnonymous: true);

      await controller.purchase();

      expect(controller.state.errorMessage, 'プレミアムのご利用にはサインインが必要です');
      expect(purchase.buyCalled, isFalse);
    });

    test('匿名ユーザーの復元はサインイン要求エラーでブロックされる', () async {
      auth.user = FakeUser(uid: 'anon-uid', isAnonymous: true);

      await controller.restore();

      expect(controller.state.errorMessage, 'プレミアムのご利用にはサインインが必要です');
      expect(purchase.restoreCalled, isFalse);
    });
  });

  group('restore（手動復元）', () {
    test('サインイン後の手動復元でpremiumに復帰できる', () async {
      auth.user = FakeUser(uid: 'user-1', isAnonymous: false);
      purchase.onRestore = () {
        firestore.users['user-1'] = {
          'tier': 'premium',
          'subscription': {'productId': 'premium_monthly'},
        };
      };

      await controller.restore();

      expect(purchase.restoreCalled, isTrue);
      expect(controller.state.isPremium, isTrue);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.isLoading, isFalse);
    });

    test('復元できる購入がない場合はエラーメッセージを表示する', () async {
      auth.user = FakeUser(uid: 'user-1', isAnonymous: false);

      await controller.restore();

      expect(controller.state.isPremium, isFalse);
      expect(controller.state.errorMessage, '復元できる購入が見つかりませんでした');
    });
  });

  group('サインイン（昇格）後の復帰フロー', () {
    test('匿名free → リンク後のinitialize再実行でpremiumに復帰する', () async {
      // 匿名で起動: free
      auth.user = FakeUser(uid: 'anon-uid', isAnonymous: true);
      await controller.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.isPremium, isFalse);

      // 既存アカウント（premium購入済み）へサインイン
      // → sign_in_sheet が initialize() を再実行する
      auth.user = FakeUser(uid: 'premium-uid', isAnonymous: false);
      firestore.users['premium-uid'] = {
        'tier': 'premium',
        'subscription': {'productId': 'premium_monthly'},
      };
      await controller.initialize();

      expect(controller.state.isPremium, isTrue);
    });

    test('解約後はrefreshTierでfreeに戻る', () async {
      auth.user = FakeUser(uid: 'user-1', isAnonymous: false);
      firestore.users['user-1'] = {
        'tier': 'premium',
        'subscription': {'productId': 'premium_monthly'},
      };
      await controller.initialize();
      expect(controller.state.isPremium, isTrue);

      firestore.users['user-1'] = {
        'tier': 'free',
        'subscription': {'productId': 'premium_monthly'},
      };
      await controller.refreshTier();

      expect(controller.state.isPremium, isFalse);
    });
  });
}
