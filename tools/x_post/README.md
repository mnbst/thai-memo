# X（Twitter）自動投稿

`@everydaythai775` に毎日の例文を自動投稿する。手で出していた
「今日のタイ語＋アプリ画面のスクショ」を、お手本再生を操作する動画1本と
画面の画像3枚にして出す。

## 流れ

| 手順 | 中身 |
| --- | --- |
| `pick_sentence.py` | 枠のテーマを決め、候補を20件に絞り、過去10件と比べて Gemini に1件選ばせる |
| `synth_tts.py` | Google Cloud TTS（th-TH）で読み上げ音声を作る（通常速度で1回） |
| `test/screenshots/x_post_screenshot.dart` | `DetailScreen` を描画し、画像3枚と操作フレームを書き出す |
| `build_media.py` | 操作フレームに音声を載せて mp4 にする |
| `post_to_x.py` | X に投稿し、投稿済みを GCS に記録する |

実行は `.github/workflows/post-daily-x.yml`（毎日 07:00 JST。`x_post_extra_slots` で枠を足せる）。

prod の1日の枠:

| 時刻 | 中身 |
| --- | --- |
| 07:00 | 例文（テーマは下記「テーマの決め方」） |
| 10:00 | Tips（下記「Tips・ガイド」） |
| 12:00 | 例文 |
| 15:00 | ガイド（ガイド画面の1欄の画像付き） |
| 17:00 | 例文 |

Scheduler は枠の名前（`slot`: 0700 / 1200 / 1700）をワークフローに渡す。

## 例文のソース

`gs://<project>-uvm-data/` の `corpus_sentences_ja.json`（静的コーパス）と
`corpus_pool_ja.json`（運用中に貯めたプール）を候補にする（premium の CorpusBank と同じ2本）。

### テーマの決め方（コード）

`inputs.themes`（`terraform/prod.tfvars` の `x_post_themes` / 枠ごとの `themes`）に並べたテーマから、
枠ごとに選ぶ。空なら全6テーマ（`タイ旅行` `タイ生活` `恋愛` `BLドラマ` `仕事` `推し活`）。

1. その枠で投稿が3件未満のテーマがあれば、その中から抽選する（探索）
2. 試し終えたら2割は抽選、8割は点数の高いテーマにする。
   点数 ＝ 枠×テーマの表示回数の中央値 × 曜日の補正（そのテーマの曜日、薄ければ平日／週末の中央値の全体比。3件以上あるときだけ）
3. 候補が残らないテーマは飛ばして次の順位へ

### 候補の絞り込み（コード）

破綻の除外（下記）→ テーマ → 投稿済みを外す（尽きたら戻す）→ BLドラマは作品で絞る、のあと、
Gemini に渡す20件を選ぶ。長さの3帯（7–8語 / 9–10語 / 11語）から同じ数ずつ、同じ場面は2件まで、
その枠の直近10件と同じ場面は後回しにする。

各候補には語数・場面（`subTheme`、無ければ `topic`）・文法の特徴を付ける。文法の特徴は
単語分解の語が `GRAMMAR_MARKERS` と完全に一致したときだけ付ける（疑問・依頼・否定・勧誘・丁寧語尾・
くだけた語尾・時制・比較・程度）。

`BLドラマ` は、本文か使い方に作品の見当がつく語（登場人物名やそのカタカナ、猫・幽霊・占いなど）が
ある例文だけを候補にし、さらに作品を1つ抽選して絞る（`BL_DRAMA_MARKERS`）。

### 1件の選定（Gemini）

Gemini には1回だけ問い合わせる。渡すのは観点（プロンプトに書くだけ）、曜日・時間帯、
その枠の直近10件の「選んだ理由・表示回数・反応」、長さ・文法ごとの伸びやすさの要約、候補20件。
答えは `{"index", "reason"}`（理由は60字以内）。思考は使わない。
応答しない・番号がおかしいときは同じ20件から抽選し、`chooser` に `抽選` と残す。

投稿済みと、投稿の履歴は `gs://<project>-uvm-data/x_post/posted.json` に持つ。履歴の1件には
tweet_id・本文・訳・テーマ・投稿日時に加え、`slot` `weekday` `theme_reason` `reason` `chooser`
`word_count` `char_count` `scene` `grammar` と表示回数・反応を残す。理由の文章は枠ごとに直近10件だけ残し、
数字と特徴は集計用に1000件まで残す。枠を記録する前の投稿は、投稿時刻から枠と曜日を割り出す。

## 選び方を変える

選定プロンプトは `select_prompt.txt` に置いてある。ここを書き換えれば選び方を
変えられる（コードは触らなくてよい）。`#` で始まる行は無視される。
差し込み口は `{theme}` `{when}` `{recent}` `{trend}` `{candidates}`（ファイル冒頭に説明）。

## 破綻の除外

