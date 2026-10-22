# 韓国語版の設計

英語版（`docs/design_english_version.md`）の仕組みに `ko` を3つ目の言語として足す。
方針（言語は1つだけ持つ・ストア地域で決める・製品ビルドでは変えられない）はそのまま引き継ぐ。
ここには英語版との差分だけを書く。

## 方針

- `AppLanguage` / `lang.Lang` に `ko` を足す。UI文言と学習コンテンツ（訳文・単語の意味・
  クイズ解説・通知本文）を韓国語にする。
- 韓国ストア（iOS `KOR` / Android `KR`）だけを `ko` にする。それ以外の海外ストアは今までどおり `en`。
- 言語判定は**初回起動時の1回だけ**なので、すでに入れている韓国ストアのユーザーは `en` のまま。
  移行はしない（履歴の訳文が英語で保存済みのため、切り替えると日英韓が混ざる）。

## 1. リリース順（最大の落とし穴）

サーバーの `lang.Resolve` は**未知の値を `ja` に倒す**。サーバーより先に `ko` を送るクライアントを
出すと、韓国ユーザーに**日本語訳**が返る。

```
1. サーバー: ko を受け付け、ko の訳文を返す（Phase 2）を先にデプロイ
2. クライアント: storefront KR/KOR → ko を出す
```

Python の `constants.resolve_lang` / JS の `utils/lang.ts` の `resolveLang` も同じ規則
（`lang.go` 冒頭）なので、残っていれば同時に直す。

## 2. クライアント（Flutter）

| 対象 | 対応 |
|---|---|
| `lib/core/l10n/app_language.dart` | `ko` を追加。`displayName` は `한국어`。`fromStorefront` で `{'KR','KOR'}` → ko |
| `lib/l10n/app_ko.arb` | 新規。**文言は Codex で作る**（下記 2.1） |
| `ios/Runner/ko.lproj/InfoPlist.strings` | `CFBundleDisplayName`（アプリ名）。`Info.plist` の `CFBundleLocalizations` と pbxproj にも足す |
| 日付・数値 | `intl` のロケールが `ko` になるだけ。表示崩れは実機で見る |
| フォント | ハングルは Thai 用フォントに無いので端末フォントに落ちる。問題なければ対応しない |

テスト: `test/core/` の `fromStorefront` テストに KR/KOR を足す。

### 2.1 文言の作り方

- `app_ja.arb` を原本にして Codex（`codex exec`）に `app_ko.arb` を書かせる。英語からの重訳はしない。
- 指示に入れること: placeholder・ICU plural/select をそのまま残す／`@` メタデータは訳さない／
  タイ語・ローマ字の例は変えない／UIは 해요체、ボタンは短い名詞形／アプリ名は 매일 태국어。
- 出力後に `flutter gen-l10n` と `flutter analyze`、キーの過不足チェックを通す。
- 長い見出しの折り返しは実機（dev の言語ピッカー）で見る。

## 3. サーバー（Go CF）

`lang.EN` で分岐している箇所（66か所）を `ko` でも通す。

| 対象 | 対応 |
|---|---|
| `internal/lang/lang.go` | `KO` を追加。`Resolve` / `Parse` / `IsWrongLanguage`（ハングル判定） |
| `internal/sentence/prompts_data.go` | `ko` ブロックを新規に書く（下記 3.1） |
| `internal/gemini/schema.go` | 出力フィールドの description を ko 別に |
| `internal/sentence/constants.go` | `LocalizeContext`（テーマ等の表示ラベル）の ko |
| `internal/thainlp/enrich.go` | 品詞ラベルの ko |
| `internal/quizgen/prompt.go` | 解説・ダミー理由の ko。`dummy_reasons` の「語（ローマ字 / 意味）：理由」の形は崩さない |
| `quiz_word_order.go` / `quiz_spelling.go` | en と同じ分岐に ko を足す |
| `internal/dailysentence/notification.go` | 通知タイトル・セット件数の ko |
| `internal/sentence/drift.go` / `quizgen/drift.go` | `driftLanguageName` に `韓国語` |
| `internal/quality/rules.go` / `judge.go` | 訳文の検査語を ko でも持つ（JAOnly の扱いは en に合わせる） |

### 3.1 プロンプト

英語版と同じく、**日本語・英語のルールを韓国語へ移植しない**。始めに入れるのは次だけにし、
それ以外は観測された違反が出てから足す（`prompt-effect-ledger` を先に読む）。

- 訳文の作り方を**作る順序**で書く（言語によらず効くと確認済みの形）
- タイ語の語順をなぞった翻訳調にしない
- 文の丁寧さの差は、文末の語尾（해요체 / 반말）で表す。`ครับ / ค่ะ` を単語として訳文に出さない
- 三人称 `เขา` は性別を決めない（그 사람 / 그）
- 人名・あだ名はハングルで書く。訳文にタイ文字・ローマ字を残さない

検証は `functions/go/cmd/sample` に `lang=ko` を渡してローカル生成で回す。品質はリリース条件にしない（英語版と同じ）。

