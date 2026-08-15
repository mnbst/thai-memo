# Code Index

## App Entry & Configuration

lib/main.dart
Firebase初期化（環境別オプション切替）、ProviderScopeでアプリ起動。

lib/app.dart
ルートMaterialApp。テーマ、ナビゲーション、認証状態リスナー。

lib/core/config/app_config.dart
アプリメタデータ、DB設定、ビルド環境設定。

lib/core/config/firebase_config.dart
Cloud Functionsのリージョン・タイムアウト・関数名定義。

lib/core/l10n/app_language.dart
アプリ言語（ja/en）の定義と、ストア地域からの初期値決定。端末ロケールは使わない。

lib/core/l10n/l10n_provider.dart
BuildContext を持たない層（provider・service）から文言を引く Riverpod プロバイダ。

lib/core/constants/generation_labels.dart
テーマ識別子（日本語のままサーバーへ送る）→表示ラベルの対応。

lib/core/quota_error.dart
エラーメッセージが生成上限によるものかの判定（「上限」/「limit」）。

lib/l10n/app_ja.arb / app_en.arb / app_localizations*.dart
UI文言のARBと gen_l10n 生成物（`flutter gen-l10n` で再生成）。

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

lib/presentation/widgets/sign_in_sheet.dart
サインイン促進ボトムシート（匿名→Google/Apple昇格link、課金時/設定から呼ぶ）。

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

lib/presentation/providers/quiz_offer_experiment_provider.dart
例文→1問確認クイズ導線のvariant定義。v1のA/Bテストはinlineカードで確定済み（全端末inline）。

lib/presentation/providers/subscription_provider.dart
ティア状態（free/premium）。Firestoreと同期、課金サービス連携。

lib/presentation/providers/settings_provider.dart
ユーザー設定（初回起動フラグ、テーマ、生成パラメータ、フォント、アプリ言語）。

lib/presentation/providers/tts_provider.dart
タイ語発音再生のText-to-Speechサービス。

lib/presentation/providers/leaderboard_provider.dart
語彙スコアランキング（leaderboard コレクション）。上位100人のストリームと、自分の順位（count集計。一覧の外でも出せる）。同点は同順位。

lib/presentation/providers/vocab_stats_provider.dart
Firestoreから語彙スコア・学習済み単語数をリアルタイム取得（Premium限定）。

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
設定画面（アカウント・プラン、テーマ、フォント、声調ガイド、学習データリセット、アプリ情報）。

lib/presentation/screens/paywall_screen.dart
プレミアム課金UI（ボトムシート）。導線は例文タブの常設バナー（premium_hint_banner）・設定・クイズ画面配下。自動表示はトライアルの開放案内・終了案内（source=trial_ended）のみで、他は全てタップ起点。

lib/presentation/screens/ranking_screen.dart
語彙スコアの全期間ランキング。自分の順位カードを上に置き、その下に上位100人を張り出す。表示名はサーバー採番のタイ人名。

lib/presentation/screens/onboarding_screen.dart
初回起動時のオンボーディング画面。

lib/presentation/screens/tone_guide_screen.dart
タイ語声調システムのチュートリアル。

## Widgets

lib/presentation/widgets/loading_tip_carousel.dart
API呼び出し中のヒントカルーセル。

lib/presentation/widgets/coach_mark_overlay.dart
指定ウィジェットをスポットライト＋吹き出しで案内する初回コーチマークOverlay。

lib/presentation/widgets/sign_in_reminder_banner.dart
匿名ユーザーへ3日非アクティブでの進捗削除を警告しサインインを促すバナー（今日タブ）。告知は3日だが実削除は7日（ANON_INACTIVE_DAYS）で意図的にずらしている。

lib/presentation/widgets/level_up_dialog.dart
語彙レベルアップ時のお祝いアニメーションダイアログ。

lib/presentation/widgets/topic_picker.dart
例文テーマ選択ダイアログ（設定・例文画面で共用）とラベル整形ヘルパー。

