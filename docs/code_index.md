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
例文詳細表示（単語分解・発音付き）。初回は発音練習→単語の分解→文脈・使い方をスクロールしながら順にコーチマークで案内する（進捗は detail_tour_step）。

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
初回起動時のオンボーディング画面（3枚・スキップ不可）。

lib/presentation/screens/interview_screen.dart
オンボーディング直後のヒアリング4問（スキップ不可）。応答は挟まず、最後に1画面だけ回答に寄せた考え方を出す。回答は端末保存＋users docで、例文生成には効かせない。

lib/presentation/screens/tone_guide_screen.dart
タイ語声調システムのチュートリアル。

## Widgets

lib/presentation/widgets/loading_tip_carousel.dart
API呼び出し中のヒントカルーセル。

lib/presentation/widgets/coach_mark_overlay.dart
指定ウィジェットをスポットライト＋吹き出しで案内する初回コーチマークOverlay。一呼吸おいてから対象が光って押せるようになる（「わかった」ボタンは持たない）。id/analytics を渡すと shown/tapped/dismissed/closed をGA4へ送る。

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

lib/services/interview_reporter.dart
オンボ直後のヒアリング回答を users doc へ記録（interview / interview_answer_count）。属性別の定着分析に使う。送信できるまで起動のたびに再送。


lib/services/daily_sentence_service.dart
サーバー配信された毎日例文をFirestoreからローカルSQLiteへ取り込み、今日ぶんの配信例文を返す。`last_opened_at`（配信バックオフの開封シグナル）も更新する。

## Thai Language Processing (Dart)

lib/core/thai_tone_analyzer.dart
ルールベースのタイ語声調分析（子音クラス、音節タイプ、声調記号）。

lib/core/pronunciation_text.dart
ローマ字発音表記のサニタイズ（TLTK由来のバックスラッシュ混入を除去）。

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
復習キューからクイズ生成（回数上限なし。SRSの期日到来分だけが出題対象）。

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
例文の日次生成上限（free 5 / premium 20）。クイズ側の値は上限として機能しない。

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

functions/python/scripts/nlp_golden/extract_corpus.py
Firestoreの実データからNLP差分テスト用コーパス（corpus.jsonl）を抽出する。

functions/python/scripts/nlp_golden/gen_golden.py
コーパスに現行Python NLP実装を流しgolden.jsonlを固定する。Go移植の正解データ。

functions/python/scripts/nlp_golden/verify.py
候補実装（Go）の出力をgoldenと突き合わせる。tier1が1件でも不一致ならexit 1。

functions/python/scripts/nlp_golden/export_tltk_data.py
TLTK/PyThaiNLPの辞書・統計をGoが読める形式（UTF-8テキスト/JSON/gzip JSONL）に書き出す。

functions/go/internal/thainlp/data.go
移植用データのembedとロード。trigramからBiCount/Count/Type等をTLTKと同じ手順で導出する。

functions/go/internal/thainlp/thainlp.go
Thai NLP公開APIのGo版のエントリ定義。

functions/go/internal/thainlp/wordparse.go
語組み立てと音素確定のGo版。ProbPhone/SelectPhones/相互情報量（呼び出し内で累積）。移植済み。

functions/go/internal/thainlp/th2ipa.go
preprocess/g2p/th2ipaのGo版。IPA正規化まで。移植済み。

functions/go/internal/thainlp/pronunciation.go
IPA→声調記号付きローマ字変換のGo版（pronunciation.py相当）。移植済み。

functions/go/internal/thainlp/postag.go
POSタグ付けのGo版。unigram(tud)辞書引きとaveraged perceptron(orchid_ud)。移植済み。

functions/go/internal/thainlp/sylrule.go
th2ipa の音韻規則テーブル(PRON 2223本/stable/AK/EngAbbr)のロード。regexp2で先頭一致。

functions/go/internal/thainlp/sylparse.go
音節解析のGo版。チャートDP・ReplaceSnd/ToneAssign/TransformSyl・Witten-Bell対数確率。移植済み。

functions/go/internal/thainlp/tokenize.go
単語分割(newmm)・音節分割のGo版。TCC・Trie・最長一致・rejoin_formatted_num。移植済み。