### 3.2 例文バンク

`free_sentences_<lang>.json` / `corpus_sentences_<lang>.json` / `corpus_pool_<lang>.json` は
言語ごとのファイルなので、ko のファイルが無ければ LLM 生成に回る（英語版の当初と同じ）。
free 経路と毎日例文の `cache_only` 経路は、ko バンクが揃うまで ko では配信しない。

**ko のプール・バンクは ja と同じタイ語の文を使い、訳だけ韓国語にする**（2026-10-22 決定）。
訳は `scripts/ko_bank_translate.py` で Codex に書かせる（fetch → prepare → translate → merge → upload）。
ja に無い文は ko にも無い。ja に後から足された文（pool review の OK）は、同じ手順を回すと
既存の ko に無いものだけ訳して足す。

- 訳すのは訳文・語義・語の補足・使用場面・文化メモ・感情。topic・style・grammatical_role は
  日本語のキーのまま残し、配信時に差し替える（`localizeBanked`）。
- 1バッチ100本だと Codex が1件ずつ訳さず、定型文とスクリプトで埋めた。40本にし、
  「スクリプトで訳を作らない」と指示し、定型文・句点抜け・複数の語義を検査で落とす。

## 4. ストア・分析

- App Store Connect / Play Console に `ko` のメタデータ（名前・サブタイトル・説明・キーワード）と
  スクリーンショット。商品ID・価格は共通。
- GA4 の `app_language` はそのまま `ko` が入る。追加の登録は不要。

## 段階リリース

| Phase | 内容 | 完了条件 |
|---|---|---|
| 1 | `AppLanguage.ko` + `app_ko.arb`（Codex）+ iOS アプリ名。storefront 判定はまだ入れない | dev の言語ピッカーで韓国語UIを一通り操作できる |
| 2 | サーバーの ko（lang / プロンプト / スキーマ / 品詞 / クイズ / 通知） | ko で韓国語の訳が返る。自然さは問わない |
| 3 | storefront KR/KOR → ko をクライアントに入れてリリース（Phase 2 のデプロイ後） | 韓国ストアの新規ユーザーが ko で起動 |
| 4 | ko の例文バンク・ストアメタデータ | free の韓国ユーザーに韓国語訳が返る |
| 5（リリース後） | 訳文品質の改善 | 監査基準を決めてから回す |

---

## 実装メモ（2026-10-22 時点）

### Phase 1（済）

- `AppLanguage.ko`、`lib/l10n/app_ko.arb`（Codex 作成、1,083キー）、`ios/Runner/ko.lproj/InfoPlist.strings`。
- `fromStorefront` はまだ触っていない（ko は dev の言語ピッカーからだけ選べる）。

### Phase 2（済・未デプロイ）

**ja 以外を en とみなす分岐を残さない。** `l != lang.EN → ja` や `l != lang.Default → 英語の description`
のような書き方だと、ko は黙って ja か en に倒れる。言語別の表（`map[lang.Lang]…`）を引き、
表に無い言語だけ ja に倒す形にそろえた。

| 対象 | 形 |
|---|---|
| context ラベル | `sentence.contextLabelsByLang`（`constants_data_ko.go` は Codex 作成） |
| スキーマ description | `sentence.schemaDescriptions` / `contextDescriptions` |
| 品詞ラベル | `thainlp.posLabels` |
| クイズ指示 | `quizgen.supported()` が表に無い言語を ja に倒す |
| 書き直し指示 | `driftLanguageName` / `repairLanguageName` に無い言語を ja に倒す |
| 品質判定 | `JAOnly` の観点は ja（と lang 未設定）だけに聞く |
| 言語ずれ検出 | `lang.isWrongKorean`：仮名・漢字・キリル文字が混ざるか、ハングルが1文字も無い |

ja のプロンプトは1文字も変えていない（golden test のまま通る）。
`lang_ko_test.go` ほかで「ko が ja に倒れていない」「ko のラベル表が en と同じキーを持つ」ことを固定した。

スモーク（`cmd/sample -lang ko`、dev、premium 8 + free 4）: 12/12 で訳文・語義・品詞・
テーマ表示が韓国語。訳のずれは目視で 2件（ภูมิใจ→「마음에 들었는데」、条件の「있으면」の足し訳）。

### 積み残し

- **ko のクイズは1問も生成していない。** `dummy_reasons` の書式から発音を切り出せることは単体テストで確認しただけ。
- `vocab_test_items_ko.json`（語彙テスト）を GCS に上げる。無いと ko の語彙テストが失敗する。
- BLドラマ回の名前の表記（`bldrama.namesNote`）は ja/en しか指示していない。ko では
  ハングル・英字が揺れうる。ja のプロンプトを変えずに出し分けるには言語を引数に取る必要がある。
- `corpustrans` / `corpususage`（静的コーパスの訳と使い方の一括生成）は ja/en 固定。Phase 4 で ko を足す。
- `target_notes` が 12本すべてで空だった。ja でも同じか未確認。
