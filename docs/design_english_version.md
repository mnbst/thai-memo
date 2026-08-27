# 英語版の設計

## 方針

単一アプリ・単一バンドルID・単一Firebaseプロジェクトのまま、**言語設定を1つだけ**持つ。
`app_language: 'ja' | 'en'` が UI文言と学習コンテンツ（訳文・単語の意味・クイズ解説・通知本文）の
両方を決める。UI言語と訳文言語を別々に設定できるようにはしない。

言語は**ダウンロード元のストア地域**だけで決まる（下記 1.1）。**製品ビルドでは変更できない。**

2026-08-07 に設定画面の言語切替を製品ビルドから外した。訳文は生成時の言語で保存され、
切り替えても履歴は書き換わらない。切替を許すと1つの履歴に日英が混在し、例文と訳の整合が
取れなくなる。

- 導線は `AppConfig.isDev` で閉じている。**dev ビルドでだけ**設定 → 表示 → 言語（dev専用）
  から切り替えられる。実機で英語UIを確認する手段がこれしか無いため残している
  （ストア地域は端末の Apple ID / Google アカウントに紐づき、開発中に切り替えられない）。
- ゲートを外す変更は `test/core/dev_only_language_switch_test.dart` で止める。
- **製品ビルドでは判定を外しても直す手段が無い。** 唯一の回復策はアプリの削除・再インストール
  （SharedPreferences はアプリ削除で消える。ただしバックアップから復元すると値ごと戻る）。
  判定失敗率は GA4 の `app_language_resolved`（`storefront=unknown` の比率）で見る。

---

## 1. 言語設定の保持場所

### 1.1 初期値の決定（初回起動時のみ）

**既定は ja。日本以外のストアだと確認できたときだけ en に倒す。**

```
storefront が JPN/JP  →  ja
それ以外              →  en
取得失敗              →  ja（既定のまま）
```

端末ロケールは**使わない**。ロケールで判定すると海外在住の日本語話者が ja 側に入り、
日本市場のセグメントに混ざるため。判定軸はダウンロード元のストア地域に一本化する。

- **取得方法**: `InAppPurchasePlatform.instance.countryCode()`。`in_app_purchase` は既に依存済みで、
  iOS（`SKStorefront`）/ Android（`BillingConfig`）とも同じAPIで取れる。

**実装上の注意:**

- **iOS は ISO 3166-1 Alpha-3（`JPN`）、Android は Alpha-2（`JP`）を返す。** 正規化が必要。
  どちらか片方だけ見ていると全滅するので、判定は `{'JP', 'JPN'}` の集合で持つ。
- `countryCode()` は非同期でストア接続が要り、失敗時は空文字。**初回描画をブロックしない**こと。
  設定の初期化待ちに相乗りさせ、短いタイムアウト（3秒）で打ち切る。
- **失敗時は ja に留まる**（＝現行ユーザーの挙動が変わらない安全側）。代わりに英語圏の
  ユーザーが日本語で起動しうるので、失敗率は GA4 で観測する
  （イベント `app_language_resolved` の `storefront=unknown` の比率）。
- 厳密には「DL元」ではなく「現在のストアアカウント地域」。**初回起動時に1回だけ**読むので
  実質DL時点の地域と一致する。2回目以降は読まない（SharedPreferences の値が真実）。

### 1.2 保持場所

| 場所 | 何を持つ | 用途 |
|---|---|---|
| `settings_provider`（SharedPreferences） | `appLanguage` | UI描画・CF呼び出し時の引数 |
| `users/{uid}.app_language`（Firestore） | 同じ値を非正規化 | サーバー起点処理（毎日例文配信・FCM本文） |

- クライアント起点の callable（`generateThaiSentence` / `generateQuiz`）は **リクエストに `lang` を渡す**。
  users doc を読みに行かないので設定変更が即座に効く。
- users doc への書き込みは `push_notification_service` のタイムゾーン登録と同じ経路に相乗りさせる。
- **後方互換**: `lang` が無いリクエストは `ja` として扱う（旧クライアント保護）。

---

## 2. UI文言（Flutter）

`flutter_localizations` + `gen_l10n`（ARB）を導入。現状 l10n の仕組みは一切入っていない。

- `l10n.yaml`, `lib/l10n/app_ja.arb`, `lib/l10n/app_en.arb`
- `MaterialApp` に `localizationsDelegates` / `supportedLocales` / `locale`（設定に追従）
- 対象は lib 配下 52ファイルのハードコード日本語。ただし `thai_tone_analyzer.dart` のように
  **コメントだけが日本語のファイルは対象外**（実質の文言ファイルはこれより少ない）。

