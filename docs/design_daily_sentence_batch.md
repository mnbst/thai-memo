# 毎日例文の5本セット配信 設計

## 背景（実データ）

prod Firestore 直近60日、アクティブ58人・274ユーザー日。

- 1日の生成本数は **1本のみ 54.0%** と **5/10/20本（上限張り付き）** の二極。
  ちょうど3本の日は 2.2% しかない。
- 1本のみの日は生成時刻が 10時36%・8時18%・12時16% に集中し、free 107 / premium 41。
  実体は**配信された1本を見て終わり**の日。
- 複数生成する日は連続タップで、同日内の生成間隔は中央値1.4分・89.5%が10分以内。

つまり「例文N本ごとにまとめクイズ」という区切りは、過半のユーザー日で**一度も成立していない**。
配信の時点で5本渡せば、過半の日で 例文→確認クイズ→まとめクイズ が1回完結する。

## 方針

1. `deliverDailySentence` は1回の配信で**例文を5本**作って書き込む。通知は1通のまま。
2. まとめクイズの間隔を **3本 → 5本に戻す**（`summaryQuizThreshold`）。
   1本/日だった頃は5本だと一巡に5日かかったので3本へ下げたが（commit a66ba61）、
   5本セットなら**1日で一巡が返る**ため前提が変わる。配信セット＝1サイクルで一致させる。
3. 本数は **users/{uid}.app_version でゲート**する。5本セットを扱えない旧版には従来どおり1本。
4. クライアントは5本を1セットとして順に消化し、5本目の確認クイズの後にまとめクイズへ進む。
   例文画面に「1 / 5」を出し、サイクルを可視化する。

## 1. バージョンゲート

`app_version` / `app_build_number` は `lib/services/app_version_reporter.dart` が起動時に
users doc へ書いている（firestore.rules の拒否リスト対象外）。サーバー側で読むのは今回が初。

対象は **1.4.8 以降**（現在の pubspec は `1.4.7+0`）。

```go
// functions/go/internal/dailysentence/dailysentence.go
var DailyBatchMinVersion = [3]int{1, 4, 8}
const DailyBatchSize = 5

// BatchSize は配信本数。版が読めない・古い場合は1本（安全側）。
func BatchSize(userData map[string]any) int {
    if compareVersion(stringValue(userData["app_version"]), DailyBatchMinVersion) < 0 {
        return 1
    }
    return DailyBatchSize
}
```

**`app_build_number` では判定できない。** pubspec は `1.4.7+0` 固定で、ビルド番号は CI が
`--build-number=${{ github.run_number }}` で注入している（`distribute-test.yml` / `distribute-prod.yml`）。
tester と prod でワークフローが別なので採番系列が独立しており、番号の大小がリリース順序を表さない。
判定は `app_version` の semver 比較（major/minor/patch を整数で比較）で行う。

- パースできない値・未報告ユーザーは1本（安全側）。次回起動で版が入れば次の配信から5本。
- ロールアウトは `DailyBatchMinVersion` を上げ下げするだけで切り替わる。dev → tester → prod。

**旧版に5本送ってはいけない理由**: `DailySentenceService._importDeliveredSentences` は
`daily:true` の未取り込みドキュメントを全部SQLiteへ入れ、**最新の1件だけを返して表示する**。
つまり旧版は5本ぶんのクォータを消費した上で4本が履歴にしか現れない。

## 2. Firestore データモデル

`users/{uid}/sentences/{id}` に3フィールド追加（既存フィールドは変更しない）。

| フィールド | 型 | 内容 |
|---|---|---|
| `daily_set_id` | string | 配信ごとに1つ。1本目の doc ID を流用する |
| `daily_set_index` | int | 0..n-1。表示順 |
| `daily_set_size` | int | 実際に書けた本数（5本目の生成に失敗したら4） |

既存の `daily` / `daily_date` は据え置き。旧クライアントは新フィールドを無視するだけなので後方互換。
1本配信のときも `daily_set_size=1` を書いておくと、クライアント側の分岐が消えて扱いが揃う。

## 3. サーバー実装（functions/go/deliver_daily_sentence.go）

`deliverOne` を「1本」から「n本」へ広げる。構造は変えず、生成・書き込み・ロールバックの単位だけ増やす。

### 3.1 単語選出は1回、例文生成は並列

`SelectTargetWords` は既に `count` 引数を持ち、`uvm.SessionSelector.GetSessionWords` が
重複しない語をまとめて返す。**5語を1回の選出でまとめて取り**、そのあと例文生成だけ並列に回す。

