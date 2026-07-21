# 毎日例文配信 + リマインド通知 設計

## 背景

- prod実測（2026-07-20）: 137ユーザー、premium 2（1.5%）、MAU 36（26%）
- W28コホートのD1が8%（他コホートは45〜67%）。流入はX（毎日投稿）
- 仮説: 「まいにちタイ語」+ Xの毎日投稿 → ユーザーは受動的に毎日届くと期待。実際は自分で生成ボタンを押す能動的アプリで、期待とズレて離脱
- 対策: 毎日決まった時刻に例文を届け、未実施なら通知でリマインドする

## 方針（確定）

**通知に例文を載せる。したがってサーバーが通知時点で例文を確定させる（事前生成する）。**

- 配信時刻に、その日まだ生成していないユーザーの例文をサーバーが1件確定 → Firestoreに保存 → 通知を送る
- すでにその日生成済みのユーザーには何もしない（通知も配信もなし）
- 通知本文にタイ語＋日本語訳を載せる（Xの毎日投稿と同じ体験）
- 通知タップ、**または通知を無視してアプリを開いた場合も**、その例文が表示される

### 通知ペイロードに依存しない設計にする

「アプリを開いたら通知の例文が表示される」を成立させるため、表示のソースは通知ペイロードではなく**Firestore**にする。

- サーバーは `users/{uid}/sentences` に `daily: true`, `daily_date: 'YYYY-MM-DD'` 付きで書く
- クライアントは起動時／フォアグラウンド復帰時に当日分の `daily` 例文を取得してローカルSQLiteへ取り込み、例文タブに表示
- 通知タップはそこへのディープリンクにすぎない

こうすると、通知を消した・通知が届かなかった・通知OSレベルで拒否、のどのケースでもアプリを開けば例文が出る。

### ローカル取り込みは主キー流用で済む

`sentences.id` は `TEXT PRIMARY KEY`（`database_constants.dart:81`）なので、Firestoreのdoc IDをそのままローカルidとして使える。`INSERT OR IGNORE` で冪等になり、**当初想定した `remote_id` 列の追加マイグレーションは不要**。

## 決定事項

| 項目 | 決定 |
|---|---|
| 配布対象 | 全ユーザー。設定からオプトアウト可能 |
| 配信時刻 | デフォルト10時。ユーザーのタイムゾーンにおけるローカル10時 |
| 時刻変更 | 設定から変更可能（`preferredGenerationTime` を復活させる） |
| 配信条件 | その日 `daily_sentence_generated == false` かつ 配信対象セグメント（下記） |
| 通知本文 | タイ語＋日本語訳 |
| 表示ソース | Firestore（通知ペイロードではない） |
| 例文ソース | free=キャッシュのみ（LLMコストをゼロに）／premium=LLM生成 |
| LLMフォールバック | free はしない。キャッシュミス時は別の語を選び直す |
| クォータ消費 | する（通常の生成と同じ。下記の分析参照） |
| UVM露出登録 | しない |

## 配信ターゲティング

全ユーザーに毎日送ると、離脱済み・アンインストール済みのユーザーにも生成し続けることになる。最終生成日からの経過日数で頻度を落とす。

### 生成実績のシグナルは既存フィールドを使う

- `daily_sentence_generated` は毎日 `false` にリセットされる（`dailyBatch.ts:197`）ため履歴が残らない
- `last_generation_date` はFirestoreルールの拒否リストに名前があるだけで、**実際にはどこからも書かれていない幽霊フィールド**。使わない
- 代わりに `last_sentence_generated_at`（SERVER_TIMESTAMP）が例文コミット時に既に書かれている（`sentence_handlers.py:199`）

これをそのまま主シグナルに使う。**新規フィールドもバックフィルも不要**で、日付文字列よりタイムゾーン非依存に比較できる。

### 大前提: 一度も生成していないユーザーには送らない

インストールしただけのユーザーを弾く。判定は**例文の生成実績があるか**で行う。

オンボーディング完了フラグとコーチマーク表示済みフラグ（`app_config.dart:45-55` の `sentence_coach_shown` 等）は SharedPreferences と GA4 にしか存在せず、Cloud Functions から参照できない。一方、例文生成にはオンボーディング通過とボタン操作が必要なので、**生成実績はオンボ完了を包含する**。クライアント側の新規実装が不要で、判定としてもより強い。