functions/go/internal/thainlp/posjapanese.go
nlp.py の _tag_words/get_pos_japanese のGo版。override→形容詞辞書→unigram→perceptronの4段階。移植済み。

functions/go/cmd/nlpdump/main.go
差分テストハーネスのGo側。corpus.jsonlを読みgoldenと同形式のJSONLを吐く。

functions/go/functions.go
Cloud Functions(2nd gen, goランタイム)のエントリポイント登録。gcloudの--entry-pointがここの名前を指す。

functions/go/reset_learning_data.go
resetLearningData の Go 版。学習データを全消しし free のクォータに戻す。resetLearningData.ts と等価。

functions/go/internal/callable/callable.go
Firebase callable プロトコルのGo実装。{"data"}/{"result"}/{"error"}電文・IDトークン検証・CORS。

functions/go/internal/fbapp/fbapp.go
Firebase Admin(Firestore/Auth)クライアントの遅延生成シングルトン。

functions/go/internal/quota/quota.go
生成回数クォータ定数。constants/quota.ts の移植（両者を一致させること）。

functions/go/cmd/local/main.go
デプロイ前のローカル起動用。FUNCTION_TARGETで関数を選ぶ。

functions/go/reset_learning_data_live_test.go
resetLearningDataを実Firestoreに対して回す検証テスト。LIVE_FIRESTORE_TEST=1のときだけ実行。

functions/go/update_uvm.go
updateUvm の Go 版。クイズ結果からUVMを更新する。uvm_handlers.py と等価。

functions/go/update_uvm_live_test.go
Go版とPython版のbatch_update_uvmを同じ種で実Firestoreに流し書き込み結果を突き合わせる差分テスト。

functions/go/internal/uvm/model.go
UVMの純粋関数（update_p / moving_avg / estimate_vocab）と定数。uvm.py の移植。

functions/go/internal/uvm/store.go
UVMのFirestore層。batch_update_uvm / sync_estimated_vocab / publish_leaderboard_vocab。

functions/go/internal/uvm/nickname.go
ランキング表示名の自動採番。nicknames/{小文字名}をCreateで押さえて一意性を担保。

functions/go/internal/uvm/freqrank.go
GCSからfreq_rank_top10000.jsonを読みキャッシュする。

functions/python/scripts/uvm_golden/gen_golden.py
uvm.pyの純粋関数のgolden.jsonを生成する。Go版model.goの一致検証用。

functions/python/scripts/uvm_golden/run_batch_update.py
差分テストからPython版batch_update_uvmを1回だけ実Firestoreに流す。

functions/go/set_user_tier.go
setUserTier の Go 版。管理者がtierを切り替える。setUserTier.ts と等価。

functions/go/set_user_tier_live_test.go
Go版とJS版のapplyTierを同じ種で実Firestoreに流しusers/tier_grantsを突き合わせる差分テスト。

functions/go/send_contact_email.go
sendContactEmail の Go 版。Secret Managerのgmail-app-passwordでGmail SMTP送信。

functions/go/internal/tier/tier.go
tier手動付与の中核（applyTier）。tierService.ts の移植。tier_grantsに監査ログを残す。

functions/go/internal/mailer/mailer.go
Gmail SMTPでプレーンテキスト送信。件名のRFC2047エンコードとUTF-8宣言を自前で組む。

functions/javascript/scripts/runApplyTier.ts
差分テストからJS版applyTierを1回だけ実Firestoreに流す。

functions/go/subscription_status.go
subscriptionStatus の Go 版。期限切れpremiumをfreeに戻す。常にHTTPトリガーで、定期実行はCloud Scheduler側で決まる。

functions/go/subscription_status_live_test.go
落とす/残すの判定表を実Firestoreで1件ずつ確認する。全体スキャンは走らせない。

functions/go/daily_batch.go
dailyBatch の Go 版。日次クォータのリセット、UVMのP減衰、匿名ユーザー・重複fcm_token・古い例文の掃除。常にHTTPトリガー。

functions/go/deliver_daily_sentence.go
daily_sentence_handlers.py の Go 版。毎時起動し、配信対象へ例文を1件作ってFirestoreに書きFCM通知する。free はキャッシュのみ、premium/トライアルはLLM生成。