見落としやすい文言:

- `lib/core/constants/loading_tips.dart` — ヒント全文
- `lib/core/constants/generation_constants.dart` — クォータ超過メッセージ
- `lib/presentation/widgets/topic_picker.dart` — テーマ表示ラベル（後述、内部値は日本語のまま）
- `purchase_service.dart` / `subscription_provider.dart` — 課金エラー文言
- `tone_guide_screen.dart` / `tone_explanation_dialog.dart` — 声調解説（分量が多い）
- `home_screen.dart` のサンプル例文（`japaneseTranslation: 'こんにちは（男性の場合）'`）

非文言のロケール依存: 日本語向けフォント指定（`google_fonts`）、日付フォーマット。

---

## 3. コンテンツ生成（Python CF）— ここが本体

### 3.1 データモデルは名前を変えない

`japanese_translation` は SQLite列名・Firestoreフィールド・JSONスキーマ・Dartモデルに
広く散っている（lib+functions で158箇所）。**フィールド名は据え置き、意味を
「ユーザーの母語訳」に再定義する**のが最小コスト。`translation` へのリネームは
DBマイグレーション＋旧クライアント互換の負担に見合わない。

- Dart側だけ表示層の呼び名を揃えたければ `String get translation => japaneseTranslation;` を足す（任意）。
- `sentences` テーブルに `lang TEXT DEFAULT 'ja'` 列を追加する（`AppConfig.databaseVersion` +1、
  `_onUpgrade` で `ALTER TABLE`）。表示制御には使わないが、言語切替後に履歴が混在するため
  後から分析・フィルタしたくなる。安いので今入れる。

### 3.2 プロンプト（`functions/go/internal/sentence/prompts.go`）

`lang` パラメータで分岐する。**日本語ルールを英訳して移植してはいけない**。
現行の訳文ルール（手順形式の訳出、過剰特定の抑制、会話語彙の選択…）は
日本語に対して実測で効くと確認したものであり、英語では前提が違う。

英語側は新規に書き起こす。起点として必要になるのは:

- 訳文の作り方を「確認せよ」ではなく**作る順序**で書く（この形式自体は言語非依存で効くと実証済み）
- タイ語の語順・品詞をなぞった翻訳調にしない
- 三人称 `เขา` は性別不定 → 既定は `they`（日本語版の「性別の過剰特定」問題の英語版）
- 丁寧語の終助詞 `ครับ / ค่ะ` を訳文に出さない

検証は `scripts/sample_sentences.py` に `lang` を通してローカル生成で回す（デプロイ不要）。
ルールを足すたびに ablation で効果を確認する運用は ja と同じ。

### 3.3 その他の Go 側

| 対象 | 対応 |
|---|---|
| `internal/sentence/constants_data.go` のレスポンススキーマ | `description` を lang 別にする |
| `internal/thainlp/posjapanese.go` | 品詞ラベル辞書を ja/en 2本にする |
| `internal/wordclass/classes_data.go` のルール文 | LLMへの指示なので日本語のままでよい。ただし「日本語訳では〜」と訳文に言及する行だけ lang 別に出し分け |
| `TOPICS` / `SUBTOPICS` / `STYLES` | 内部識別子は日本語のまま。プロンプトにもそのまま入れる。表示のみクライアントでマッピング。サーバーが返す `context.topic` も日本語キーなのでクライアント側で訳す |

### 3.4 free 例文バンク（最大の落とし穴）

free ティアは GCS の `free_sentences.json`（事前生成・日本語訳込み）から引く。
ここを対応しないと、**英語ユーザーの free 体験がまるごと日本語訳になる**。

- Goの例文生成経路で `free_sentences_en.json` を生成
- `get_free_sentences(lang)` / `pick_free_sentence(word, lang)` でファイル切替
- `scripts/upload_corpus.sh` に en バンクを追加

---

## 4. クイズ生成（Go CF）

`quizGenerationService.ts` のプロンプトが日本語固定（`explanation` / `dummy_reasons` の
生成指示とスキーマ description）。callable 引数に `lang` を追加して分岐。
`constants/defaultQuizQuestions.ts`（フォールバック）の en 版も必要。

---

## 5. 毎日例文の通知（Python CF）