```
words, topic := Selector.SelectTargetWords(..., count = n, ...)   // 排他は選出側が保証
var wg sync.WaitGroup
for i, w := range words {
    go func(i int, w string) { results[i] = produceOne(w, topic) }(i, w)
}
```

- 選出を並列に回すと同じ `key_word` が重複する（各呼び出しが同じ UVM 状態を見るため）。
  ここは1回にまとめるのが正しく、かつ既存APIのままでよい。
- **テーマは語ごとに持たせる**（`TargetWord.Topic`）。散るかどうかは `ChooseTopic` 次第:

  | | テーマ | セット内 |
  |---|---|---|
  | テーマ指定あり | 指定値 | 共通 |
  | free おまかせ | 一様抽選で1つ（テーマが key_word を絞る） | 共通 |
  | premium おまかせ | 語ごとに `FindBestTopic` | **散る** |

  premium だけ語ごとにできるのは、`ChooseTopic` が premium にはテーマを確定せず
  候補プールだけ渡すため。テーマによる候補の絞り込みが無く、語の選定とテーマの決定が
  独立している。free を同じ形にするとテーマ分布が embedding の重心に引きずられて
  BLドラマへ偏る（2026-08-14 実測 82.7%、prod の premium 実測でも 19.2%）。
- **選定は1回にまとめる**。`GetSessionWords` はプールから外しながら引くので1回の
  呼び出しで返る n 語は重複しないが、呼び出しをまたぐ排他は無い。分けて引くと同じ
  `key_word` がセットに2本入る。
- free（`CacheOnly`）は LLM ではなくバンクからの `Bank.Pick`。キャッシュミスした語は
  **使用済みの語を除いて引き直す**（現行の `SelectRetry` ループを語ごとに回す）。
  引き直しても埋まらなければ揃ったぶんだけ配信する。
- 実装は `Producer` に `ProduceBatch(ctx, db, freqRank, req, n) ([]*Produced, error)` を足し、
  既存の `Produce` は `ProduceBatch(..., 1)` の薄いラッパにする。通常生成の経路は挙動不変。

**レイテンシの実測（済）**: `functions/go/cmd/burst` で本番と同じ `sentence.Service` を
gemini-3.1-flash-lite に対して叩いた結果（dev、premium プロンプト、estimated_vocab=800）。

| 条件 | 同時LLM | 1本あたり median / p90 | 1ユーザー max | 全体 | 失敗 |
|---|---|---|---|---|---|
| 現行 5人 × 1本 | 5 | 5.79s / 6.26s | 6.26s | 6.3s | なし |
| **5人 × 5本 並列** | **25** | **5.47s / 6.98s** | **7.58s** | **7.6s** | **なし** |
| 5人 × 5本 直列 | 5 | 5.23s / 5.91s | 25.7s | 27.8s | なし |
| 10人 × 5本 並列 | 50 | 6.62s / 7.24s | 7.66s | 7.7s | なし |

- **並列で問題ない。** 同時50本まで1本あたりの所要はほとんど伸びず、429・5xx ともゼロ。
  `dailySentenceConcurrency = 5` は据え置きでよい。
- 直列にすると1ユーザー26秒、バッチ1周28秒。関数タイムアウト120秒に対して
  配信対象が増えると危うくなるので、**並列が必須**（直列は選ばない）。
- デプロイ済みの `deliverDailySentence`（dev）は timeout 120s / memory 2Gi / maxInstances 10。
  並列5本ぶんのレスポンス保持は 2Gi に対して十分小さい。変更不要。
- prod の配信対象は現在20人（通知ON＋トークンあり）、うち premium 3人。
  同一の配信枠に最大10人だが LLM を叩くのは premium だけなので、
  実運用の同時LLMは最大でも 3人 × 5本 = 15本。実測レンジのはるか内側。

再測は `go run ./cmd/burst -users 5 -per 5`（ベースラインは `-per 1`、直列比較は `-serial`）。

### 3.2 コミット

`commitDailySentence` を n 本対応にする。1トランザクションのまま。

- `tx.Set` を n 回（doc は事前に `NewDoc()` で n 個確保）
- `remaining_sentences` は `Increment(-consumed)`
- `daily_sentence_generated` / `last_notified_at` / `notify_tier` は現状どおり
- `dailyCommitPlan` の戻り値に consumed を足す

**クォータの扱い**: free / premium とも**配信した本数ぶん消費**する（現行の1消費の延長）。