functions/go/deliver_daily_sentence_golden_test.go
配信の生成分岐・コミット時の更新内容・ロールバックの更新内容をPython実装の出力と突き合わせる。

functions/go/daily_batch_golden_test.go
resetQuota と duplicateTokenUids をJS実装の出力（golden JSON）と突き合わせる。削除境界の計算も検証。

functions/go/daily_batch_live_test.go
dailyBatch のFirestore書き込み部分を実Firestoreで検証。全体実行は行わない（Auth実削除を含むため）。

functions/go/internal/notify/notify.go
notifyUtcHour の Go 版。現地の配信希望時刻がUTCの何時に当たるかを求める。tzdataを埋め込む。

functions/go/internal/notify/golden_test.go
JS(Intl)が出した8510ケースの期待値とGo(tzdata)の結果を突き合わせる。

functions/go/internal/premium/premium.go
utils/premium.ts の Go 版。プレミアム体験トライアルの有効判定とJST 0:00への切り上げ。

functions/go/internal/subscription/subscription.go
constants/subscription.ts の Go 版。期限切れ判定の猶予とストア購入プラットフォームの定数。

functions/go/internal/userdata/userdata.go
deleteUserFirestoreData の Go 版。ユーザーのFirestoreデータ（サブコレクション・leaderboard・nicknames・quiz_queue）を一括削除。

functions/javascript/scripts/genNotifyGolden.ts
notifyUtcHour の期待値をJS実装から書き出す差分テスト用スクリプト。

functions/javascript/scripts/genQuotaGolden.ts
resetQuota と duplicateTokenUids の期待値を、firebase-adminをスタブして本物のdailyBatch.tsから書き出す。

functions/go/verify_subscription.go
verifySubscription の Go 版。ストアAPIで購入を検証しFirestoreへ保存。同一サブスクを持つ旧docからpremiumを剥奪する。

functions/go/verify_subscription_live_test.go
バリデーション文言、匿名拒否、ティア変更時のみのクォータリセット、旧doc剥奪を検証。

functions/go/handle_app_store_notification.go
handleAppStoreNotification の Go 版。Apple通知の署名検証と通知タイプごとのtier/status判定。エラーでも200を返す。

functions/go/handle_play_notification.go
handlePlayNotification の Go 版。Play RTDN(Pub/Sub)を受けてPlay APIで再検証しFirestoreを更新。

functions/go/notification_golden_test.go
通知ハンドラのFirestore更新内容をJS実装の出力と突き合わせる（App Store 1404ケース / Play 36ケース）。

functions/go/notification_live_test.go
通知ハンドラのFirestore部分を実Firestoreで検証。複数doc更新と無関係docの非巻き添えを確認。

functions/go/internal/applejws/applejws.go
Apple JWS の署名検証（発行者のCA判定 + x5cチェーン検証 + Apple Root CA G3 のフィンガープリント固定）とデコード。

functions/go/internal/applejws/rejected.go
署名検証で弾いたことを表すエラー型。200を返す通知ハンドラで監視用ログを出し分けるために使う。

functions/go/internal/appstore/client.go
App Store Server API v1 クライアント。ES256 JWT認証、購入検証、通知パース、sandbox/本番フォールバック。

functions/go/internal/appstore/types.go
App Store 検証結果・トランザクション情報・更新情報の型。

functions/go/internal/playbilling/playbilling.go
Google Play Developer API v3(Subscriptions v2)クライアント。購入トークンから状態を4種にマッピング。

functions/go/internal/secrets/secrets.go
Secret Manager からシークレットを読む。環境変数による差し替えに対応。

functions/javascript/scripts/appleTestCerts.ts
Apple JWS 検証テスト用の証明書。appStoreServer.test.tsから機械的に抜き出したもの。

functions/javascript/scripts/genAppleJwsGolden.ts
Apple JWS の署名検証（通す/弾く）の期待値をJS実装から書き出す。

functions/javascript/scripts/genAppStoreGolden.ts
verifyAppStorePurchase の判定と叩くURLの順序をJS実装から書き出す。

functions/javascript/scripts/genPlayGolden.ts
verifyPlayPurchase の判定をJS実装から書き出す。

functions/javascript/scripts/genNotificationGolden.ts
通知ハンドラのFirestore更新内容をJS実装から書き出す。

