# X（Twitter）自動投稿

`@everydaythai775` に毎日の例文を自動投稿する。手で出していた
「今日のタイ語＋アプリ画面のスクショ」を、アプリを操作する縦動画1本にして出す。
同じ動画を TikTok（@daily_thai4）にも使うので、Google Drive に置く（下記「TikTok 用の素材」）。

## 流れ

| 手順 | 中身 |
| --- | --- |
| `pick_sentence.py` | 枠のテーマを決め、候補を20件に絞り、過去10件と比べて Gemini に1件選ばせる |
| `synth_tts.py` | Google Cloud TTS（th-TH）で読み上げ音声を作る（通常速度で1回） |
| `build_quiz.py` | 動画の確認クイズ（単語→意味の4択）を単語分解から作る |
| `test/screenshots/tiktok_video_screenshot.dart` | 例文詳細と確認クイズを描画し、操作の連番フレームを書き出す |
| `build_video.py` | 連番フレームに音声を重ねて mp4 にする |
| `post_to_x.py` | X に投稿し、投稿済みを GCS に記録する |
| `upload_to_drive.py` | 動画（Tips・ガイドの枠は日英の画像と説明文）を Google Drive に置く |

実行は `.github/workflows/post-daily-x.yml`（毎日 07:00 JST。`x_post_extra_slots` で枠を足せる）。

prod の1日の枠:

| 時刻 | 中身 |
| --- | --- |
| 07:00 | 例文（テーマは下記「テーマの決め方」） |
| 10:00 | Tips（下記「Tips・ガイド」） |
| 12:00 | 例文 |
| 15:00 | ガイド（ガイド画面の1欄の画像付き） |
| 17:00 | 例文 |
| 20:00 | 機能紹介（ストア用スクショ付き） |

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
答えは `{"index", "reason", "hook"}`（理由は60字・書き出しは20字以内）。思考は使わない。
応答しない・番号がおかしいときは同じ20件から抽選し、`chooser` に `抽選` と残す。

### 投稿本文

```
〜の時の〇〇👇（Gemini の hook）

タイ語
発音

日本語訳
```

1行目からタイ語だと読み飛ばされるので、日本語の書き出しから始める。訳を最後に置き、先にタイ語を読ませる。ハッシュタグは付けない。
書き出しが20字を超える・タイ文字を含む・280字に収まらないときは、テーマの決まり文句（`FALLBACK_HOOKS`）に替える。
BLドラマ回は作品名・登場人物名を出さない（プロンプトで禁止し、`BL_DRAMA_MARKERS` のカタカナ名・英題が混ざったら落とす）。

投稿済みと、投稿の履歴は `gs://<project>-uvm-data/x_post/posted.json` に持つ。履歴の1件には
tweet_id・本文・訳・テーマ・投稿日時に加え、`slot` `weekday` `theme_reason` `reason` `hook` `chooser`
`word_count` `char_count` `scene` `grammar` と表示回数・反応を残す。理由の文章は枠ごとに直近10件だけ残し、
数字と特徴は集計用に1000件まで残す。枠を記録する前の投稿は、投稿時刻から枠と曜日を割り出す。

## 選び方を変える

選定プロンプトは `select_prompt.txt` に置いてある。ここを書き換えれば選び方を
変えられる（コードは触らなくてよい）。`#` で始まる行は無視される。
差し込み口は `{theme}` `{when}` `{recent}` `{trend}` `{top_hooks}` `{candidates}`（ファイル冒頭に説明）。

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

ワークフローの `kind` が `tip` / `guide` / `feature` の枠は、例文の代わりに `study_posts.json` の
投稿文を出す（`pick_study_post.py`）。投稿文はアプリの Tips（ローディング画面）と
ガイド（タイ文字・発音・語順・声調）から書き起こした完成文で、その場で生成はしない
（タイ語の誤りを避けるため）。足す・直すときはこのファイルを編集する。