| | 上限 | 配信後の残り |
|---|---|---|
| free | 5本/日 | 0本 |
| premium | 20本/日 | 15本 |

free は配信だけで枠を使い切るが、実データ上 free の自発生成は1〜2本止まりで、
その大半が配信された1本を見て終わる日なので実質的な取り上げにならない。

これに伴う2点:

- **先に自発生成した日は配信が5本に満たない。** free が朝の配信前に2本作っていれば残り3本。
  `min(remaining_sentences, DailyBatchSize)` を配信し、`daily_set_size` に実数を書く。
  実データでは free の生成時刻は配信時刻（8〜12時）に張り付いており、
  配信が先に来る日がほとんどなので影響は小さい。0本のときは配信を見送る。
- **セット消化後の「次へ」は上限到達になる。** これは新しいエラー状態ではなく、
  既存の上限到達表示＋ペイウォール導線（`_quotaPaywallSource = 'sentence_quota_error'`）に
  そのまま落ちる。5本を学び切った直後は「なぜ premium が要るか」が最も伝わる場面なので、
  導線としてはむしろ良い位置になる。新しい文言・画面は作らない。

`deliveryRestoreUpdate` / `rollbackUpdate` の `Increment(+1)` も consumed に揃える。

### 3.3 通知

1通のまま。`Data` を拡張する。

```go
Data: map[string]string{
    "type": "daily_sentence",
    "sentence_id": firstID,        // 旧版はこれだけ見る（従来どおり動く）
    "daily_set_id": setID,
    "daily_set_size": strconv.Itoa(len(picked)),
}
```

本文は1本目の key_word を出す現行の `BuildNotificationText` に「ほか4本」を添える。
l10n（ja/en）に文言を追加。`notification_golden_test.go` の期待値も更新する。

### 3.4 失敗時

- 通知送信失敗・トークン失効 → **n本すべて削除**してロールバック。`rollbackDelivery` を複数 ref 対応に。
- 一部の生成失敗 → 揃ったぶんだけ配信し、`daily_set_size` に実数を書く。0本なら従来どおり `no_sentence`。
- `remaining_sentences` が本数に足りない → 取れるぶんだけ配信（3.2）。0本なら配信を見送る。

### 3.5 UVM

現状は送信成功後に `registerSentenceExposure` を1回。**生成順に n 回**呼ぶ。
`uvm.SyncEstimatedVocab` は最後に1回だけでよい（毎回呼ぶと無駄な読み書きが増える）。

## 4. クライアント実装

### 4.1 取り込み（lib/services/daily_sentence_service.dart）

`sync()` の戻りを `ThaiSentence?` から `DailySentenceSet?` に変える。

```dart
class DailySentenceSet {
  final String setId;
  final List<ThaiSentence> sentences;   // daily_set_index 昇順
}
```

- `_importDeliveredSentences` の取り込みロジック（未取り込みだけ保存）はそのまま。
  返す対象を「最新の1件」から「最新の `daily_set_id` に属する全件」へ変える。
- `daily_set_id` を持たない旧ドキュメントは `setId = doc.id` の1本セットとして扱う。
- 通知タップ経由（`_importDeliveredSentenceById`）は、その doc の `daily_set_id` で同セットを引き直す。
- SQLite 側は `sentences` テーブルにセット情報を持たせない。セットは「今日の配信の並び」でしかなく、
  履歴・クイズ・UVMのどれもセット単位を必要としないため。表示に必要な並びは
  取り込み時のメモリ上の `DailySentenceSet` で足りる。

### 4.2 学習フロー（lib/presentation/screens/home_screen.dart）

`_LearningScreenState` にセットカーソルを足す。

```dart
List<ThaiSentence> _setSentences = const [];
int _setIndex = 0;
static const String _setCursorKey = 'daily_set_cursor';   // 新キー
```

遷移:

```
例文(1/5) → 確認クイズ → 次へ → … → 例文(5/5) → 確認クイズ → まとめクイズ → 完了
```

- 「次へ」がセット内に残りを持つ場合は **`generateSentence` を呼ばない**。
  現在の `_proceedToNextSentence` は無条件に生成を叩くので、セット消化中は
  カーソルを進めるだけの分岐を入れる（クォータもLLMも消費しない）。
- セットを消化しきったら従来どおり自発生成へ落ちる。生成した例文は従来の
  `_completedCount` カウントに乗せ、5本ごとのまとめクイズ判定を継続する。
  free は配信で枠を使い切っているので、ここは既存の上限到達表示になる（3.2）。
