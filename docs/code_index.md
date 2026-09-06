# Code Index

## App Entry & Configuration

lib/main.dart
Firebase初期化（環境別オプション切替）、ProviderScopeでアプリ起動。

lib/app.dart
ルートMaterialApp。テーマ、ナビゲーション、認証状態リスナー。

lib/core/config/app_config.dart
アプリメタデータ、DB設定、ビルド環境設定。

lib/core/theme/app_colors.dart
アプリ全体のカラートークンと light/dark の ColorScheme 定義。

lib/core/theme/app_theme.dart
ThemeData の構築（app.dart から分離）。スクリーンショット生成など MyApp を起動しない経路からも同じ見た目を再現するため。

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

lib/data/models/vocab_test_step.dart
語彙テストの1往復ぶんの応答（出題1段ぶん、または最終結果）。正解は含まない。

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
Firestoreから語彙スコア・語彙テストの受験日と測定値をリアルタイム取得。

## Screens

lib/presentation/screens/splash_screen.dart
アプリ初期化中のローディング画面。

lib/presentation/screens/home_screen.dart
メイン画面。3タブナビゲーション（今日/履歴/設定）。

lib/presentation/screens/detail_screen.dart
例文詳細表示（例文カード・聞く／話す・使い方・単語・声調ガイド導線）。

lib/presentation/screens/history_screen.dart
保存済み例文一覧（検索・すべて/お気に入りのチップ絞り込み・スワイプ/一括削除）。1枚のカードに罫線区切りで積む。

lib/presentation/screens/quiz_screen.dart
クイズ画面（問題出題、回答、結果確認）。進み具合は上端の金の帯とAppBarの「2 / 5」（QuizProgressCounter）で示し、正誤は緑と朱、進む導線は下端の固定バー。ヒント（発音→訳文の2段階、使い切っても不活性で残す）は5問テストのみ。確認クイズはヒント無しで例文へ戻るだけ。

lib/presentation/screens/settings_screen.dart
設定画面。語彙スコアの深藍カード＋Free向け課金導線を先頭に置き、以下はアカウント/学習設定/表示/アプリについての4カード（見出し＋罫線区切り）。学習設定の先頭は読み物（使い方ガイド・声調ガイド）。

lib/presentation/screens/paywall_screen.dart
プレミアム課金UI（ボトムシート）。深藍の表題カード＋Free→Premiumの対比3行＋固定購入バー。導線は設定・クイズ画面配下。自動表示はトライアルの開放案内・終了案内（source=trial_ended）のみで、他は全てタップ起点。

lib/presentation/screens/ranking_screen.dart
語彙スコアの全期間ランキング。自分の順位カードを上に置き、その下に上位100人を張り出す。表示名はサーバー採番のタイ人名。

lib/presentation/screens/guide_screen.dart
アプリの使い方を1枚にまとめた説明書。並びは 概要 → 各機能の役割 → 操作のしかた。初回起動ではヒアリングの後・語彙テストの前に全文表示（スキップ可）、以後は設定「使い方ガイド」から読み返す。画面に重ねるコーチマークは持たない。要所には guide_figures.dart の図を挟む。

lib/presentation/screens/onboarding_screen.dart
初回起動時の機能紹介3枚（戻る不可・スキップ可）。この後にヒアリング→使い方ガイド→語彙テスト。

lib/presentation/screens/interview_screen.dart
初回起動時のヒアリング4問（この後に使い方ガイド→語彙テスト）（スキップ不可）。応答は挟まず、最後に1画面だけ回答に寄せた考え方を出す。回答は端末保存＋users docで、level は語彙テストの開始段に使う。

lib/presentation/screens/vocab_test_screen.dart
語彙テスト。4択を1段（4問）ずつサーバーから受け取り、落ちた段で終わる（初心者は4問）。初回は使い方ガイドの直後（mandatory: 戻る・スキップ無しで必ず測る）、以後は設定から。プレミアム限定。

lib/presentation/screens/tone_guide_screen.dart
タイ語声調システムのチュートリアル。

## Widgets

lib/presentation/widgets/loading_tip_carousel.dart
API呼び出し中のヒントカルーセルと、それを載せる生成待ちの白カード（LoadingCard）。例文生成・クイズ生成で共用。

