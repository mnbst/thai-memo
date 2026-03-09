# Code Index

## App Entry & Configuration

lib/main.dart
Firebase初期化、Riverpod設定、FCMバックグラウンドハンドラ、AdMob初期化。

lib/app.dart
ルートMaterialApp。テーマ、ナビゲーション、認証状態リスナー。

lib/core/config/app_config.dart
アプリメタデータ、DB設定、ビルド環境設定。

lib/core/config/firebase_config.dart
Cloud Functionsのリージョン・タイムアウト・関数名定義。

lib/firebase_options_dev.dart / firebase_options_tester.dart / firebase_options_prod.dart
環境別Firebase設定（dev/tester/prod）。

## Constants

lib/core/database_constants.dart
SQLiteテーブル・カラム名の定数定義。

lib/core/constants/generation_constants.dart
日次生成上限（free/premium別クォータ値）。

lib/core/constants/loading_tips.dart
ローディング画面のヒントメッセージ。

## Authentication

lib/services/firebase_auth_service.dart
Firebase Authシングルトン。ログイン、ログアウト、ユーザー状態、トークン管理。

lib/presentation/providers/auth_provider.dart
Firebase Auth状態のRiverpodプロバイダー。

lib/presentation/screens/login_screen.dart
ログイン画面（Google/Apple、匿名フォールバック）。

## Data Models

lib/data/models/thai_sentence.dart
例文モデル。コンテキスト・単語分解付き、JSON/DBシリアライゼーション。

lib/data/models/word_breakdown.dart
単語分析モデル（発音、意味、文法的役割、音節）。

lib/data/models/syllable.dart
音節構造（声調・子音・母音の分析データ）。

lib/data/models/quiz_question.dart
クイズ問題モデル（正解＋3つの不正解選択肢）。

lib/data/models/quiz_result.dart
クイズ回答・スコア記録モデル。

## Data Sources

lib/data/datasources/backend_api_service.dart
Cloud Functions HTTPクライアント。例文生成・クイズ生成呼び出し、エラーマッピング。

lib/data/datasources/local/database_helper.dart
SQLite CRUD操作（sentences, word_breakdowns, generation_logs, quiz関連テーブル）。

lib/data/datasources/local/secure_storage_service.dart
暗号化キーバリューストレージ。

## Repository

lib/data/sentence_repository.dart
バックエンドAPIとローカルSQLiteの仲介。ユースケースロジック集約。

## Use Cases

lib/domain/generate_sentence_usecase.dart
例文生成オーケストレーション。エラーをUI向けメッセージに変換。

lib/domain/get_sentences_usecase.dart
例文取得（全件、フィルタ、お気に入り）。

lib/domain/delete_sentence_usecase.dart
例文と関連する単語分解の削除。

## Providers (State Management)

lib/presentation/providers/sentence_provider.dart
例文CRUD・生成状態のRiverpod StateNotifier。

lib/presentation/providers/quiz_provider.dart
クイズ状態管理（initial→pending→generating→ready→answering→result→summary）。

lib/presentation/providers/subscription_provider.dart
ティア状態（free/premium）。Firestoreと同期、課金サービス連携。

lib/presentation/providers/settings_provider.dart
ユーザー設定（テーマ、生成パラメータ、通知設定）。

lib/presentation/providers/ad_provider.dart
AdMobバナー/インタースティシャル広告状態（premium時は非表示）。

lib/presentation/providers/tts_provider.dart
タイ語発音再生のText-to-Speechサービス。

lib/presentation/providers/streak_provider.dart
連続学習ストリーク管理（日次活動記録・streak統計・起動時チェック）。

## Screens

lib/presentation/screens/splash_screen.dart
アプリ初期化中のローディング画面。

lib/presentation/screens/home_screen.dart
メイン画面。3タブナビゲーション（今日/履歴/設定）。

lib/presentation/screens/detail_screen.dart
例文詳細表示（単語分解・発音付き）。

lib/presentation/screens/history_screen.dart
保存済み例文一覧（全件/お気に入り、検索、削除）。