lib/presentation/widgets/sentence_audio_player.dart
例文全文の再生／停止＋リピート再生と、単語単位の頭出しバー。

lib/presentation/widgets/notification_coach_dialog.dart
毎日例文通知を継続サポート機能として紹介するコーチングダイアログ＋表示判定。

lib/presentation/widgets/premium_trial_ended_dialog.dart
プレミアム体験トライアル終了を伝えて登録へ誘導するダイアログ。起動時に一度だけ表示。

lib/presentation/widgets/premium_trial_started_dialog.dart
後から配られたプレミアム体験の開放を伝えるダイアログ（premium_trial_backfilled_at が目印）。課金は勧めない。

lib/presentation/widgets/premium_hint_banner.dart
例文カード直下に常設するfree向けプレミアム訴求バナー。訴求軸（テーマ/品質/語彙上限）を起動ごとに均等ランダム抽選、×で3日間非表示。お試し期間中は出さない。

lib/presentation/widgets/quiz_offer.dart
1問確認クイズ導線の表示（現行はinlineカード。controlは実験再開用に残置）。

lib/presentation/widgets/swipe_back.dart
右フリックで前画面へ戻すラッパー。Cupertinoの戻るジェスチャが左端20px限定なので、その補助として全面で拾う。

lib/presentation/tone_explanation_dialog.dart
タイ語声調の解説ダイアログ。

## Services

lib/services/purchase_service.dart
アプリ内課金（iOS/Android）とサブスクリプション検証。

lib/services/storefront_service.dart
ダウンロード元のストア地域取得。初回起動時のアプリ言語決定にだけ使う。

lib/services/tts_service.dart
タイ語発音のText-to-Speechエンジン。

lib/services/push_notification_service.dart
FCMトークン・タイムゾーン・配信希望時刻をusers/{uid}に登録。OSの通知許可とアプリ内設定の突き合わせも行う。

lib/services/app_version_reporter.dart
起動時に users doc へ app_version / app_build_number / last_opened_at を記録。サーバー側の機能出し分け判定に使う。

lib/services/daily_sentence_service.dart
サーバー配信された毎日例文をFirestoreからローカルSQLiteへ取り込み、今日ぶんの配信例文を返す。`last_opened_at`（配信バックオフの開封シグナル）も更新する。

## Thai Language Processing (Dart)

lib/core/thai_tone_analyzer.dart
ルールベースのタイ語声調分析（子音クラス、音節タイプ、声調記号）。

## Pronunciation Practice (声調の発音判定)

lib/core/pronunciation/pitch_track.dart
F0系列の前処理。Hz→セミトーン変換とメディアンフィルタによるオクターブ誤り除去。

lib/core/pronunciation/speaker_range.dart
話者の声域推定と正規化。録音から自己推定し、不安定なときは蓄積プロファイルで代替する。

lib/core/pronunciation/tone_contour.dart
5声調の標準ピッチカーブ定数と、音節の声調列からお手本カーブを組み立てる処理。

lib/core/pronunciation/dtw.dart
DTWでお手本カーブと録音ピッチを対応づける（音節境界の推定を兼ねる）。

lib/core/pronunciation/pronunciation_scorer.dart
音節ごとの採点。レベル誤差（高さ）と形状誤差（動き）の2軸で ○/惜しい/× を出す。

lib/core/pronunciation/pronunciation_analyzer.dart
発音判定のパイプライン全体。マイク・UIに依存しない純粋関数で、録音なしでテストできる。

lib/domain/sentence_tone_spans.dart
単語分解から音節の声調列と語↔音節の対応を作る（thai_text の空白＝節の切れ目も拾う）。

lib/core/pronunciation/transcript_match.dart
音声認識の結果と例文を語単位で照合し「通じたか」を返す。声調とは別軸の検査。

lib/core/pronunciation/word_verdict.dart
語ごとの声調判定と、声調＋発音を1本の帯にまとめる総合判定。

lib/core/pronunciation/pronunciation_coach.dart
採点結果から「次の1回で直す点」を1つだけ選ぶ。判定の2軸（形・入り方）をそのまま使う。