lib/presentation/widgets/sign_in_reminder_banner.dart
匿名ユーザーへ3日非アクティブでの進捗削除を警告しサインインを促すバナー（今日タブ）。告知は3日だが実削除は7日（ANON_INACTIVE_DAYS）で意図的にずらしている。

lib/presentation/widgets/level_up_dialog.dart
語彙レベルアップ時のお祝いアニメーションダイアログ。

lib/presentation/widgets/vocab_level.dart
語彙レベルの区切り（入門〜上級）とラベル・アイコン、free の語彙スコア上限。

lib/presentation/widgets/topic_picker.dart
例文テーマ選択ダイアログ（設定・例文画面で共用）とラベル整形ヘルパー。

lib/presentation/widgets/sentence_audio_player.dart
例文全文の再生／停止＋リピート再生と、単語単位の頭出しバー。

lib/presentation/widgets/sentence_audio_section.dart
例文の下の「お手本を聞く／発音練習」2ボタンと、押したときに開く再生バー・録音UI。学習タブと例文詳細で共用。

lib/presentation/widgets/thai_highlight.dart
例文中の学習単語を金で示す TextSpan 生成（深藍面の金地・紙面の色のみ・発音の3種）。

lib/presentation/widgets/guide_figures.dart
使い方ガイドに載せる模式図（学習のくり返し・例文カードの構成・発音判定の色）。画面写真は使わず、文言はl10nから引く。

lib/presentation/widgets/notification_coach_dialog.dart
毎日例文通知を継続サポート機能として紹介するコーチングダイアログ＋表示判定。

lib/presentation/widgets/premium_trial_ended_dialog.dart
プレミアム体験トライアル終了を伝えて登録へ誘導するダイアログ。起動時に一度だけ表示。失う実数（例文の回数、語彙テストで測った値→free上限）だけを並べる。

lib/presentation/widgets/premium_trial_started_dialog.dart
後から配られたプレミアム体験の開放を伝えるダイアログ（premium_trial_backfilled_at が目印）。課金は勧めない。

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

lib/services/review_prompt_service.dart
App Storeのレビュー依頼をiOSのOSダイアログで出す。クイズ完走と例文生成の2経路から発火し、バージョン単位＋60日クールダウンで重複を防ぐ。

lib/services/interview_reporter.dart
初回ヒアリングの回答を users doc へ記録（interview / interview_answer_count）。属性別の定着分析に使う。送信できるまで起動のたびに再送。

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

lib/presentation/widgets/pronunciation_practice.dart
例文詳細の発音練習セクション。点数リングと語ごとの判定チップ、選択した語のピッチカーブ・お手本再生・直し方。

---

lib/presentation/widgets/pronunciation_sheet.dart
ホームの例文カードから発音練習を開くボトムシート。お手本の再生バー＋ pronunciation_practice。

---

## Cloud Functions — JavaScript/TypeScript

functions/javascript/src/index.ts
Authトリガー2本のエントリーポイント。

functions/javascript/src/onUserCreate.ts
Authユーザー作成時にクォータとプレミアム体験期限を初期化。

functions/javascript/src/deleteUserData.ts
Authユーザー削除時にFirestoreの関連データを削除。

functions/javascript/src/constants/quota.ts
Authユーザー初期化で使うクォータと体験期間の定数。

functions/javascript/src/utils/notifyUtcHour.ts
配信希望時刻が対応するUTC時刻を算出。

functions/javascript/src/utils/premium.ts
プレミアム体験期限をJSTの日次境界へ揃える。

---

## Cloud Functions — Go

functions/go/testdata/
Python/JavaScriptからの移行時に確定した回帰テスト用goldenデータ。旧ランタイムなしでGo実装の互換性を検証する。

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

functions/go/functions.go
Cloud Functions(2nd gen, goランタイム)のエントリポイント登録。gcloudの--entry-pointがここの名前を指す。

functions/go/reset_learning_data.go
resetLearningData の Go 版。学習データを全消しし free のクォータに戻す。resetLearningData.ts と等価。

functions/go/internal/callable/callable.go
Firebase callable プロトコルのGo実装。{"data"}/{"result"}/{"error"}電文・IDトークン検証・CORS。

