- 出力する情報は常に必要最小限ででわかりやすいものにしてください

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Context management

Before writing new code:

- Read `docs/code_index.md` to understand the codebase structure and locate relevant files.
- Inspect relevant files.
- Do not keep investigation logs in context.
- Run `compact` after analysis.
- Then start implementation.

Goal: minimize token usage.

## Code index maintenance

ファイルの新規追加・削除・大幅な役割変更を行った場合、`docs/code_index.md` を更新すること。説明は1行で簡潔に。

## Project Overview

「まいにちタイ語」はタイ語学習Flutterアプリ。Google Gemini AIとFirebase Cloud Functionsで毎日タイ語例文を生成し、単語分解・発音・日本語訳を提供する。UIとエラーメッセージは日本語。

Main code: lib/
Backend: Cloud Functions
Infra: Terraform

Ignore:
android/
ios/
build/
node_modules/

## Build & Development Commands

```bash
# Install dependencies
flutter pub get

# Run code generation (JSON serialization)
dart run build_runner build --delete-conflicting-outputs

# Run the app
flutter run

# Run tests
flutter test
flutter test test/widget_test.dart  # single test

# Static analysis
flutter analyze

# Cloud Functions - JavaScript
cd functions/javascript && npm install && npm run build
cd functions/javascript && npm run deploy

# Cloud Functions - Python (generateThaiSentence)
cd functions/python && uv sync
cd functions/python && uv export --no-hashes > requirements.txt  # デプロイ前に実行

# Cloud Functions - 全関数デプロイ
firebase deploy --only functions

# Firestore Rules デプロイ
firebase deploy --only firestore:rules

# Infrastructure (in terraform/ directory)
# 環境: dev, tester, prod
# シークレットは secrets/<env>.tfvars（gitignore済み）に分離。2つの -var-file が必須。
cd terraform
terraform init -backend-config=backends/<env>.tfbackend -reconfigure
terraform plan  -var-file=<env>.tfvars -var-file=secrets/<env>.tfvars
terraform apply -var-file=<env>.tfvars -var-file=secrets/<env>.tfvars
```

## Architecture

Clean Architecture with three layers:

- **data/** — Datasources (SQLite via `database_helper.dart`, secure storage, backend API, Gemini API), models with JSON serialization (`json_serializable`), repository implementations
- **domain/** — Use cases (`GenerateSentence`, `GetSentences`, `DeleteSentence`)
- **presentation/** — Riverpod providers (`StateNotifierProvider` for sentence state), screens (Home with 4 tabs: 例文/クイズ/履歴/設定), widgets

Key services outside the layers:
- `FirebaseAuthService` — Google/Appleサインイン（匿名認証は非対応）
- `PurchaseService` — アプリ内課金・サブスクリプション検証
- `AdmobService` — 広告管理（Premium時は非表示）
- `TtsService` — タイ語発音のText-to-Speech

## State Management

Flutter Riverpod v2. Providers are defined in `lib/presentation/providers/sentence_provider.dart`. The main controller is `SentenceController` (StateNotifier) managing sentence generation, favorites, and deletion.

## Data Flow for Sentence Generation

1. App authenticates via Google/Apple Sign-in (Firebase Auth)
2. `BackendApiService` calls `generateThaiSentence` Cloud Function (asia-northeast1)
3. Cloud Function retrieves Gemini API key from GCP Secret Manager, calls Gemini API
4. Response is parsed into `ThaiSentence` + `WordBreakdown` models and saved to local SQLite DB

## Database

SQLite (`thai_memo.db`) with tables: `sentences`, `word_breakdowns`, `generation_logs`, `quiz_results`, `quiz_stats`, `daily_activity`, `streak_stats`. Foreign keys enabled with CASCADE delete. Schema constants in `lib/core/database_constants.dart`.

## Backend

- Cloud Functions (2 codebase構成):
  - `functions/javascript/` — TypeScript (Node.js 22): dailyBatch, generateQuiz, onUserCreate, verifySubscription, subscriptionStatus, deleteUserData, handlePlayNotification, handleAppStoreNotification
  - `functions/python/` — Python 3.11+ (uv管理): generateThaiSentence, updateUvm（PyThaiNLPで音節分割）
- Terraform IaC in `terraform/` for GCP resources (3環境: dev/tester/prod、backend configで切り替え)
- Region: asia-northeast1 (Tokyo)
- **Cloud Functions を修正したら必ず `firebase deploy --only functions` を実行すること**
- **Python側の依存追加時は `cd functions/python && uv add <pkg> && uv export --no-hashes > requirements.txt`**
