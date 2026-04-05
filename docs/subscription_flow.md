# サブスクリプション登録フロー（iOS）

## シーケンス図

```mermaid
sequenceDiagram
    actor User
    participant App as Flutter App
    participant StoreKit as StoreKit (iOS)
    participant CF as Cloud Function<br/>verifySubscription
    participant Apple as Apple API<br/>(sandbox/prod)
    participant FS as Firestore

    User->>App: 「プレミアムに登録」タップ
    App->>StoreKit: buyNonConsumable()
    StoreKit-->>User: 決済シート表示
    User->>StoreKit: サンドボックスアカウントで承認

    StoreKit-->>App: purchaseStream<br/>PurchaseStatus.purchased

    App->>CF: verifySubscription({<br/>  platform: 'ios',<br/>  purchase_token: JWS,<br/>  product_id: 'premium_monthly'<br/>})

    CF->>CF: JWSをデコード<br/>→ transactionId取得

    alt ローカルStoreKit（transactionId が短い数値）
        CF->>CF: Apple APIスキップ<br/>valid=true 即返却
    else サンドボックス / 本番
        CF->>Apple: GET /inApps/v1/transactions/{transactionId}<br/>(JWT ES256認証)
        Apple-->>CF: signedTransactionInfo (JWS)
        CF->>CF: JWSデコード<br/>→ expiresDate, revocationDate確認
    end

    CF->>FS: users/{uid} を更新<br/>tier: 'premium'<br/>remaining_sentences: 5<br/>subscription.status: 'active'

    CF-->>App: { plan: 'premium', status: 'active' }

    App->>FS: _fetchTierFromFirestore()<br/>users/{uid}.tier を取得
    FS-->>App: tier: 'premium'
    App->>App: state.tier = UserTier.premium
    App-->>User: UI がプレミアム状態に切り替わる

    App->>StoreKit: completePurchase()<br/>トランザクション完了マーク
```

## 環境別の Apple API 分岐（CF内部）

```
purchase_token (JWS: eyJ...) を受信
        │
        ▼
   JWSデコード → transactionId 取得
        │
        ├─ 短い数値ID (1〜10桁) かつ非本番環境
        │         └─→ Apple API スキップ → valid=true（30日後期限）
        │
        └─ それ以外
                  ├─ APP_STORE_ENVIRONMENT = production
                  │         └─→ api.storekit.apple.com
                  └─ それ以外 (sandbox)
                            └─→ api.storekit-sandbox.apple.com
```

## 関連ファイル

| ファイル | 役割 |
|---------|------|
| `lib/services/purchase_service.dart` | 購入フロー・purchaseStream監視 |
| `lib/presentation/providers/subscription_provider.dart` | 状態管理（SubscriptionController） |
| `functions/javascript/src/verifySubscription.ts` | Cloud Function本体 |
| `functions/javascript/src/services/appStoreServer.ts` | Apple API検証・JWSデコード |
| `functions/javascript/src/handleAppStoreNotification.ts` | Apple Server Notifications V2 ハンドラ（更新・解約・失効） → `docs/appstore_notification_flow.md` |
