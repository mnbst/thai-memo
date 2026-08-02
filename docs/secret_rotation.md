# シークレットのローテート手順

> **状態: 2026-08-02 に dev / tester / prod の3環境とも実施完了。**
> Gemini キー（環境ごとに新規発行）・OpenAI キー・Google OAuth client secret・
> Apple Sign-in 鍵（Key ID `JGPGZZ5HRP`）を差し替え、動作確認済み。
> 旧 Gemini キーは削除・失効確認済み。旧 OpenAI キーと旧 Apple 鍵 `5LU78HU4GU` は
> 手動 revoke が必要（未確認）。
> 以降は次回ローテート時の手順書として参照する。

`terraform/{dev,tester,prod}.tfvars` に平文でコミットされていたシークレットを無効化し、
新しい値に差し替えるための手順書。**リポジトリを public 化する前に必ず完了させること。**

## 対象

| 変数 | 種別 | 旧状態 |
|---|---|---|
| `gemini_api_key` | Gemini API キー | **dev/tester/prod で同一キーを共有** |
| `openai_api_key` | OpenAI API キー | **dev/tester/prod で同一キーを共有** |
| `google_client_secret` | Google OAuth Web client secret | 環境ごとに別（それぞれ露出） |
| `apple_private_key` | Sign in with Apple 秘密鍵 (.p8) | 全環境で同一（key_id `5LU78HU4GU`） |

いずれも git 履歴に残っているため、**新しい値に差し替えたうえで旧値を失効させる**まで漏洩リスクは消えない。

## 前提

- 変数ファイルは分離済み: 非機密は `terraform/<env>.tfvars`、機密は `terraform/secrets/<env>.tfvars`（gitignore 済み）
- 適用時は `-var-file` を 2 つ渡す

```bash
cd terraform
terraform init -backend-config=backends/<env>.tfbackend -reconfigure
terraform apply -var-file=<env>.tfvars -var-file=secrets/<env>.tfvars
```

- Cloud Functions は Secret Manager の `versions/latest` を**コールドスタート時に取得**する
  （`functions/javascript/src/services/secretManager.ts`, `functions/python/llm_providers.py`）。
  新バージョン追加後は既存インスタンスが旧値を保持し続けるため、**必ず再デプロイする**。

---

## 1. Gemini API キー

環境ごとに別キーを発行する（dev の漏洩が prod の課金被害にならないようにする）。

1. [Google AI Studio](https://aistudio.google.com/apikey) で対象 GCP プロジェクトを選び「Create API key」
   - dev = `thai-memo-dev` / tester = `thai-memo-67139` / prod = `thai-memo-prod`
2. GCP Console > APIs & Services > Credentials で作成されたキーを開き、
   **「API の制限の選択」を「1 個の API」→ `Gemini API`**（`generativelanguage.googleapis.com`）に設定
   - 「サービスアカウントにバインド」は**しない**（Functions 側は API キー渡しの実装のため）
   - 「アプリケーションの制限」は**なしのまま**でよい。利用元が Cloud Functions のサーバー
     サイドで、リファラー/IP/アプリ ID のいずれも該当しない（IP 制限には VPC コネクタ +
     Cloud NAT による固定 egress IP が必要で、この規模では過剰）。
     コンソールの警告はこの理由で無視してよい
3. `terraform/secrets/<env>.tfvars` の `gemini_api_key` を新しい値に更新
4. `terraform apply`（上記コマンド）
5. `firebase deploy --only functions` で再デプロイ
6. 動作確認後、**旧キーを削除**（Credentials 画面から削除。全環境の差し替えが済むまで消さないこと）

## 2. OpenAI API キー

1. [OpenAI Platform > API keys](https://platform.openai.com/api-keys) で環境ごとにキーを作成
   - プロジェクトを分けて **Usage limits（月額上限）** を設定しておくと濫用時の被害が限定される
2. `terraform/secrets/<env>.tfvars` の `openai_api_key` を更新
3. `terraform apply` → `firebase deploy --only functions`
4. 動作確認後、旧キーを **Revoke**

## 3. Google OAuth client secret

環境ごとに独立しているので個別にリセットする。

1. GCP Console > APIs & Services > Credentials > OAuth 2.0 Client IDs > 該当の **Web client** を開く
   - dev: `147810088545-4921rt150m9jtjate82nbol5q8hgoj3l...`
   - tester: `763566155520-anliuk00tk1fv4d0nou0o48dhroevlfg...`
   - prod: `219961294368-6lf7vceshitof77mflvjm0jujcbok68j...`
2. 「Reset secret」（旧 secret はこの時点で即失効）
3. `terraform/secrets/<env>.tfvars` の `google_client_secret` を更新
4. `terraform apply`（Firebase Auth の Google プロバイダ設定が更新される）
5. **実機で Google サインインを確認**

> ⚠️ Reset は即時失効なので、2〜4 は続けて実施すること。この間 Google サインインが失敗する。

## 4. Sign in with Apple 秘密鍵

鍵の差し替えで `apple_key_id` も変わる。**`apple_key_id` は非機密なので `terraform/<env>.tfvars` 側**、
`apple_private_key` は `terraform/secrets/<env>.tfvars` 側を更新する。

1. [Apple Developer > Certificates, IDs & Profiles > Keys](https://developer.apple.com/account/resources/authkeys/list) で
   「Sign in with Apple」を有効にした新しい鍵を作成し、`.p8` をダウンロード（**再ダウンロード不可**）
2. `terraform/<env>.tfvars` の `apple_key_id` を新しい Key ID に更新
3. `terraform/secrets/<env>.tfvars` の `apple_private_key` を新しい `.p8` の内容に更新
   - 改行は `\n` にエスケープした 1 行の文字列にする
4. 全環境で `terraform apply`
5. **実機で Apple サインインを確認**
6. 確認できてから Apple Developer で**旧鍵（`5LU78HU4GU`）を Revoke**

> 旧鍵を先に revoke すると全環境で Apple サインインが停止するため、必ず新鍵の動作確認後に revoke する。

---

## 完了チェックリスト

- [ ] Gemini キーを環境ごとに新規発行し、API 制限を設定した
- [ ] OpenAI キーを環境ごとに新規発行し、Usage limits を設定した
- [ ] Google OAuth client secret を 3 環境ともリセットした
- [ ] Apple Sign-in 鍵を新規発行し、`apple_key_id` も更新した
- [ ] 全環境で `terraform apply` 済み
- [ ] `firebase deploy --only functions` 済み（LLM キーの反映）
- [ ] 実機で Google / Apple サインイン、例文生成、クイズ生成を確認した
- [ ] 旧キー・旧 secret・旧鍵をすべて失効／削除した
- [ ] `git ls-files | xargs grep -lE 'AIzaSy|sk-proj-|GOCSPX-|BEGIN PRIVATE KEY'` が
      `lib/firebase_options_*.dart`（公開前提のクライアントキー）以外にヒットしない

ここまで完了して初めて、git 履歴のパージと public 化に進める。