lib/core/pronunciation/segment_coach.dart
通じなかった語の子音・母音の直し方を1つ選ぶ。日本語話者が外しやすい順の優先表。

lib/services/speech_capture_service.dart
ネイティブのマイク収録との橋渡し。マイクは1箇所だけが握り、PCMと音声認識へ分岐する。

lib/services/pitch_recorder_service.dart
収録からF0抽出まで。YINは重いので抽出は必ず別isolate（compute）で回す。

lib/presentation/providers/pronunciation_provider.dart
発音練習の状態管理（録音→判定→永続化）と、声調別集計・最弱声調の算出。

lib/presentation/providers/pronunciation_quota_provider.dart
free の発音チェック回数（1日5回）。判定は端末内なのでカウンタもローカル（SharedPreferences）。

lib/presentation/widgets/pronunciation_practice.dart
例文詳細の発音練習セクション。語ごとの判定色帯と、選択した語のピッチカーブ描画。

---

lib/presentation/widgets/pronunciation_sheet.dart
ホームの例文カードから発音練習を開くボトムシート。中身は pronunciation_practice の再利用。

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

functions/javascript/src/setUserTier.ts
管理者用callable：任意ユーザーのtierを手動切り替え（ADMIN_UIDS / custom claim admin で制限）。

functions/javascript/src/services/tierService.ts
tier付与の中核ロジック（クォータリセット・subscription書き込み・tier_grants監査ログ）。クーポン導線でも再利用する。

### Notification Handlers

functions/javascript/src/handlePlayNotification.ts
Google Play RTDN（Pub/Sub）サブスクリプションイベント処理。

functions/javascript/src/handleAppStoreNotification.ts
App Store Webhookサブスクリプションイベント処理。

### Content Generation & Batch

functions/javascript/src/generateQuiz.ts
復習キューからクイズ生成（クォータチェック付き）。

functions/javascript/src/dailyBatch.ts
日次バッチ（JST 0:00）：日次クォータリセット、UVMのP値減衰、30日超過例文削除、非アクティブ匿名ユーザー削除。

### Services

functions/javascript/src/services/quizGenerationService.ts
クイズ生成のプロンプト構築・サニタイズ・ルールベース変換。解説とダミー理由はlangでja/en分岐（NG例・書式は共有）。

functions/javascript/src/services/geminiQuizService.ts
Gemini API呼び出しによるQuizGenerationService実装。

functions/javascript/src/services/secretManager.ts
GCP Secret ManagerクライアントでAPIキー取得。

functions/javascript/src/services/playBilling.ts
Google Play Developer API v3 購入検証。

functions/javascript/src/services/appStoreServer.ts
App Store Server API v1 サブスクリプション検証。

### Constants & Utilities

functions/javascript/src/constants/quota.ts
日次生成上限（free/premium別）。

functions/javascript/src/constants/subscription.ts
期限切れ降格の猶予・猶予期間上限・ストア platform 値。

functions/javascript/src/constants/defaultQuizQuestions.ts
クイズ生成フォールバック用デフォルト例文。

functions/javascript/src/utils/formatDate.ts
JST日付フォーマットユーティリティ。

functions/javascript/src/utils/notifyUtcHour.ts
配信希望時刻（現地）が対応するUTC時刻を算出。users.notify_utc_hourの非正規化に使う。

functions/javascript/src/utils/premium.ts
実効プレミアム判定（課金 premium ＋ 体験トライアル期間中）。tier 直参照の代わりに使う。

functions/javascript/src/utils/lang.ts
リクエストのlangをja/enへ正規化。未知・欠落はja。Python側 constants.resolve_lang と同規則。

---

## Cloud Functions — Python

functions/python/main.py
`generateThaiSentence`・`updateUvm`・`deliverDailySentence`を再エクスポートするエントリーポイント。実処理は各handlers.py。

functions/python/daily_sentence.py
毎日例文の配信判定ロジック（段階バックオフ・反応評価・ローカル時刻）。副作用なしでテスト可能。