functions/go/generate_quiz.go
generateQuiz / generateLearningQuiz の Go 版。エントリポイントと定数、Geminiクライアントの生成。

functions/go/generate_quiz_sources.go
クイズ生成元の組み立て。sentence_detail・key_word意味の解決・クライアント向け1問への変換。

functions/go/generate_quiz_srs.go
SRS(間隔反復)による復習例文の選出とUVMによる補充、モデル呼び出しと再試行。

functions/go/generate_quiz_golden_test.go
generateLearningQuiz の組み立てとエラーをJS実装の出力と突き合わせる。

functions/go/generate_quiz_live_test.go
SRS選出とUVM補充を実Firestoreで検証。クエリ境界(JST 0:00)も確認。

functions/go/internal/quizgen/normalize.go
テキスト正規化・タイ語判定・注釈除去・空欄生成。JSの \s と同じ空白集合を使う。

functions/go/internal/quizgen/prepare.go
穴埋め位置の確定とルールベース項目の合成、例文発音の空欄化。

functions/go/internal/quizgen/prompt.go
クイズ生成のシステムプロンプトとユーザープロンプト(ja/en)。JS版と1バイトも変えないこと。

functions/go/internal/quizgen/sanitize.go
モデル出力の検査と整形。選択肢・ダミー理由・選択肢発音の対応付け。

functions/go/internal/quizgen/types.go
クイズ生成の入出力の型。

functions/go/internal/quizgen/golden_test.go
プロンプト(バイト一致)と整形処理をJS実装の出力と突き合わせる。

functions/go/internal/gemini/quiz.go
Gemini APIでクイズ1問分のダミー・理由・解説を生成する。トークン使用量のログも出す。

functions/go/internal/gemini/schema.go
Gemini の responseSchema(ja/en)。

functions/go/internal/lang/lang.go
訳文・解説の言語(ja/en)の正規化。

functions/javascript/scripts/genQuizGolden.ts
プロンプト・整形処理・Geminiリクエスト本文の期待値をJS実装から書き出す。

functions/javascript/scripts/genLearningQuizGolden.ts
generateLearningQuiz の組み立てとエラーをJS実装から書き出す。

functions/go/internal/dailysentence/dailysentence.go
daily_sentence.py の Go 版。毎日例文の配信判定（段階バックオフ・見送り理由・現地時刻）。

functions/go/internal/dailysentence/golden_test.go
配信判定をPython実装の出力と突き合わせる（6000ケース + タイムゾーン112ケース）。

functions/go/internal/dailysentence/notification.go
毎日例文のFCM通知タイトル・本文の組み立て。タイトルは言語別、本文はタイ文/発音/訳の3行。

functions/go/internal/dailysentence/notification_golden_test.go
通知文面をPython実装の出力と突き合わせる（53ケース）。

functions/go/internal/sentence/constants.go
constants.py の Go 版。モデル設定・クォータ定数・context英語化・レスポンススキーマ組み立て。

functions/go/internal/sentence/constants_data.go
constants.py のデータ部分（STYLES/TOPICS/ラベル表/JSON Schema）の自動生成。手で編集しないこと。

functions/go/internal/sentence/golden_test.go
スキーマ組み立てとcontext英語化をPython実装の出力と突き合わせる。

functions/python/scripts/daily_golden/gen_golden.py
daily_sentence.py の判定結果を書き出す差分テスト用スクリプト。

functions/python/scripts/daily_golden/gen_constants_golden.py
constants.py のスキーマ組み立てとcontext英語化を書き出す差分テスト用スクリプト。

functions/python/scripts/gen_go/gen_constants.py
constants.py のデータ部分から Go ソース（constants_data.go）を生成する。

functions/go/internal/embeddings/embeddings.go
embeddings.py の Go 版。コサイン類似度（float64累積）・意味的重複除去・多様な語の貪欲選出。

functions/go/internal/embeddings/store.go
embedding データのGCS遅延ロードとキャッシュ、重みつき抽選。

functions/go/internal/embeddings/select.go
サブテーマ・ドラマショット・テーマの類似度による選出。

functions/go/internal/embeddings/npy.go
numpy の .npy（float32・C order・2次元）を numpy 無しで読む。

functions/go/internal/wordclass/wordclass.go
word_classes.py の Go 版。key_word の語クラス逆引き。