lib/presentation/screens/quiz_screen.dart
クイズ画面（問題出題、回答、結果確認）。

lib/presentation/screens/settings_screen.dart
設定画面（テーマ、通知、アカウント、アプリ情報）。

lib/presentation/screens/paywall_screen.dart
プレミアム課金UI。

lib/presentation/screens/onboarding_screen.dart
初回起動時のオンボーディング画面。

lib/presentation/screens/tone_guide_screen.dart
タイ語声調システムのチュートリアル。

## Widgets

lib/presentation/widgets/app_icon_title.dart
アプリヘッダー/ロゴウィジェット。

lib/presentation/widgets/loading_tip_carousel.dart
API呼び出し中のヒントカルーセル。

lib/presentation/tone_explanation_dialog.dart
タイ語声調の解説ダイアログ。

## Services

lib/services/fcm_service.dart
FCMトークン管理、通知ルーティング。

lib/services/purchase_service.dart
アプリ内課金（iOS/Android）とサブスクリプション検証。

lib/services/admob_service.dart
AdMob広告管理（サブスク状態に応じた表示制御）。

lib/services/tts_service.dart
タイ語発音のText-to-Speechエンジン。

## Thai Language Processing (Dart)

lib/core/thai_tone_analyzer.dart
ルールベースのタイ語声調分析（子音クラス、音節タイプ、声調記号）。

---

## Cloud Functions — JavaScript/TypeScript

functions/javascript/src/index.ts
全Cloud Functionsのエクスポート（エントリーポイント）。

functions/javascript/src/config/environment.ts
dev/prod環境検出、環境変数。

functions/javascript/src/config/constants.ts
共通設定定数。

### User & Subscription

functions/javascript/src/onUserCreate.ts
Auth トリガー：アカウント作成時にユーザークォータ初期化。

functions/javascript/src/verifySubscription.ts
購入検証（Android/iOS）、Firestoreティア更新。

functions/javascript/src/subscriptionStatus.ts
Firestoreからサブスクリプション状態を照会。

functions/javascript/src/deleteUserData.ts
GDPR対応：ユーザーデータ削除。

### Notification Handlers

functions/javascript/src/handlePlayNotification.ts
Google Play RTDN（Pub/Sub）サブスクリプションイベント処理。

functions/javascript/src/handleAppStoreNotification.ts
App Store Webhookサブスクリプションイベント処理。

### Content Generation & Batch

functions/javascript/src/generateQuiz.ts
復習キューからクイズ生成（クォータチェック付き）。

functions/javascript/src/dailyBatch.ts
夜間バッチ：SRSキュー再生成＋30日超過データクリーンアップ。

### Services

functions/javascript/src/services/geminiService.ts
Gemini APIクイズ生成ラッパー。

functions/javascript/src/services/secretManager.ts
GCP Secret ManagerクライアントでAPIキー取得。

functions/javascript/src/services/playBilling.ts
Google Play Developer API v3 購入検証。

functions/javascript/src/services/appStoreServer.ts
App Store Server API v1 サブスクリプション検証。

### Constants & Utilities

functions/javascript/src/constants/quota.ts
日次生成上限（free/premium別）。

functions/javascript/src/constants/defaultQuizQuestions.ts
クイズ生成フォールバック用デフォルト例文。

functions/javascript/src/utils/formatDate.ts
JST日付フォーマットユーティリティ。

---

## Cloud Functions — Python

functions/python/main.py
`generateThaiSentence`と`sendDailySentence`のエントリーポイント。Gemini API呼び出し、クォータチェック、NLPエンリッチメント。

functions/python/nlp.py
PyThaiNLPラッパー（音節分割、発音変換、品詞タグ付け＋日本語ラベル）。

functions/python/pronunciation.py
タイ文字→ローマ字発音変換（声調記号付き）。

functions/python/prompts.py
Gemini APIプロンプト構築（free/premium別パラメータ）。

functions/python/constants.py
Geminiモデル名、APIパラメータ、トピック/スタイル/文法/感情リスト、レスポンスJSONスキーマ。