判定式: `last_sentence_generated_at` が存在する、または `estimated_vocab > 0`

`estimated_vocab` の併用は、`last_sentence_generated_at` が導入される前に生成したきりのユーザーの取りこぼし対策。`estimated_vocab` は保持期限で消えない永続シグナルなのでこれを救える。

**この判断のトレードオフ**: prod実測で未生成は約28%あり、活性化の最大の課題層かつD1離脱コホートを含む。リテンション施策として最も効かせたい相手を意図的に除外することになる。「使ってすらいない相手に毎日通知するのはスパム」という判断を優先した結果であり、意図的なもの。

### 頻度の逓減（バックオフ）

無反応の通知が同じ段階で3回たまるごとに、次の段階へ落とす。

| 段階 | 間隔 | 無反応が続いた場合の配信日 |
|---|---|---|
| 0 | 1日 | 0, 1, 2 |
| 1 | 3日 | 5, 8, 11 |
| 2 | 10日 | 21, 31, 41 |
| 3 | 30日 | 71, 101, 131 |
| 4 | 停止 | — |

計12通・約4.3ヶ月で打ち切る。永久に送り続けないため、UNREGISTEREDの検知に漏れたアンインストール済みユーザーへの無駄も12回で頭打ちになる。

#### 「反応」の判定は2段階

主シグナルは**「次へ」押下**（＝`last_sentence_generated_at` が動く）。通知をタップしただけ、ロック画面でプレビューを見ただけと区別でき、「もっと学びたい」という本来測りたい意図そのものになる。

ただしこれ単独では不足がある。毎日例文はクォータを1消費して配信されるため、通知から開いて例文を読んで満足して閉じたユーザーはその日の学習が成立しているのに無反応に数えられる。3日続けただけで間隔が3日に落ち、**毎日ちゃんと読んでいるユーザーを最も早く降格させてしまう**。

そこで開封を副シグナルとして挟む。

| 行動 | シグナル | 扱い |
|---|---|---|
| 「次へ」を押した | `last_sentence_generated_at` | 段階を0にリセット |
| 開いただけ | `last_opened_at` | 段階を進めない（`misses` を増やさない） |
| 開かなかった | — | `misses += 1` |

段階が上がるのは**アプリを開きすらしなかった場合だけ**になり、「反応がない＝届いていない／見ていない」という本来の定義に一致する。

`last_opened_at` はクライアントが起動時・フォアグラウンド復帰時に `users/{uid}` へ書く。ルールの update 拒否リストに含めないので**ルール変更は不要**。既存の `last_active_at` に相乗りさせないのは、あれがサーバー側で「生成・クイズをした」という意味で書かれており `scripts/prod_analytics.py` がリテンション指標に使っているため。

**復帰時のリセット**: 停止後でもユーザーが自分で生成すれば `last_sentence_generated_at` が動くため、バッチ側で段階を0に戻し停止を解除する。恒久的な除外にはならない。

**トグルON時のリセット**: 停止後に復帰しても例文を生成せず閲覧だけのユーザーは上記の解除に乗らない（リセット条件が `last_sentence_generated_at` のみのため）。設定画面で通知トグルをONにした操作を「再開の意思表示」とみなし、クライアントが `notify_tier` / `notify_tier_misses` を0に書く。ルールはこの2フィールドについて**0へのリセットに限り**クライアント書き込みを許可する（0に戻して増えるのは本人への通知だけなので悪用の害がない）。

#### 必要なフィールド（すべて `users/{uid}`）

| フィールド | 管理 | 用途 |
|---|---|---|
| `last_sentence_generated_at` | サーバー（既存） | 反応の主シグナル。配信ターゲティングにも使う |
| `last_opened_at` | クライアント（新規） | 反応の副シグナル（開封） |
| `last_notified_at` | サーバー（新規） | 次回配信日の算出。反応判定の基準時刻 |
| `notify_tier` | サーバー（新規） | 現在の段階 0-4。初期値0、4で停止 |
| `notify_tier_misses` | サーバー（新規） | 現段階での無反応回数 0-2 |

#### 判定ロジック