functions/go/internal/callable/number.go
callable の data に載る整数を読む。Flutter SDK が int を包む Int64 ラッパーも解く。

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

functions/go/vocabtest.go
startVocabTest / submitVocabTest。語彙テストの出題・採点と estimated_vocab の書き込み。全員1段目から出題。プレミアム限定＋月1回（開始時刻を起点に30日、中断のやり直しのみ同一期間内3回まで）。

functions/go/internal/uvm/model.go
UVMの純粋関数（UpdateP / GuessRate / MovingAvg / EstimateVocab）と定数。P の更新は尤度比（推測率 g・うっかり率 s）。旧 α 則は UpdatePAlpha として golden 用に残す。

functions/go/internal/uvm/store.go
UVMのFirestore層。batch_update_uvm / sync_estimated_vocab / publish_leaderboard_vocab。

functions/go/internal/uvm/nickname.go
ランキング表示名の自動採番。nicknames/{小文字名}をCreateで押さえて一意性を担保。

functions/go/internal/uvm/freqrank.go
GCSからfreq_rank_top10000.jsonを読みキャッシュする。

functions/go/internal/uvm/vocabtest.go
語彙テストの純ロジック。段の昇降・早期終了・スコア変換・出題の組み立て・測定値が支える下限。11段（上限3000）／1段6問・5問通過。語ごとのPには触らない。

functions/go/internal/uvm/vocabtest_items.go
GCSから vocab_test_items_<lang>.json（出題語と訳）を読みキャッシュする。

functions/go/set_user_tier.go
setUserTier の Go 版。管理者がtierを切り替える。setUserTier.ts と等価。

functions/go/send_contact_email.go
sendContactEmail の Go 版。Secret Managerのgmail-app-passwordでGmail SMTP送信。

functions/go/internal/tier/tier.go
tier手動付与の中核（applyTier）。tierService.ts の移植。tier_grantsに監査ログを残す。

functions/go/internal/mailer/mailer.go
Gmail SMTPでプレーンテキスト送信。件名のRFC2047エンコードとUTF-8宣言を自前で組む。

functions/go/subscription_status.go
subscriptionStatus の Go 版。期限切れpremiumをfreeに戻す。常にHTTPトリガーで、定期実行はCloud Scheduler側で決まる。

functions/go/subscription_status_live_test.go
落とす/残すの判定表を実Firestoreで1件ずつ確認する。全体スキャンは走らせない。

functions/go/daily_batch.go
dailyBatch の Go 版。日次クォータのリセット、UVMのP減衰、匿名ユーザー・重複fcm_token・古い例文の掃除、生成例文の品質監査。常にHTTPトリガー。

functions/go/sentence_audit.go
dailyBatch から呼ぶ品質監査。直近24時間の premium 例文を無作為抽出してLLMに判定させ、不自然なものだけ sentence_flags へ書く。判定は既定で gpt-5.6-luna（SENTENCE_JUDGE_PROVIDER / SENTENCE_JUDGE_MODEL で変更、SENTENCE_AUDIT_MAX=0 で無効化）。

functions/go/sentence_audit_test.go
監査対象の抽出条件（premium限定・本文必須）、間引き、束分けのテスト。

functions/go/sentence_audit_live_test.go
judgeを実際に叩くdry run。実Firestoreの直近の例文、または cmd/sample の出力JSONを判定して結果を出力する（sentence_flagsには書かない）。

functions/go/internal/quality/judge.go
例文品質judgeのプロンプト・スキーマ・sentence_flags ドキュメントの組み立て。判定基準は与えず、タイ語・訳文・key_wordだけ渡して理由を書かせる。

functions/go/internal/quality/judge_test.go
judgeレスポンスの選別（natural除外・理由なし除外・index重複）とドキュメント内容のテスト。

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

functions/go/internal/sentence/prompts.go
prompts.py の Go 版（ロジック）。難易度・長さヒント・テーマゲート・各種制約ブロック。

functions/go/internal/sentence/prompts_data.go
prompts.py の文字列データ（組み立て済みシステムプロンプト含む）の自動生成。手で編集しないこと。