- 同じ kind の中から抽選する。一巡するまで同じ文は出さず、全部出したら最初から繰り返す
  （投稿済みキー `study:<id>:<回数>` を posted.json に積み、回数が一番少ないものから選ぶ）。
- ガイドの文は `image.screen`（script / pron / word_order / tone）の画面から、`image.from`
  の見出しを含む欄（Card）を `test/screenshots/guide_screenshot.dart` で切り出して1枚貼る。
  見出しにタイ文字が入るもの（語順ガイドなど）は、日本語だけの部分を `from` に書く。
  描けなかったときは本文だけで出す。
- 機能紹介（`feature`）はアプリの機能を1つずつ紹介する文で、`image_file` に書いた固定の画像
  （`feature_images/`）を1枚貼る。ストア用スクショと同じ素材・同じ合成で、ストアから外した画面
  （例文の分解・復習タブ）も残すので枚数はストアより多い。並びと見出しは `feature_captions.json`。
  ランキング・お手本再生・通知時刻・連続日数はストアに出さない画面で、素材は
  `store_mock_screens.dart` の 06_ranking / 09_audio / 10_notify / 11_streak。
  ストアの素材を撮り直したら作り直して写す。

  ```bash
  flutter test test/screenshots/store_screenshots.dart --dart-define=DEVICE=iphone \
    --dart-define=CAPTIONS=tools/x_post/feature_captions.json --dart-define=OUT=build/x_post_feature
  cp build/x_post_feature/iphone/ja/*.png tools/x_post/feature_images/
  ```
- 本文の長さ（X の 280）と書式は
  `python tools/x_post/pick_study_post.py --check` で確かめられる。

## 画面の描画

シミュレータではなく `flutter test` 上で `DetailScreen`・`QuizScreen` を描画する。サインインも
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

縦動画1本（約1分、幅1080）。X・Threads・TikTok で共通。

1. 例文詳細で「お手本を聞く」を押し、読み上げを繰り返しながら例文を読む間を置く
   （英語版は長め）。読み上げが言い終わったところで止める
2. 「使い方」の欄 → 単語を1語ずつ、画面の中央に送って見せる（語数で1語の秒数を決め、全体で約1分）
3. 学習単語の行で単語の詳細（声調解説）を開く。収まらなければ中を下まで送る
4. 確認クイズに切り替え、考える間を置いて正解を押す。`build_quiz.py` がクイズを
   作れなかった例文は、3 で終える

実際に操作したときと同じ描画を `flutter_test` 上で1コマずつ撮り、音声は読み上げが
始まった位置ごとに重ねる。BGM は `fetch_bgm.py` が GCS の `x_post/bgm/` から1曲選んで取り、
`build_video.py --bgm` が小さく敷く（ラウドネスを -28 LUFS にそろえ、読み上げの間はさらに下げ、最後はフェードアウト）。
音源は OpenTracks（旧 DOVA-SYNDROME）のフリー BGM（クレジット不要）。ライセンス上、音源ファイルは公開の場所に
置けないので、このリポジトリには入れない。曲を足すときは同じ場所に英数字の名前で mp3 を置く。タイ語フォントはアプリ既定の Sarabun に固定する。

確認クイズのダミーは、同じ例文のほかの語の意味から選ぶ（生成しないので費用はかからない）。

## TikTok 用の素材（Google Drive）

TikTok は英語だけ。Drive のフォルダ（`issue_drive_token.py` が作る）へ置く。

| 枠 | 置くもの |
| --- | --- |
| 例文（1日1回、Terraform の `tiktok_daily_schedule`） | `<日付>_<枠>_en_post.mp4`（9:16）。ワークフローの `platform=tiktok`（tiktok ジョブ）が英語のコーパスから選び、置けたら `x_post/en/tiktok/posted.json` に記録して重ねない |
| Tips かガイド（同じ tiktok ジョブ、1日おきに交互） | `<日付>_<tip|guide>_*`: 英語の文字カード画像（`tip_card_screenshot.dart`。見出しは Tips / Guide）と説明文。英語の文がある投稿から選び、置けたら同じ記録に積む |