functions/python/daily_sentence_handlers.py
毎日例文の配信バッチ（毎時起動）。free=キャッシュ／premium=LLM生成（preferred_topic反映）でFirestoreに書きFCM送信。

functions/python/nlp.py
PyThaiNLPラッパー（音節分割、発音変換、品詞タグ付け＋日本語ラベル）。品詞は機能語辞書→形容詞辞書→unigram→perceptronの順で判定。localize_posでenラベルへ変換。

functions/python/nlp_worker.py
nlp.pyを別プロセスで実行するワーカー。重いimportがGILで親のLLM処理を止めないようstdin/stdoutのJSON Linesで通信する。

functions/python/pythainlp_fast.py
PyThaiNLPの軽量ローダ。sys.modulesにスタブを置きパッケージ__init__を飛ばして使うsubmoduleだけ読む（import 1.32s→0.37s）。失敗時は通常importにフォールバック。

functions/python/pos_adjectives.py
形容詞（状態動詞）辞書。build_adjective_dict.pyが生成する自動生成ファイル。

functions/python/scripts/build_non_vocab_dict.py
freq_rank上位語をLLMに分類させnon_vocab.pyを生成するオフラインスクリプト。

functions/python/scripts/build_adjective_dict.py
freq_rank上位語をLLMに分類させpos_adjectives.pyを生成するオフラインスクリプト。

functions/python/bound_morphemes.py
拘束形態素（น่า, การ など単独で自立しない語）辞書。freq_rank生成時に除外する語のリスト。build_bound_morpheme_dict.pyが生成する自動生成ファイル。

functions/python/interjections.py
間投詞・感嘆詞（อ๋อ, เฮ้อ, โอ้ย など）辞書。freq_rank生成時に除外する語のリスト。手動メンテ。

functions/python/non_vocab.py
学習語彙にならない語（終助詞มั้ง・人名断片ซู・口語崩れงี้）辞書。build_non_vocab_dict.pyが生成する自動生成ファイル。

functions/python/pronunciation.py
タイ文字→ローマ字発音変換（声調記号付き）。TLTKはtltk/th2ipa.pyだけをファイル指定で単独ロードし、nltk/scipyの読み込みを回避する。

functions/python/prompts.py
Gemini APIプロンプト構築（free/premium/UVM別パラメータ）。レジスタ制約・語クラス別ブロックは末尾に置く（system promptでは守られないため）。

scripts/sample_sentences.py
ターゲット語を指定して本番と同じ経路で例文をまとめて生成するプロンプト検証スクリプト。デプロイせずルール変更の効果を確認する。

scripts/ga4_quiz_offer_experiment.py
1問確認クイズ導線A/BテストのGA4ファネルを実験群別に集計する。

functions/python/word_classes.py
word_classes.json のロードと語→クラス逆引き。pythainlpを引き込まない軽量モジュール。

functions/python/word_classes.json
key_wordの語クラス（三人称/一・二人称/限定詞/指示代名詞/数詞/数量詞/類別詞/多品詞語/機能語）と、その語がターゲットのときだけプロンプト末尾に足すルール。ルール追加はこのJSONを編集する。分割条件はJSON冒頭の_commentに記載。

functions/python/themes/bl_drama.py
BLドラマテーマのプロンプト断片構築。参考セリフ（BL_DRAMA_SHOTS）から1文だけをembedding類似度で選び出す。

functions/python/constants.py
LLMプロバイダー切替、OpenAI/Geminiモデル名、APIパラメータ、テーマ/スタイル/文法/感情リスト、レスポンスJSONスキーマ（build_response_schemaで未確定contextフィールドのみ追加）。

functions/python/llm_providers.py
LLMプロバイダー抽象レイヤ（OpenAI/Gemini切替、API呼び出し、リトライ、トークン使用量ログ）。両プロバイダーともurllibでREST直叩き（SDKはimportが重くコールドスタートを悪化させるため不使用）。