functions/go/internal/sentence/build_prompt.go
プロンプト本体の組み立て。抽選済みの値を受け取るので決定的。

functions/go/internal/sentence/prompts_golden_test.go
プロンプト全文・システムプロンプト・制約ブロックをPython実装とバイト単位で突き合わせる。

functions/go/internal/sentence/service.go
sentence_service.py の純粋ロジック。ๆ の空白詰め・ターゲット語検証・分かち書き崩壊の修正・再生成プロンプト。

functions/go/internal/sentence/service_golden_test.go
sentence_service.py / word_gap.py の純粋ロジックをPython実装と突き合わせる。

functions/go/internal/wordgap/wordgap.go
word_gap.py の Go 版。word_breakdownの欠落検出と補完結果の差し込み。

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

functions/go/internal/sentence/types.go
例文と word_breakdown の型。LLMレスポンスmapからの読み込み。

functions/go/internal/sentence/generate.go
例文生成のフロー。target_notesの展開・NLP後処理・欠落補完・やり直しの制御。

functions/go/internal/sentence/generate_golden_test.go
生成フローとNLP後処理をPython実装と突き合わせる差分テスト。

functions/go/internal/thainlp/enrich.go
word_breakdownへの音節分割・発音・品詞の付与（nlp.py:enrich_with_nlp）と品詞ラベルの英訳。

functions/go/internal/sentence/resolve.go
生成パラメータの確定（テーマ候補のゲート・時制と関係の抽選・サブテーマ選出）。

functions/go/internal/sentence/resolve_golden_test.go
resolve_generation_params の確定部分をPython実装と突き合わせる。

functions/go/internal/bldrama/bldrama.go
BLドラマ回の専用プロンプト断片。参考セリフの選出（embedding／ランダム）と断片の組み立て。

functions/go/internal/bldrama/data.go
BLドラマの設定・セリフ75件（自動生成。gen_bldrama.pyが出力）。

functions/go/internal/bldrama/golden_test.go
bl_drama.py とプロンプト断片・データを突き合わせる差分テスト。

functions/go/internal/uvm/session.go
key_word候補のランク帯算出・テーマembeddingでの絞り込み・重み付き抽選（uvm.py:get_session_words）。

functions/go/internal/uvm/exposure.go
例文に出た語の露出をUVMへ記録する（uvm.py:register_exposure / get_sentence_words）。

functions/go/internal/uvm/session_golden_test.go
uvm.py の選定・露出まわりと突き合わせる差分テスト。

functions/go/internal/uvm/session_band_test.go
KeyWordBand（帯の下端＝境界）と capBand / capCandidates のテスト。

functions/go/internal/uvm/estimate_test.go
EstimateVocab のテスト。証拠が無ければ動かさない・0からと測定値からで挙動が同じ、を固定する。

functions/go/vocabtest_session_test.go
語彙テストのセッションdocの往復（選択肢の保存と、同じ段の再送）のテスト。

functions/go/internal/uvm/scoresim_test.go
語彙テストの測定精度シミュレーション（SIM=1 で実行）。段の階段・1段の問題数・通過本数・世界側の推測率/slip を差し替えて誤差と到達率を比べる。TestStages 等を触る前に回す。

functions/go/internal/uvm/irtsim_test.go
IRT（3PL・θ=logランク・適応出題）で測った場合の精度を、いまの階段と同条件で比べるシミュレーション（SIM=1）。世界モデル（pKnowの形）を線形/logで差し替えられる。本番コードは使わない検証専用。

functions/go/internal/uvm/downsim_test.go
「下振れは許容し上振れだけ抑える」前提で、階段のゲート/内挿率と IRT の c を掃き出すシミュレーション（SIM=1）。指標は全世界での上振れp90・下振れp10・世界ごとの中央値。

functions/go/internal/uvm/matrixsim_test.go
受験有無 × まとめクイズ着手・放置の4セルで estimated_vocab の90日推移を比べるシミュレーション。母数の絞り方とヒント常用時の比較も含む。更新則・新語 prior・世界側の推測率/slip を差し替えるつまみを持つ。

functions/go/internal/uvm/dropsim_test.go
例文生成のたびに estimated_vocab が落ちる現象の再現と、前方帯の変更・回答済みのみを母数にする案の比較。