`daily_sentence_handlers.py` の FCM 本文を `users.app_language` で切替。
free 経路は 3.4 のキャッシュに依存するため、en バンクが揃うまで英語ユーザーへの配信は出さない。

---

## 6. TTS・発音

タイ語 TTS はそのまま流用できる。`pronunciation.py` のローマ字発音も英語話者に使える。
声調ガイドは文言の翻訳のみ。

**要検証**: 英語圏の学習者はローマ字転写の体系（RTGS / Paiboon 等）に好みがあり、
現行の独自表記が受け入れられるかは実ユーザーで確かめる必要がある。v1では変更しない。

---

## 7. 課金・ストア

- 商品ID・価格は共通のまま。paywall 文言は ARB へ。
- App Store Connect / Play Console に**英語ロケールのメタデータとスクリーンショットを追加**。
  別アプリにしないので既存の審査実績・評価をそのまま引き継げる。

### アプリ名（ホーム画面のアイコン）

**アイコン名だけは端末の表示言語で決まる。ストア地域では出し分けられない。**
iOS が `InfoPlist.strings` を選ぶ軸が端末言語しかないため、アプリ内で使っている
ストア地域ルールをここへ適用する方法が無い。

- `ios/Runner/{ja,en}.lproj/InfoPlist.strings` の `CFBundleDisplayName`
  （ja=まいにちタイ語 / en=Daily Thai）。`project.pbxproj` に PBXVariantGroup として登録済み。
- **ズレは仕様として許容する。** 英語端末＋日本ストア → アイコンは "Daily Thai"、UI は日本語。
  逆も起きる。多数派（英語端末＝海外ストア）では一致する。
- App Store の**掲載名**はこれとは別で、App Store Connect のローカライズで
  地域ごとに設定できる。こちらは正しく分けられる。
- Android の `android:label` は未対応（現状「まいにちタイ語」固定）。

---

## 8. 分析

GA4 に user property `app_language` を追加。
**カスタムディメンションの登録は実装と同時に行う**（登録前のデータは `(not set)` で遡及しない）。
`scripts/ga4_acquisition.py` / `ga4_funnel.py` に言語ディメンションを足す。

---

## 段階リリース

**英語訳の品質は v1 のリリース条件にしない。** 「英語で読める訳が返る」を通過点とし、
自然さの作り込みはリリース後に実データを見てから回す。品質を先に詰めると、
測る基準（下記「未解決」）が無いまま無限に時間が溶ける。

| Phase | 内容 | 完了条件 |
|---|---|---|
| 1 | 言語設定 + l10n 骨組み + `users.app_language` 保存 | ja の挙動が完全に不変（**済**） |
| 1.5 | lib 配下の全画面 ARB 化 | 英語UIで一通り操作できる（**済**） |
| 1.6 | `lang` を各CFへ伝播（サーバーは受け取るだけ） | 旧クライアント互換を保つ（**済**） |
| 2 | `prompts.py` の en ブロック（最小）/ schema / 品詞ラベル / クイズ en | en で構造的に妥当な訳が返る。**自然さは問わない**（**済**） |
| 3 | `free_sentences_en` 生成 | free の英語ユーザーに英訳が返る |
| 4 | 通知 en + ストア英語メタデータ + GA4 ディメンション | リリース |
| 5（リリース後） | 英語訳の品質改善 | 監査基準を定義してから ablation で回す |

Phase 2 の「最小」の中身は 3.2 の4項目のみ。ここにルールを足したくなっても
**観測された違反以外は入れない**（予防的ルールは語彙を注入して逆効果になる）。

---

## 未解決

- **英語訳の品質をどう測るか。** `sentence-quality-audit` スキルの監査基準は日本語訳前提。
  Phase 5 の着手時に en 用の基準を定義する。リリースはブロックしない。
- 発音表記の体系（上記6）。

---

## 実装メモ（2026-08-07 時点）

### 訳さないもの

サーバーへ送る値・prefs に保存する値は**日本語の識別子のまま**にしてある。表示だけを
差し替える。ここを訳すとサーバー側のプロンプトや保存済みデータと食い違う。

| 識別子 | 実体 | 表示ラベル |
|---|---|---|
| `GenerationConstants.topics` / `styles` ほか | プロンプトへそのまま入る | `core/constants/generation_labels.dart` |
| 語彙レベル（`入門`〜`上級`） | prefs `last_vocab_level` の値・閾値判定のキー | `vocabLevelLabel()` |
| `SentenceContext.getFullExplanation()` | `context_explanation` としてサーバーに保存する値 | （表示に使っていないので未対応） |

