# インフラ堅牢化（予算/監視アラート・App Check・Firestore PITR）

すべて Terraform 管理。`terraform/<env>.tfvars` の変数で環境ごとに切り替える。

```bash
cd terraform
terraform init -backend-config=backends/<env>.tfbackend -reconfigure
terraform plan  -var-file=<env>.tfvars -var-file=secrets/<env>.tfvars
```

---

## 1. 予算アラート・監視アラート

`terraform/modules/monitoring/`

| リソース | 内容 |
| --- | --- |
| `google_monitoring_notification_channel.email` | 通知先メール（`alert_email`） |
| `google_billing_budget.monthly` | 月次予算。50/80/100%（実績）と 120%（予測）で通知 |
| `google_monitoring_alert_policy.function_errors` | Cloud Run 5xx が 5分で 10件超 |
| `google_monitoring_alert_policy.generation_failures` | `failed_sentence_generations` が 5分で 5件超 |
| `google_monitoring_alert_policy.generation_spike` | `successful_sentence_generations` が 5分で 100件超（LLMコスト暴走の検知） |

後ろ2つは `modules/logging` のログベース指標に依存する。

予算額: prod 10,000円 / dev・tester 各 3,000円（`budget_amount`）。

`alert_email` が空なら通知チャネル・アラートポリシーとも作られない。
`billing_account` が空なら予算だけ作られない。

**必要権限**: 予算の作成には請求先アカウントに対する `roles/billing.costsManager`
（または `billing.budgets.create`）が要る。プロジェクトの owner だけでは 403 になる。

## 2. App Check（iOS）

`terraform/modules/app-check/` + `lib/main.dart` の `_activateAppCheck()`

- iOS は **App Attest**（最低ターゲット iOS 16 のため DeviceCheck 併用は不要）
- デバッグビルドは `AppleDebugProvider`。起動ログに出るトークンを
  `secrets/<env>.tfvars` の `app_check_debug_token` に登録する
- 適用サービス: `firestore.googleapis.com`, `identitytoolkit.googleapis.com`
- **初期値は `UNENFORCED`**（検証はするが未証明リクエストも通す）

### ロールアウト手順

1. `app_check_enforcement_mode = "UNENFORCED"` のまま apply し、App Check 対応版をリリース
2. ~~Apple Developer ポータルで App ID の App Attest capability を有効化~~ → **2026-08-02 実施済み**
   （`com.thaimemo.thaiMemo` / bundleId `2T66JW94H9`。App Store Connect API の
   `capabilityType` 列挙に `APP_ATTEST` が無いため、Web UI での操作が必要だった）
3. Firebase コンソール > App Check のメトリクスで「未証明リクエスト」の割合を見る。
   Cloud Functions 側は `generateThaiSentence` のログの `appCheck` フィールドでも測れる
4. 十分下がったら `app_check_enforcement_mode = "ENFORCED"` に変更して apply
5. Cloud Functions の強制は別。`sentence_handlers.py` の `@https_fn.on_call(...)` に
   `enforce_app_check=True` を足す（同じく未証明の割合が下がってから）

旧クライアントは App Check トークンを送らないため、**先に強制すると弾かれる**。
必ず UNENFORCED → 計測 → ENFORCED の順で進めること。

### プロビジョニングプロファイル（2026-08-02）

App Attest capability の追加で既存プロファイルが無効化されたため、再生成した。

| | 旧 | 新 |
|---|---|---|
| 名前 | `Thai_Memo_AppStore`（INVALID） | `Thai_Memo_AppStore_AppAttest` |
| profile ID | `MP59CZK48V` | `Z92AH2NT7K` |
| 有効期限 | — | 2027-03-29 |

新プロファイルは App Store Connect API (`POST /v1/profiles`) で作成し、
`profileContent`（base64）をそのまま prod の Secret Manager `ci-provisioning-profile`
version 2 として登録済み。CI はプロファイル名をファイルから読む実装なので、
名前が変わってもワークフローの修正は不要。

entitlements には `com.apple.developer.devicecheck.appattest-environment` を追加
（Runner: `production` / RunnerDebug: `development`）。新プロファイルは両方の値を許可している。

旧プロファイル `Thai_Memo_AppStore`（INVALID）は削除していない。名前の重複で
新規作成が 409 になるため、同名で作り直したい場合は先に削除が必要。

## 3. Firestore PITR / バックアップ

`terraform/modules/firebase/main.tf`、変数 `enable_firestore_protection`（prod のみ true）

- PITR: 直近7日間の任意の時点に復元可能
- 日次バックアップ: 保持7日
- 週次バックアップ（日曜）: 保持14週
- 削除保護: `DELETE_PROTECTION_ENABLED`（`terraform destroy` の事故防止）

いずれも追加コストがかかるため dev/tester では無効のまま。

### 復元

```bash
# バックアップ一覧
gcloud firestore backups list --location=asia-northeast1

# バックアップから新しいDBへ復元（既存DBは上書きされない）
gcloud firestore databases restore \
  --source-backup=projects/thai-memo-prod/locations/asia-northeast1/backups/<ID> \
  --destination-database=restored-$(date +%Y%m%d)
```

PITR からの復元も `--source-database` + `--snapshot-time` で同様に別DBへ行う。
本番DBを直接巻き戻す操作はないので、復元後にアプリ側の向き先を切り替える判断が要る。

---

## 未対応

- Android: SAキー廃止（WIF移行）、Play Integrity — Android 対応時に着手