functions/go/internal/uvm/alphasim_test.go
P 更新則の比較シミュレーション（尤度比 vs 旧 α 則 vs 不正解α強化）。世界側の推測率・slip を振って、推定誤差と「実際は知らないのに P>0.5 の語」の割合を測る。

functions/go/internal/uvm/migratesim_test.go
旧 α 則で溜まった doc を引き継いで新更新則へ切り替えたときの estimated_vocab の推移。切替時に飛ばないこと、その後の補正が緩やかなことを確かめる。

functions/go/internal/uvm/graded_test.go
IsGradedResult（採点区分）・ResultEvidence・UpdateP の向き（正解で上がり不正解で下がる）と、evidence を持たない既存 doc の移行のテスト。

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

functions/go/generate_thai_sentence.go
generateThaiSentence（callable）。認証・クォータ・トライアル判定・生成・保存・UVM更新。

functions/go/cmd/sample/main.go
ターゲット語・語彙帯・テーマを指定して本番と同じ経路で例文を量産する ablation 用コマンド。Firestore を通さず LLM だけ叩く。

functions/go/generate_thai_sentence_golden_test.go
sentence_handlers.py のクォータ・トライアル・生成条件と突き合わせる差分テスト。

scripts/sample_sentences.py
旧プロンプト検証スクリプト。functions/python の削除で動かない。後継は functions/go/cmd/sample。

scripts/ga4_quiz_offer_experiment.py
1問確認クイズ導線A/BテストのGA4ファネルを実験群別に集計する。

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

scripts/sim_scan_floor.py
key_word帯の後方下限・読み取り上限のシミュレーション（取りこぼし率・境界との差・Firestore読取数）。

scripts/build_vocab_test_items.py
語彙テストの出題語（vocab_test_items_<lang>.json）をGeminiで作りGCSへ上げる。段の定義は uvm.TestStages と揃える。

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
prod GA4 のイベント／ユーザースコープのカスタムディメンションとカスタム指標を、実装スキーマに対して plan／check／apply／list する（登録は遡及しない）。

scripts/ga4_funnel.py
prod GA4 の Activation Funnel を Data API の閉鎖型ファネルとして集計。各イベントの独立ユーザー数ではなく、順番どおり到達したユーザーの遷移率と離脱数を表示する。

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


test/presentation/screens/vocab_test_screen_test.dart
語彙テスト画面の進行（段の連結・わからない・free の断り文言・あとで）のテスト。

test/presentation/widgets/premium_trial_ended_dialog_test.dart
体験終了ダイアログが語彙スコアの落差を出す条件（測定値が free 上限超のときだけ）のテスト。

## X 自動投稿

tools/x_post/README.md
X（@everydaythai775）へ毎日の例文を自動投稿する仕組みの全体像と、必要なシークレットの手順。

tools/x_post/pick_sentence.py
GCSのfree例文バンクから未投稿を1件選び、投稿本文を組む。投稿済みは x_post/posted.json で管理。

tools/x_post/synth_tts.py
Google Cloud TTS（th-TH）で例文の読み上げ音声を作る。通常速度→間→ゆっくりの1本。

tools/x_post/build_media.py
screen.png をX上限の4枚以内に均等分割し、1枚目＋音声を ffmpeg で mp4 にする。

tools/x_post/post_to_x.py
Xへ投稿し、投稿済みをGCSへ記録する。動画→画像→テキストの順に自動で退避する。

tools/x_post/fetch_fonts.sh
スクリーンショット描画に使う日本語フォントを取得する（リポジトリには置かない）。

test/screenshots/x_post_screenshot.dart
DetailScreen を flutter_test 上で描画してPNGに落とす。`_test.dart` ではないので通常の `flutter test` では走らない。

.github/workflows/post-daily-x.yml
毎日07:00 JSTに上記を通しで実行するワークフロー。dry_run で投稿せず確認できる。

## E2E (Maestro)

.maestro/smoke.yaml
起動〜3タブ遷移のスモークフロー。シミュレータ上の実アプリを座標/テキストで操作する。

.maestro/README.md
Maestroの実行手順（起動コマンド、studio、スクショの出力先）。
