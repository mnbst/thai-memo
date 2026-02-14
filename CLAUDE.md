出力する情報は常に必要最小限ででわかりやすいものにしてください

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Thai Memo is a Flutter app for learning Thai language. It generates daily Thai sentences with word-by-word breakdowns, pronunciation, and Japanese translations using Google Gemini AI via Firebase Cloud Functions. UI text and error messages are in Japanese.

## Build & Development Commands

```bash
# Install dependencies
flutter pub get

# Run code generation (JSON serialization)
flutter pub run build_runner build --delete-conflicting-outputs

# Run the app
flutter run

# Run tests
flutter test
flutter test test/widget_test.dart  # single test

# Static analysis
flutter analyze

# Cloud Functions (in functions/ directory)
cd functions && npm install && npm run build
cd functions && npm run serve   # local emulator
cd functions && npm run deploy  # deploy to Firebase

# Infrastructure (in terraform/ directory)
cd terraform && terraform plan
cd terraform && terraform apply
```

## Architecture

Clean Architecture with three layers:

- **data/** — Datasources (SQLite via `database_helper.dart`, secure storage, backend API, Gemini API), models with JSON serialization (`json_serializable`), repository implementations
- **domain/** — Use cases (`GenerateSentence`, `GetSentences`, `SaveSentence`, `DeleteSentence`)
- **presentation/** — Riverpod providers (`StateNotifierProvider` for sentence state), screens (Home with 3 tabs: Today/History/Settings), widgets

Key services outside the layers:
- `BackgroundService` — WorkManager-based 24-hour periodic sentence generation with 23-hour cooldown
- `NotificationService` — Local push notifications for new sentences
- `FirebaseAuthService` — Anonymous Firebase authentication (singleton)

## State Management

Flutter Riverpod v2. Providers are defined in `lib/presentation/providers/sentence_provider.dart`. The main controller is `SentenceController` (StateNotifier) managing sentence generation, favorites, and deletion.

## Data Flow for Sentence Generation

1. App authenticates anonymously via Firebase Auth
2. `BackendApiService` calls `generateThaiSentence` Cloud Function (asia-northeast1)
3. Cloud Function retrieves Gemini API key from GCP Secret Manager, calls Gemini API
4. Response is parsed into `ThaiSentence` + `WordBreakdown` models and saved to local SQLite DB
5. Background generation runs via WorkManager even when app is closed

## Database

SQLite (`thai_memo.db`) with tables: `sentences`, `word_breakdowns`, `generation_logs`, `app_settings`. Foreign keys enabled with CASCADE delete. Schema constants in `lib/core/constants/database_constants.dart`.

## Backend

- Cloud Functions in `functions/src/` (TypeScript, Node.js 18)
- Terraform IaC in `terraform/` for GCP resources
- Region: asia-northeast1 (Tokyo)