- `summaryQuizThreshold` を **3 → 5** に戻す。セット経路では「5本目の確認クイズの後は
  常にまとめクイズ」が既定になるので、判定は
  `_setIndex == _setSentences.length - 1 || shouldOfferSummaryQuiz(_completedCount)`。
- まとめクイズ完了で `_setIndex` と `_completedCount` を 0 に戻す。
- 途中でアプリを閉じた場合は `_setCursorKey` に `setId` と index を保存して復帰する。
  既存のクイズ復元（`_savedConfirmationQuizKey` / `_savedSummaryQuizKey`）と同じ流儀。

### 4.3 進捗の可視化

例文画面の上部に「1 / 5」を出す。`QuizProgressCounter` と同じ意匠を流用し、
クイズ中も同じ位置に出し続ける（クイズ画面は既に「2 / 5」を出している）。
**これが元の課題（サイクルがわかりにくい）への直接の答え**で、5本まとめ取得はその前提条件にすぎない。

### 4.4 文言

ガイドと l10n の「例文3つに1回」を5本セット前提の表現へ書き換える
（`guideOverviewSummaryQuiz` / `guideRoleQuizBody` / `guideHowQuizStep5`、ja/en 両方）。
commit a66ba61 で消した「プレミアム登録後は例文5つに1回」の注記は復活させない（tier で分けない）。

## 5. コスト

- free: LLM 増分ゼロ（キャッシュのみ）。Firestore 書き込みが5倍だが絶対数が小さい。
  1日あたりの総本数も5本のまま（配信ぶんを消費するため）で増えない。
- premium: 配信の LLM 呼び出しが5倍。premium アクティブは60日で969本生成しており、
  配信増分は premium 人数 × 4本/日。`gemini-cost-inspect` で単価を当てて事前見積もりを取る。

## 6. 検証

`app_version` は GA4 の標準ディメンションなので、1.4.7 以前と 1.4.8 以降の比較が
そのまま自然実験になる。

主要指標（版別に比較）:

1. **1配信あたりの `summary_quiz_complete` 到達率** — 「1本のみの日 54%」をどこまで削れるか
2. `quiz_offer` shown → tapped（現状 JP 64% / TH 69%）
3. 1日あたり生成本数の分布の変化（本設計の集計スクリプトを `scripts/` に追加して再測）
4. 配信通知の開封（`notify_tier` の段階が落ちていないか＝通知1通に5本が重すぎないか）
5. **5本を最後まで消化するか**（`daily_set_index` ごとの確認クイズ到達率）。
   3本でも脱落していたなら5本は遠すぎるので、ここが撤退判断の指標になる

米国は App Store 審査トラフィックなので集計から除外する。

## 7. 作業リスト

サーバー:
- `internal/dailysentence/dailysentence.go` — `BatchSize` / `DailyBatchMinVersion` / semver 比較
- `internal/sentence/produce.go` — `ProduceBatch`（選出1回・生成並列、free のミス時引き直し）
- `deliver_daily_sentence.go` — `deliverOne` の n 本化、`commitDailySentence` / `dailyCommitPlan` /
  `rollbackDelivery` / `deliveryRestoreUpdate` の複数対応、`buildNotification` の Data 拡張
- `internal/dailysentence/notification.go` + l10n — 「ほか4本」
- golden test: `deliver_daily_sentence_golden_test.go`, `notification_golden_test.go`,
  `internal/dailysentence/golden_test.go`, `internal/sentence/produce_golden_test.go`

クライアント:
- `lib/services/daily_sentence_service.dart` — `DailySentenceSet`
- `lib/presentation/screens/home_screen.dart` — セットカーソル、`summaryQuizThreshold = 5`、生成スキップ
- 例文画面の進捗表示ウィジェット
- l10n（ja/en）＋ `flutter gen-l10n`
- `test/presentation/screens/home_screen_test.dart` ほか

リリース:
- pubspec を `1.4.8` に上げ、`DailyBatchMinVersion` と一致させる

## 8. 決定済み

- 配信本数 5本、まとめクイズ間隔も5本（配信セット＝1サイクル）
- 版ゲートは `app_version >= 1.4.8`（`app_build_number` は使えない。1参照）
- クォータは free / premium とも配信本数ぶん消費（3.2）
- 生成は**並列**。同時50本まで劣化なしを実測（3.1）。`dailySentenceConcurrency = 5` は据え置き

未決事項なし。実装に着手できる。