functions/go/internal/wordclass/classes_data.go
word_classes.json の自動生成。手で編集しないこと。

functions/go/internal/uvm/freqrank_live_test.go
GCS上のfreq_rankに欠番が無いこと（moving_avgの前提）を実データで確認する。

scripts/renumber_freq_rank.py
freq_rank の rank を1からの連番に振り直す。語の増減はしない。除去は strip_denylist.py。

functions/python/scripts/sim_renumber_impact.py
freq_rank振り直しがestimated_vocabに与える影響を実データで測る（読み取りのみ）。

functions/go/internal/sentence/prompts.go
prompts.py の Go 版（ロジック）。難易度・長さヒント・テーマゲート・各種制約ブロック。

functions/go/internal/sentence/prompts_data.go
prompts.py の文字列データ（組み立て済みシステムプロンプト含む）の自動生成。手で編集しないこと。

functions/go/internal/sentence/build_prompt.go
プロンプト本体の組み立て。抽選済みの値を受け取るので決定的。

functions/go/internal/sentence/prompts_golden_test.go
プロンプト全文・システムプロンプト・制約ブロックをPython実装とバイト単位で突き合わせる。

functions/python/scripts/gen_go/gen_prompts.py
prompts.py のデータ部分から Go ソース（prompts_data.go）を生成する。

functions/python/scripts/daily_golden/gen_prompts_golden.py
prompts.py の組み立て結果を書き出す差分テスト用スクリプト（抽選は固定）。

functions/python/scripts/daily_golden/gen_wordclass_golden.py
word_classes.py の分類結果を書き出す差分テスト用スクリプト。

functions/python/scripts/daily_golden/gen_embeddings_golden.py
embeddings.py の数値計算を書き出す差分テスト用スクリプト（合成データ）。

functions/go/internal/sentence/service.go
sentence_service.py の純粋ロジック。ๆ の空白詰め・ターゲット語検証・分かち書き崩壊の修正・再生成プロンプト。

functions/go/internal/sentence/service_golden_test.go
sentence_service.py / word_gap.py の純粋ロジックをPython実装と突き合わせる。

functions/go/internal/wordgap/wordgap.go
word_gap.py の Go 版。word_breakdownの欠落検出と補完結果の差し込み。

functions/python/scripts/daily_golden/gen_service_golden.py
sentence_service.py / word_gap.py の結果を書き出す差分テスト用スクリプト。

functions/go/internal/pystr/pystr.go
Pythonと同じ空白判定・split・strip。Goの\sはASCIIのみで全角スペースやNBSPを含まないため。

functions/go/internal/llm/llm.go
LLMプロバイダー抽象レイヤ（llm_providers.py の Go 版）。リクエスト送信・指数バックオフ再送・プロバイダー振り分け。

functions/go/internal/llm/openai.go
OpenAI Responses API のリクエスト組み立て・出力抽出・トークン単価計算。

functions/go/internal/llm/gemini.go
Gemini generateContent のリクエスト組み立て・出力抽出・トークン単価計算。

functions/go/internal/llm/errors.go
LLM API エラー型。再送してよいステータスの判定。

functions/go/internal/llm/golden_test.go
llm_providers.py とリクエスト本文・ログ行・再送回数を突き合わせる差分テスト。

functions/python/scripts/daily_golden/gen_llm_golden.py
llm_providers.py の結果を書き出す差分テスト用スクリプト。

functions/go/internal/sentence/types.go
例文と word_breakdown の型。LLMレスポンスmapからの読み込み。

functions/go/internal/sentence/generate.go
例文生成のフロー。target_notesの展開・NLP後処理・欠落補完・やり直しの制御。

functions/go/internal/sentence/generate_golden_test.go
生成フローとNLP後処理をPython実装と突き合わせる差分テスト。

functions/go/internal/thainlp/enrich.go
word_breakdownへの音節分割・発音・品詞の付与（nlp.py:enrich_with_nlp）と品詞ラベルの英訳。

functions/python/scripts/daily_golden/gen_generate_golden.py
sentence_service.py の生成フローと nlp.localize_pos / enrich_with_nlp の結果を書き出す差分テスト用スクリプト。