### 文言の引き方

- ウィジェット: `L10n.of(context)`
- provider / service: `l10nProvider`（`core/l10n/l10n_provider.dart`）を
  `L10n Function()` として注入する。値で持つと言語切替に追従しない。

### `lang` の伝播（Phase 1.6）

クライアント → CF は `lang` を**リクエスト直下**に載せる（`generateThaiSentence` /
`generateQuiz` / `generateLearningQuiz`）。

- `BackendApiService` は `String Function() lang` を受ける。値ではなく供給関数なのは
  設定画面での切替を次のリクエストから効かせるため。既定は `'ja'` なので、
  供給しない呼び出し元（`settings_screen` の `resetLearningData` など）は挙動が変わらない。
- サーバーは正規化だけする。**未知の値・欠落はすべて `ja`** に倒す
  （`constants.resolve_lang` / `utils/lang.ts` の `resolveLang`。両者は同じ規則、片方を
  変えたらもう片方も変えること）。日本語ユーザーに英訳が返る事故のほうが害が大きい。
- Python は `lang` を `_effective_generation_params` で params から**除去する**。
  残すとプロンプトの条件ブロックに未知のキーとして流れ込む。
- 現状は**ログに出すだけ**で生成には反映しない。英語リクエストの実数を Phase 2 の前に測る。

### 生成の言語分岐（Phase 2）

**分岐するのは訳文・解説に面する部分だけ。** タイ語の構文ルール（語順・否定・
ターゲット語の入れ方・語クラス・レジスタ、クイズの NG 例）は thai_text 自体の規則で
言語非依存なので共有する。ここを言語ごとに複製すると片方だけ直して他方が腐る。

| 分岐する | 場所 |
|---|---|
| 訳文の手順ブロック | `prompts.TRANSLATION_STEPS`（`EN_TRANSLATION_STEPS` は新規。英訳移植ではない） |
| 訳文ルール・訳語のレジスタ | `prompts._TRANSLATION_RULES` / `_TRANSLATION_REGISTER_RULES` |
| 出力フィールドの言語 | `constants.build_response_schema(lang)` の description **のみ** |
| 品詞ラベル | `nlp.localize_pos`（固定語彙なので直訳） |
| クイズの解説・ダミー理由 | `quizGenerationService.quizGenerationSystemPrompt(lang)` / `quizResponseSchema(lang)` |

**出力フィールドの言語はスキーマの description だけで決まる。** プロンプト本文に
言語指定を足しても効果が無いことを 12文×3条件で確認済み（`prompts.py` の不採用コメント）。
足すと他のルールが薄まるだけなので入れない。

**注意点:**

- ja のプロンプトは1文字も変えていない。free と premium で助詞前の空白が1文字違う
  箇所まで含めて `tests/test_prompts_lang.py` / `quizGenerationLang.test.ts` で固定した。
- クイズの `dummy_reasons` は「語（ローマ字 / 意味）：理由」の形を崩せない。
  `extractDummyPronunciation` がここから選択肢の発音を切り出しており、崩すと
  4択の発音表示が空になる。en も同じ括弧＋スラッシュを使う。
- クイズの禁止表現リストは生成物への検査語なので、**出力言語の文字列**でないと機能しない。
  日本語ルールの英訳移植ではなく、同じ逃げ道を英語で塞いだもの。
- free 例文バンクは日本語訳込み。en では引かず必ず LLM で生成する（設計 §3.4）。
  毎日配信の free 経路（`cache_only`）で en なら配信しない。

### 積み残し

- `backend_api_service.dart` の3つの例外メッセージが日本語のまま。いずれも上位層で
  言語に沿った文言へ置き換わるが、`errUnexpected` 経由でまれに素通りしうる。
- 英語文言は未検証（実機で見ていない）。長い英語見出しでの折り返し崩れは
  `quiz_offer` の1件だけ実測で直した。他は未確認。
- **en の訳文品質は未測定**（Phase 5）。12文の目視で `พี่`→"My brother" の
  性別・血縁の過剰特定、thai_text に無い "thank you for helping" の足し訳を確認。
  リリースはブロックしない。
- **en のクイズは1問も生成していない。** プロンプト・スキーマの分岐を入れただけで、
  実出力を見ていない。`dummy_reasons` の書式（発音の切り出し）が英語で崩れないかは
  実測で確かめること。