functions/python/uvm.py
UVMコアロジック（テーマ×語彙レベルによるセッション単語選定、P(know)更新、バッチ更新）。

docs/estimated_vocab_logic.md
estimated_vocab算出ロジックの詳細ドキュメント（estimate_vocab・moving_avg・sync_estimated_vocab）。

docs/sentence_generation_logic.md
例文生成ロジック（UVM単語選定→プロンプト構築→Gemini呼び出し→NLP後処理→Firestore保存）。

docs/design_english_version.md
英語版（app_language による UI・訳文の同時切替）の設計。l10n・プロンプト・free例文バンク・課金/分析への影響と段階リリース計画。

docs/design_daily_sentence.md
毎日例文の配信＋プッシュ通知の設計（配信ターゲティング、段階バックオフ、反応シグナル、必要フィールド）。

docs/design_pronunciation_practice.md
発音練習（声調）の設計。例文詳細でお手本と自分の声のピッチを比較する。F0抽出・自己正規化・DTW対応づけ・採点。

docs/quiz_generation_logic.md
クイズ生成ロジック（SRS例文選出→Gemini穴埋め生成→サニタイズ→デフォルト補填）。

docs/secret_rotation.md
git履歴に露出したシークレット（Gemini/OpenAIキー、OAuth secret、Apple秘密鍵）のローテート手順。

docs/public_repo_checklist.md
リポジトリpublic化の前提作業（履歴パージ、stateバケット堅牢化、WIF制約、GitHub設定）。

functions/python/embeddings.py
GCSからembedding/テーマembeddingをlazy-load、コサイン類似度でテーマ関連単語検索・セマンティック重複除去・ドラマ参考セリフ選出（find_best_drama_shot）。

---

## Infrastructure

terraform/modules/uvm-data/
GCSバケット（vocab_embeddings.npy, vocab_words.json, topic_embeddings.json格納）+ CF SA権限。

terraform/modules/monitoring/
予算アラート（billing budget）+ Cloud Monitoring アラートポリシー（5xx急増・生成失敗・生成数スパイク）。

terraform/modules/app-check/
Firebase App Check（iOS App Attest）の構成とサービス別適用モード、デバッグトークン。

docs/infra_hardening.md
予算/監視アラート・App Check・Firestore PITR の設計とロールアウト手順。

## Scripts

scripts/build_freq_rank.py
タイ語コーパスからPyThaiNLPで単語頻度ランキングを構築。corpus_word_filter.pyのDENYLIST（終助詞・感嘆詞＋拘束形態素）を除外して採番する。

scripts/strip_denylist.py
既存freq_rankから拘束形態素・間投詞を除去しrankを連番で振り直す移行スクリプト。

scripts/build_embeddings.py
freq_rank_top10000からVertex AI gemini-embedding-001でembedding生成。

scripts/build_topic_embeddings.py
テーマ・サブテーマ・BLドラマ参考セリフ（shot_embeddings.json）のembeddingを768次元で事前計算する。出力はcorpus/配下、アップロードはupload_corpus.sh。

scripts/upload_corpus.sh
UVMデータ（embeddings, vocab_words, freq_rank, topic_embeddings）をGCSにアップロード。

scripts/ga4_acquisition.py
prod GA4 の流入分析（日次新規・流入元・国・OS/バージョン別）。SAインパーソネーションで認証。

## Tests (Flutter)

test/helpers/fake_firebase.dart
FirebaseAuth/Firestore/PurchaseService/AnalyticsServiceのテスト用フェイク実装。

test/services/firebase_auth_service_test.dart
匿名→正規アカウントのリンク（昇格）・既存アカウントフォールバックのテスト。

test/presentation/providers/subscription_provider_test.dart
premium復帰フロー（Firestore tier反映・自動/手動復元・匿名ガード）のテスト。

## E2E (Maestro)

.maestro/smoke.yaml
起動〜3タブ遷移のスモークフロー。シミュレータ上の実アプリを座標/テキストで操作する。

.maestro/README.md
Maestroの実行手順（起動コマンド、studio、スクショの出力先）。