functions/go/internal/sentence/resolve.go
生成パラメータの確定（テーマ候補のゲート・時制と関係の抽選・サブテーマ選出）。

functions/go/internal/sentence/resolve_golden_test.go
resolve_generation_params の確定部分をPython実装と突き合わせる。

functions/python/scripts/daily_golden/gen_resolve_golden.py
resolve_generation_params の結果を書き出す差分テスト用スクリプト。

functions/go/internal/bldrama/bldrama.go
BLドラマ回の専用プロンプト断片。参考セリフの選出（embedding／ランダム）と断片の組み立て。

functions/go/internal/bldrama/data.go
BLドラマの設定・セリフ75件（自動生成。gen_bldrama.pyが出力）。

functions/go/internal/bldrama/golden_test.go
bl_drama.py とプロンプト断片・データを突き合わせる差分テスト。

functions/python/scripts/gen_go/gen_bldrama.py
themes/bl_drama.py のデータをGoソースへ書き出す。bl_drama.py変更時は再実行必須。

functions/python/scripts/daily_golden/gen_bldrama_golden.py
bl_drama.py のプロンプト断片を書き出す差分テスト用スクリプト。

functions/go/internal/uvm/session.go
key_word候補のランク帯算出・テーマembeddingでの絞り込み・重み付き抽選（uvm.py:get_session_words）。

functions/go/internal/uvm/exposure.go
例文に出た語の露出をUVMへ記録する（uvm.py:register_exposure / get_sentence_words）。

functions/go/internal/uvm/session_golden_test.go
uvm.py の選定・露出まわりと突き合わせる差分テスト。

functions/python/scripts/uvm_golden/gen_session_golden.py
uvm.py のランク帯・重み・テーマ絞り込み・露出の結果を書き出す差分テスト用スクリプト。

functions/go/internal/sentence/freebank.go
free例文バンク（GCS）の読み込みとキャッシュ、target_word一致の抽選。

functions/go/internal/sentence/select.go
テーマ候補プールの決定とUVMからのターゲット語選定（sentence_service.py:select_uvm_target_words）。

functions/go/internal/sentence/produce.go
単語選定→キャッシュ/LLM生成→ティア付与までの生成コア（sentence_handlers.py:produce_sentence）。

functions/go/internal/sentence/doc.go
Firestoreへ保存する例文ドキュメントの組み立てとkey_wordの引き当て。

functions/go/internal/sentence/select_golden_test.go
sentence_service.py のテーマ決定と突き合わせる差分テスト。

functions/go/internal/sentence/produce_golden_test.go
sentence_handlers.py の生成コア・保存ドキュメントと突き合わせる差分テスト。

functions/python/scripts/daily_golden/gen_select_golden.py
select_uvm_target_words / resolve_interview_topic の結果を書き出す差分テスト用スクリプト。

functions/python/scripts/daily_golden/gen_handlers_golden.py
sentence_handlers.py の純粋部分と produce_sentence の制御を書き出す差分テスト用スクリプト。

functions/python/scripts/daily_golden/gen_delivery_golden.py
daily_sentence_handlers.py の配信制御（生成分岐・コミット・ロールバック）を書き出す差分テスト用スクリプト。

functions/python/scripts/daily_golden/gen_notification_golden.py
毎日例文の通知文面を書き出す差分テスト用スクリプト。

functions/go/generate_thai_sentence.go
generateThaiSentence（callable）。認証・クォータ・トライアル判定・生成・保存・UVM更新。

functions/go/generate_thai_sentence_golden_test.go
sentence_handlers.py のクォータ・トライアル・生成条件と突き合わせる差分テスト。

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

scripts/ga4_register_dimension.py
prod GA4 にイベントスコープのカスタムディメンションを登録／一覧。文字列パラメータを足したら実装と同時に実行する（登録は遡及しない）。

scripts/ga4_language_resolution.py
prod GA4 の初回起動時の言語決定の内訳（storefront取得失敗率・country×langの食い違い・storefront→langの整合性）。日本以外のユーザーが日本語UIで起動していないかの確認に使う。

scripts/prod_quota_reach.py
例文生成の日次上限への到達率をCloud Loggingから集計（tier別・人日ベース・生成数分布）。上限値を上下させる判断材料。ログ保持30日ぶんのみ。

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
