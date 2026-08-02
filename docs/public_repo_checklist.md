# リポジトリ public 化チェックリスト

`docs/secret_rotation.md` のローテートが**全て完了してから**着手すること。

## 1. git 履歴のパージ

`terraform/{dev,tester,prod}.tfvars` の過去のコミット（初出: `a458228`, 2026-04-17）に
シークレットが平文で残っている。作業ファイルからは除去済みだが、履歴には残ったまま。

```bash
# 事前に必ずバックアップ
git clone --mirror https://github.com/mnbst/thai-memo.git ~/thai-memo-backup.git

brew install git-filter-repo

# 作業用にクリーンなミラーを取得
git clone https://github.com/mnbst/thai-memo.git /tmp/thai-memo-purge
cd /tmp/thai-memo-purge

# 該当ファイルを全履歴から削除（現行の非機密版も一度消える）
git filter-repo --invert-paths \
  --path terraform/dev.tfvars \
  --path terraform/tester.tfvars \
  --path terraform/prod.tfvars

# 非機密版を戻す（ローカルの現行ファイルからコピー）
cp /Users/gaku/project/thai-memo/terraform/{dev,tester,prod}.tfvars terraform/
git add terraform/*.tfvars && git commit -m "chore: restore non-sensitive tfvars"

git remote add origin https://github.com/mnbst/thai-memo.git
git push --force --all && git push --force --tags
```

### 注意

- **全コミットハッシュが変わる。** 他のクローン／作業ブランチは作り直しが必要
  （現在 `59-word-score-explanation` に未コミットの変更があるので先に退避すること）
- 未マージの PR は close される
- GitHub 側に古い blob がキャッシュされる場合があるため、パージ後に
  GitHub Support へ削除依頼を出すか、**新規リポジトリとして作り直す**のが確実
- いずれにせよ**旧キーの失効が本質的な対策**。履歴パージはそれを前提とした後始末

## 2. state バケットの堅牢化

state にはシークレットが平文で入る。バケット名は public 化で露出する。

```bash
for P in thai-memo-dev thai-memo-67139 thai-memo-prod; do
  B=gs://${P}-terraform-state
  gcloud storage buckets update $B --versioning
  gcloud storage buckets update $B --uniform-bucket-level-access
  gcloud storage buckets update $B --public-access-prevention
done
```

※ バケット名は `terraform/backends/*.tfbackend` で確認すること（prod は
`thai-memo-prod-terraform-state`）。現状 prod は versioning 無効・UBLA 無効・PAP 未強制。

## 3. WIF のブランチ固定（コード変更済み・apply 待ち）

`terraform/main.tf` の `attribute_condition` に `assertion.ref` の制約を追加済み。
各環境で apply して反映する。

```bash
cd terraform
terraform apply -var-file=prod.tfvars -var-file=secrets/prod.tfvars
```

反映後、`main` / `test` 以外のブランチからは OIDC 認証が通らなくなる。

## 4. 有効期限なし SA キーの廃止（**保留 — Android 対応時に着手**）

`terraform/main.tf` の `google_service_account_key.github_actions_play_upload` は
期限なしの鍵を state に平文保存している。WIF があるため本来は不要。

- Play アップロードを WIF 経由に切り替え → 当該リソースを削除 → 旧鍵を無効化

鍵の値自体は state 内にとどまり git には出ないため、public 化の**ブロッカーではない**。
ただし state バケットの堅牢化（項目2）は前提として必須。

## 5. GitHub リポジトリ設定

- Settings > Actions > General
  - Fork pull request workflows: **Require approval for all outside collaborators**
  - Allow GitHub Actions to create and approve pull requests: **OFF**
- Settings > Code security
  - Secret scanning: **ON**
  - Push protection: **ON**（再混入の防止。public なら無料）
- Settings > Branches: `main` / `test` に保護ルール（force push 禁止・レビュー必須）

## 6. クライアント側の保護

`lib/firebase_options_*.dart` と `android/app/google-services.json` の API キーは
公開前提のものだが、public 化を機に以下を入れる。

- Firebase App Check + Cloud Functions 側で `enforceAppCheck`
  - iOS: DeviceCheck / App Attest
  - Android: Play Integrity（**保留 — Android 対応時に着手**）
- GCP Console > Credentials で各 API キーにアプリ制限（iOS bundle ID / Android パッケージ名）

## 7. 公開直前の最終確認

```bash
git ls-files | xargs grep -lE 'AIzaSy|sk-proj-|GOCSPX-|BEGIN PRIVATE KEY|ya29\.'
```

ヒットしてよいのは以下のみ:

- `lib/firebase_options_{dev,tester,prod}.dart` — 公開前提のクライアントキー
- `functions/javascript/src/__tests__/appStoreServer.test.ts` — テスト用に自己生成した証明書・鍵
- `terraform/README.md`, `terraform/terraform.tfvars.example` — プレースホルダ