```
TIER_INTERVAL_DAYS = [1, 3, 10, 30]   # notify_tier == 4 は停止

配信する条件:
  生成実績あり（last_sentence_generated_at あり or estimated_vocab > 0）
  && daily_reminder_enabled
  && daily_sentence_generated == false
  && notify_tier < 4
  && now >= last_notified_at + TIER_INTERVAL_DAYS[notify_tier]

前回通知への反応を先に評価してから送る:
  if last_sentence_generated_at > last_notified_at:
    notify_tier = 0
    notify_tier_misses = 0
  elif last_opened_at > last_notified_at:
    据え置き（misses を増やさない）
  else:
    notify_tier_misses += 1
    if notify_tier_misses >= 3:
      notify_tier += 1
      notify_tier_misses = 0
      if notify_tier >= 4: 送らず停止

送信後:
  last_notified_at = now
```

サーバー管理のフィールドのうち `last_notified_at` をFirestoreルールの update 拒否リストに追加する。`notify_tier` / `notify_tier_misses` は上記トグルON時のリセットのため「両方0を書く場合のみ」クライアント更新を許可する。`last_sentence_generated_at` も同様に追加する（現状は幽霊フィールドの `last_generation_date` が載っているだけで、実際に書かれている方が保護されていない）。`last_opened_at` はクライアントが書くので追加しない。

### アンインストール済みユーザーの除外

通知本文に例文を載せる以上、生成 → 送信の順になり、送信するまでアンインストールを検知できない。したがって**初回は1回だけ無駄に生成される**。

対応: 送信結果が `messaging/registration-token-not-registered`（UNREGISTERED）なら、

1. 生成した例文docを削除
2. `users/{uid}.fcm_token` をクリア

トークンを消せば次回以降は配信対象外になるため、無駄は1ユーザーあたり1回で止まる。free例文はGCSキャッシュ由来でLLMを叩かないため、コストはFirestore書き込み1件のみ。

上記の段階バックオフが二重の網になる。iOSはAPNs側の反映ラグでUNREGISTEREDの検知が遅れることがあるが、アンインストール済みユーザーはどちらのシグナルも動かないため段階が最速で進み、計12通で停止する。

### クォータ消費: する（通常の生成と同じ）

毎日例文も5回/日の枠を1つ消費する。「開かなかった日にも枠が減る」ことを一度は懸念したが、損失が成立する条件を分解すると噛み合わないため実害がない。

- 通知を無視して**その日一度もアプリを開かなかった**場合 → 1枠消費して残4。ただし本人は0回しか使っていないので実際には何も失っていない
- **アプリを開いた**場合 → 毎日例文が表示される。枠は「見た例文」に使われており、通常の生成と等価

損失には「一度も開かない」かつ「上限まで使いたかった」の同時成立が必要で、両立しない。したがって特別扱いは不要。

**残る些細な点**: 毎日例文はサーバーがUVMから語を選ぶため、トピック・文体をユーザーが指定できない。上限まで使うヘビーユーザーにとっては5枠のうち1枠が自分で選べない例文になる。表示画面から「別の例文を生成」で通常フローに入れるようにすれば実質的に解消する。

### UVM露出登録: しない

`_register_sentence_exposure` は呼ばない。開いていない例文で `estimated_vocab` が上がるのを防ぐため。クォータとは扱いを分ける。

### PremiumだけLLM生成・テーマ設定を反映する

分岐は `tier == 'premium'` の1つだけにする。premium は通常生成と同じスペックでLLMを呼び、生成に失敗した場合だけキャッシュへ退避して通知そのものは落とさない。

**free はプレミアム体験トライアルの残があってもキャッシュのまま**。トライアルを毎日例文に混ぜると、free側にLLM原価と残回数の増減という2つの変動要因が入り、「通知を開かなかった日にも有限のトライアル枠が減る」という説明しづらい挙動も生む。トライアルは、ユーザーが自分でボタンを押して使う通常生成に閉じておく。

### トライアル残がある間は配信しない

free の配信はキャッシュ品質なので、premium品質を体験してもらう期間に混ぜると差が伝わらない。加えて配信はクォータを1消費するため、その日の自力生成が5回から4回に減り、トライアル（5回）の消化が1日ぶん遅れる。

判定は `should_deliver` に1条件: `tier != 'premium' && premium_trial_remaining > 0` なら配信しない。トライアルを使い切った時点で通常どおり配信対象に戻る。premium はトライアル枠を消費しないのでこの条件の対象外。

**テーマ設定はFirestoreにミラーする必要がある**。テーマは `SharedPreferences` の `pref_topic` にしか無く、配信バッチから参照できない。対応:

| 書くタイミング | 内容 |
|---|---|
| テーマ変更時（`setGenerationParam('topic', …)`） | `users/{uid}.preferred_topic` を更新 |
| 起動時（`syncPushRegistration`） | 既存ユーザー向けに現在値で揃える |

「おまかせ」（null）はフィールドごと削除し、バッチ側は未設定として通常どおりUVMのkey_wordからテーマを決める。`preferred_topic` はクライアントが書くのでルールの拒否リストには入れない。

premium の生成はユーザーごとに逐次実行される。現状の課金ユーザー数なら1時間バケットあたりの件数は少なく540秒に収まるが、増えたら並列化が必要になる。

## 実装

### 1. 配信バッチ（新規 Python scheduled function）

`dailyBatch.ts`（TypeScript）には足さない。`pick_free_sentence` がPython実装のため、TSに再実装すると二重管理になる。

- `functions/python/` に新規関数を追加し、`select_uvm_target_words` + `pick_free_sentence` を再利用
- スケジュール `0 * * * *`（毎時）。各ユーザーの `timezone` と設定時刻からローカル時刻を判定
- 条件: `daily_sentence_generated == false` && オプトアウトしていない
- キャッシュミス時はLLMを呼ばず別の語を選び直す
- `users/{uid}/sentences` に `daily: true`, `daily_date` 付きで保存
- FCM送信（本文＝タイ語＋日本語訳、data に doc ID）

### 2. クライアント取り込み

- 起動時／フォアグラウンド復帰時に当日の `daily` 例文をFirestoreから取得
- doc IDを主キーにして `INSERT OR IGNORE` でSQLiteへ（マイグレーション不要）
- 例文タブに表示

### 3. タイムゾーンと時刻設定

- クライアントが `users/{uid}.timezone` にIANA名を保存
- オフセット（分）で持つとサマータイムで壊れるためIANA名で持つ
- `DateTime.timeZoneName` は環境依存で信頼できない → `flutter_timezone` パッケージ追加
- 既存137人は未保存 → フォールバック `Asia/Tokyo`
- 配信時刻は `users/{uid}.preferred_generation_hour`（デフォルト10）。設定画面から変更可能
- 既存の `SettingsState.preferredGenerationTime`（保存されているがUI・参照なし）をこの用途で復活させる

### 4. 通知とオプトアウト

- `firebase_messaging` 追加、`users/{uid}.fcm_token` に保存
- `users/{uid}.daily_reminder_enabled`（デフォルト `true`）
- 設定画面にトグルと時刻ピッカーを置く

## 注意点

### `daily_sentence_generated` のリセットはJST固定

`dailyBatch` はJST 0:00に全ユーザー一律でリセットする（`dailyBatch.ts:197`）。「同じ日」の定義はローカル日ではなくJST日になる。クォータの日次境界が元々JST固定なので既存仕様と整合しているが、UTC-9より西のユーザーはローカル配信時刻がJST日の切り替わりを跨ぐ。実害は「リセット直後に未生成扱いで配信される」＝正しい挙動なので許容する。

### Firestoreルール

- `users/{uid}/sentences` は `allow read: uid一致 / allow write: false` 済み（サーバー専用書き込み）＝変更不要
- `users/{uid}` の update 拒否リストに `timezone` / `fcm_token` / `daily_reminder_enabled` / `preferred_generation_hour` は含まれないため、クライアントから書き込み可能＝変更不要

## 関連ファイル

- `functions/python/sentence_handlers.py` — 既存生成フロー（L197 `daily_sentence_generated = true`、L350-364 キャッシュ分岐、L392-402 Firestore保存）
- `functions/python/sentence_service.py` — `get_free_sentences` / `pick_free_sentence`（L103-125）
- `functions/python/scripts/generate_free_sentences.py` — キャッシュ生成スクリプト
- `functions/javascript/src/dailyBatch.ts` — 既存の日次バッチ。L197 でフラグリセット
- `firebase/firestore.rules` — L13-16 に sentences サブコレクションのルール
- `lib/core/database_constants.dart` — L81 `id TEXT PRIMARY KEY`
- `lib/presentation/providers/remaining_quota_provider.dart` — Firestore購読パターンの参考
- `lib/presentation/screens/home_screen.dart` — L59/103/168 でフラグ参照
- `lib/data/sentence_repository.dart` — `generateAndSaveSentence`