例文の動画は X・Threads とも 9:16。

Tips・ガイドの英語の文は `study_posts.json` の `text_en`（Codex が書いた）。
カード画像には絵文字のフォントが無いので、絵文字は落とす（説明文には残る）。

### 始めるまで（本人の作業）

1. `terraform apply`（Drive API の有効化と secret `google-drive-upload` の枠）
2. GCP コンソールで OAuth クライアント ID（デスクトップ アプリ）を作り、JSON を落とす
3. 本人のアカウントで許可して鍵を入れる（フォルダもここで作る）

   ```bash
   uv run --with google-auth-oauthlib --with google-cloud-secret-manager --with requests \
     python tools/x_post/issue_drive_token.py --project thai-memo-prod \
     --client-secret ~/Downloads/client_secret_xxx.json
   ```

## ローカルでの確認

```bash
pip install -r tools/x_post/requirements.txt
tools/x_post/fetch_fonts.sh

python tools/x_post/pick_sentence.py --project thai-memo-prod --out build/x_post
python tools/x_post/build_quiz.py --out build/x_post
python tools/x_post/synth_tts.py --sentence build/x_post/sentence.json --out build/x_post
flutter test test/screenshots/tiktok_video_screenshot.dart \
  --dart-define=X_POST_SENTENCE=build/x_post/sentence.json \
  --dart-define=TIKTOK_QUIZ=build/x_post/quiz.json \
  --dart-define=TIKTOK_OUT=build/x_post \
  --dart-define=X_POST_AUDIO_MS=4000 --dart-define=X_POST_LANG=ja
python tools/x_post/build_video.py --out build/x_post
python tools/x_post/post_to_x.py --project thai-memo-prod --out build/x_post --dry-run
```

GitHub Actions からは `workflow_dispatch` の `dry_run` で同じ確認ができる。
生成物は artifact `x-post-media` に上がる。

## Threads

X と同じワークフローを `platform=threads` で動かし、同じ枠の時刻に Threads にも出す。

- 中身の作りは X と同じ（例文は動画＋画像3枚、Tips・ガイドは同じ投稿文）。
- 例文は X と別の文にする。`pick_sentence.py --platform threads` は X と Threads の両方の
  投稿済みを外して選ぶ。同じ枠の2本はワークフローの `concurrency` で順に走るので、
  後の方が先の投稿を見て選べる（その分、後の方は数分遅れる）。
- 記録は `x_post/threads/posted.json`。テーマの点数は Threads 自身の表示回数（インサイトの views）で付ける。
- 投稿は `post_to_threads.py`。Threads はメディアを URL で取りに来るので、`x_post/threads/media/` に
  置いて署名付き URL を渡し、投稿後に消す。動画＋画像はカルーセルにする。
- トークンは長期トークン（60日）。投稿のたびに、Secret Manager の最新版が7日より古ければ延長して版を足す。
- Scheduler のジョブは `threads_post_enabled = true` で `post-daily-threads-<枠>` が作られる。

### 始めるまで（本人の作業）