Gemini に渡す前に、機械的に分かるものだけ落とす。

- 本文・発音・訳のどれかが空
- 発音表記に算用数字が残っている（例: 「50 บาท」が「5 bàat」。生成側の取りこぼし）
- 本文が80文字を超える（詳細画面の見栄えが崩れる）
- 単語分解が空、または分解した語が本文に見つからない
- 語数（単語分解の数）が7〜11の範囲に無い

自然さや訳の妥当性はプロンプト側で Gemini に見させる。

## 表示回数の取り直し

その枠の投稿のうち、表示回数をまだ持っていないものと、投稿から3日以内（まだ伸びる）のものだけを
X から取り直す。取り直した値は `post_to_x.py` が `posted.json` の履歴に書き戻し、それより古い投稿はその値を使う。

X の読み取りは PPU のクレジットを消費する。クレジットが無い（402）・鍵が無い場合は
履歴に残した値だけを使う。

## Tips・ガイド

ワークフローの `kind` が `tip` / `guide` の枠は、例文の代わりに `study_posts.json` の
投稿文を出す（`pick_study_post.py`）。投稿文はアプリの Tips（ローディング画面）と
ガイド（タイ文字・発音・語順・声調）から書き起こした完成文で、その場で生成はしない
（タイ語の誤りを避けるため）。足す・直すときはこのファイルを編集する。

- 同じ kind の中から抽選する。一巡するまで同じ文は出さず、全部出したら最初から繰り返す
  （投稿済みキー `study:<id>:<回数>` を posted.json に積み、回数が一番少ないものから選ぶ）。
- ガイドの文は `image.screen`（script / pron / word_order / tone）の画面から、`image.from`
  の見出しを含む欄（Card）を `test/screenshots/guide_screenshot.dart` で切り出して1枚貼る。
  見出しにタイ文字が入るもの（語順ガイドなど）は、日本語だけの部分を `from` に書く。
  描けなかったときは本文だけで出す。
- 本文の長さ（ハッシュタグ込みで X の 280）と書式は
  `python tools/x_post/pick_study_post.py --check` で確かめられる。

## 画面の描画

シミュレータではなく `flutter test` 上で `DetailScreen` を描画する。サインインも
実機も要らず、実UIのピクセルがそのまま得られる。テスト環境にはシステムフォントが
無いので、タイ語（`google_fonts/`）・日本語（`fetch_fonts.sh` が取得）・
MaterialIcons を明示的に読み込んでいる。

`_test.dart` で終わらないファイル名なので、通常の `flutter test` では走らない。

## 事前に必要なもの

1. X Developer Portal でアプリを作り、**Read and write** 権限の OAuth 1.0a
   認証情報（API Key / API Secret / Access Token / Access Token Secret）を発行する。
   これは本人しか取得できない。
2. 発行した4つを Secret Manager に入れる（枠は Terraform が作る）。

   ```bash
   printf '%s' '<値>' | gcloud secrets versions add x-api-key \
     --project=thai-memo-prod --data-file=-
   # x-api-secret / x-access-token / x-access-token-secret も同様
   ```
3. `terraform apply` で `texttospeech.googleapis.com` の有効化と
   シークレットの枠を作る。

## 添付するもの

動画1本＋画像3枚（Xの添付上限は4件）。

- 動画は「お手本を聞く」を押してから読み上げが終わるまでの画面。実際に操作した
  ときと同じ描画を `flutter_test` 上で1コマずつ撮り、音声はタップした位置から
  重ねる。読み上げは通常速度で1回だけ。
- 画像は動画が映した1画面目の続きから撮る。見出しや単語の区切りで送るので、
  直前の画面で見切れた要素の頭が次の1枚の先頭に来る。最後の1枚だけは切れ目に
  揃えず下端まで送り、単語カードの末尾を必ず入れる（最大3枚）。
- タイ語フォントはアプリ既定の Sarabun に固定する。

X が動画と画像の同時添付を拒む場合に備えて、`post_to_x.py` は動画のみ →
画像のみ → テキストのみ、の順に落として投稿を止めない。

## ローカルでの確認

```bash
pip install -r tools/x_post/requirements.txt
tools/x_post/fetch_fonts.sh

python tools/x_post/pick_sentence.py --project thai-memo-prod --out build/x_post
flutter test test/screenshots/x_post_screenshot.dart \
  --dart-define=X_POST_SENTENCE=build/x_post/sentence.json \
  --dart-define=X_POST_OUT=build/x_post
python tools/x_post/synth_tts.py --out build/x_post
python tools/x_post/build_media.py --out build/x_post
python tools/x_post/post_to_x.py --project thai-memo-prod --out build/x_post --dry-run
```

GitHub Actions からは `workflow_dispatch` の `dry_run` で同じ確認ができる。
生成物は artifact `x-post-media` に上がる。
