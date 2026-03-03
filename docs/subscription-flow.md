# サブスクリプションフロー

## アーキテクチャ概要

```
[Flutter App] <---> [RevenueCat SDK] <---> [App Store / Google Play]
                                                  |
                                           RevenueCat Dashboard
                                                  |
                                           Webhook (イベント通知)
                                                  |
                                    [Cloud Functions: revenuecatWebhook]
                                                  |
                                         [Firestore: users/{uid}.tier]
```

## 環境別の動作

| 環境 | ティア判定 | 購入ボタン動作 |
|------|-----------|---------------|
| **dev** | ローカル state のみ（RevenueCat未接続） | `toggleTier()` で Free ↔ Premium 即時切替 |
| **tester** | RevenueCat Sandbox | App Store Sandbox 経由の実購入フロー |
| **prod** | RevenueCat 本番 | App Store / Google Play 経由の実購入フロー |

## prod/tester: 購入フロー（RevenueCat）

### アップグレード（Free → Premium）

1. ペイウォール表示（設定画面のバナー or クォータ超過時）
2. 「プレミアムにアップグレード」タップ
3. `SubscriptionController.purchase()`
   - `RevenueCatService.getOfferings()` → 商品一覧取得
   - `RevenueCatService.purchasePackage()` → OS のストア決済シート表示
   - 成功時: `entitlements['premium'].isActive == true` → state を Premium に更新
4. ペイウォールを閉じ、SnackBar 表示

### ダウングレード（Premium → Free）

ユーザーが自分でダウングレードする操作は **アプリ内にはない**。以下のいずれかで発生:

1. **サブスク期限切れ（EXPIRATION）** — 更新しなかった場合、期間終了で自動 Free 化
2. **キャンセル（CANCELLATION）** — ユーザーが App Store / Google Play の設定でキャンセル
3. **決済問題（BILLING_ISSUE）** — カード失効等

いずれの場合も:
- RevenueCat が Webhook でイベント送信 → `revenuecatWebhook` Cloud Function が Firestore の `users/{uid}.tier` を `free` に更新
- アプリ側は `RevenueCatService.customerInfoStream` のリスナーで `entitlements['premium'].isActive` を監視 → state を Free に更新

### 購入復元

- 「購入を復元する」タップ → `Purchases.restorePurchases()`
- 別端末や再インストール時に有効な entitlement を復元

## dev: テスト用切替フロー

RevenueCat API キーが `PLACEHOLDER` のため SDK 初期化がスキップされ、ローカル state のみで動作。

### Free → Premium

1. 設定画面「プレミアムで全パラメータを解放」バナータップ
2. ペイウォール表示（UI は prod と同一）
3. 「プレミアムにアップグレード」タップ → `toggleTier()` で即時 Premium 化
4. ペイウォール閉じる

### Premium → Free

現在 Premium 状態だとアップグレードバナーが非表示のため、ペイウォールへの導線がない。
**→ Premium → Free の切替導線は未実装（要対応）**

## ペイウォール表示トリガー

| 画面 | トリガー |
|------|---------|
| 設定画面 | アップグレードバナータップ / ロックされたパラメータタップ |
| ホーム画面 | 例文生成のクォータ超過（Free: 5回/日） |
| クイズ画面 | クイズ生成のレート制限（Free: 1回/日） |

## Free/Premium 機能差分

| 機能 | Free | Premium |
|------|------|---------|
| 例文生成 | 5回/日 | 10回/日 |
| クイズ | 1回/日 | 10回/日 |
| トピック | 4種 | 16種 |
| 文体 | 2種 | 5種 |
| 例文出力設定 | x | o |
| 広告 | あり | なし |

## 関連ファイル

- `lib/services/revenuecat_service.dart` — RevenueCat SDK ラッパー
- `lib/presentation/providers/subscription_provider.dart` — state 管理・toggleTier
- `lib/presentation/screens/paywall_screen.dart` — ペイウォール UI
- `lib/presentation/providers/ad_provider.dart` — Premium 時の広告非表示
- `lib/core/constants/generation_constants.dart` — Free/Premium パラメータ制限
- `functions/javascript/src/revenuecatWebhook.ts` — Webhook で Firestore tier 更新