1. Threads アカウントを作る（Instagram アカウントから）。
2. [Meta for Developers](https://developers.facebook.com/apps) でアプリを作り、ユースケースに
   「Threads API にアクセス」を選ぶ。権限は `threads_basic` `threads_content_publish` `threads_manage_insights`。
3. アプリの「役割」で投稿する Threads アカウントを Threads テスターに追加し、Threads の
   設定 → アカウント → ウェブサイトのアクセス許可 → 招待 で承認する
   （自分のアカウントにだけ出すので、アプリ審査は要らない）。
4. ユースケースの設定画面の「User Token Generator」で短期トークンを出し、長期トークンに替える。

   ```bash
   curl -s "https://graph.threads.net/access_token?grant_type=th_exchange_token&client_secret=<アプリシークレット>&access_token=<短期トークン>"
   ```
5. 長期トークンを Secret Manager に入れる（枠は Terraform が作る）。

   ```bash
   printf '%s' '<長期トークン>' | gcloud secrets versions add threads-access-token \
     --project=thai-memo-prod --data-file=-
   ```
6. `workflow_dispatch` で `platform=threads` `dry_run=false` を1回手で流して確かめ、
   `terraform/prod.tfvars` の `threads_post_enabled = true` にして `terraform apply`。

## 英語アカウント

英語の X アカウント（@daily_thai11）にも例文を出す。ワークフローの `lang=en` で切り替える。

- 候補は `corpus_pool_en.json`（訳は英語、テーマ名は日本語のまま）。選定プロンプトは
  `select_prompt_en.txt`、画面は英語の UI で撮る（`X_POST_LANG`）。
- 投稿済みと履歴は `x_post/en/posted.json`。日本語アカウントとは別に選ぶので、同じタイ語が両方に出ることはある。
- 出すのは例文だけ（Tips・ガイド・機能紹介と Threads は日本語だけ）。
- 開発者アプリ（`x-api-key` / `x-api-secret`）は共通で、Access Token だけ
  `x-access-token-en` / `x-access-token-secret-en` に分ける。発行は
  `python tools/x_post/issue_x_token.py --project thai-memo-prod --lang en --expect daily_thai11`
  （ブラウザで @daily_thai11 として許可し、出た PIN を `--pin` に付けてもう一度実行する。トークンは Secret Manager に直接入る）。
- 枠は Terraform の `x_post_en_slots`（米国西部の時刻。枠と曜日も `--tz America/Los_Angeles` で数える）。鍵を入れてから足して `terraform apply` する。

ダウンロードページ（`public/app.html`）は端末の言語（日本語・韓国語）、それ以外は時間帯
（Asia/Tokyo・Asia/Seoul）で ja / ko を選び、残りは en で出す。App Store は国を付けない
URL で、開いた人の国のストアへ飛ぶ。英語アカウントの BIO からは `?c=x_en_bio` で計測する。

## YouTube Shorts

日本語の例文の縦動画（X と同じ作り）を YouTube Shorts に出す。ワークフローの `platform=youtube`。

- 例文は X と別の文にする（`pick_sentence.py --platform youtube` がほかの投稿先の投稿済みを外す）。
- タイトルは「書き出し｜タイ語 #タイ語 #Shorts」（100字を超えたらタイ語を落とす）。説明欄は X と同じ本文に、
  アプリの案内と `app?c=youtube_shorts` のリンクを足す。カテゴリは教育。
- 記録は `x_post/youtube/posted.json`。テーマの点数は YouTube の再生回数で付ける（`videos.list`、1回 1 ユニット）。
- 投稿は `post_to_youtube.py`。`videos.insert` は1本 1600 ユニットで、既定の 1日 10,000 ユニットなら6本まで。
- Scheduler のジョブは `terraform/prod.tfvars` の `youtube_post_slots` に枠を足すと `post-daily-youtube-<枠>` が作られる。

### 始めるまで（本人の作業）

1. 投稿する YouTube チャンネルを作る。
2. `terraform apply`（YouTube Data API の有効化と secret `youtube-upload` の枠）。
3. GCP コンソールで OAuth 同意画面を「本番」にする（「テスト」のままだとリフレッシュトークンが7日で切れる）。
   OAuth クライアントは Drive 用（secret `google-drive-upload`）のものを使い回す。
4. チャンネルのアカウントで許可して鍵を入れる。

   ```bash
   uv run --with google-auth-oauthlib --with google-cloud-secret-manager --with requests \
     python tools/x_post/issue_youtube_token.py --project thai-memo-prod
   ```
5. [YouTube API Services の監査](https://support.google.com/youtube/contact/yt_api_form)を申請する。
   監査を通す前のプロジェクトから上げた動画は**非公開に固定**されるので、通るまでは YouTube Studio で手で公開にする。
6. `workflow_dispatch` で `platform=youtube` を1回手で流して確かめ、`youtube_post_slots` に枠を足して `terraform apply`。
