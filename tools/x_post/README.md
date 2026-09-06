# X（Twitter）自動投稿

`@everydaythai775` に毎日の例文を自動投稿する。手で出していた
「今日のタイ語＋アプリ画面のスクショ」を、お手本再生を操作する動画1本と
画面の画像3枚にして出す。

## 流れ

| 手順 | 中身 |
| --- | --- |
| `pick_sentence.py` | 前日生成分から破綻を除き、Gemini に1件選ばせて本文を組む |
| `synth_tts.py` | Google Cloud TTS（th-TH）で読み上げ音声を作る（通常速度で1回） |
| `test/screenshots/x_post_screenshot.dart` | `DetailScreen` を描画し、画像3枚と操作フレームを書き出す |
| `build_media.py` | 操作フレームに音声を載せて mp4 にする |
| `post_to_x.py` | X に投稿し、投稿済みを GCS に記録する |

実行は `.github/workflows/post-daily-x.yml`（毎日 07:00 JST）。

## 例文のソース

前日（日本時間）に生成された例文を Firestore の collection group `sentences`
から集め、タイ語本文で重複をまとめてから Gemini に1件選ばせる。読者像は
指定せず「X で反応が良さそうなもの」の判断を任せている。

前日分が取れないとき（索引の準備待ち・権限不足・生成が無かった日）や Gemini が
応答しないときは、`gs://<project>-uvm-data/free_sentences_ja.json`（free 例文
バンク）からの抽選に落として投稿を止めない。`--source bank` で常にバンクを使える。

collection group クエリには `sentences.created_at` の COLLECTION_GROUP 索引が
要る（`firebase/firestore.indexes.json` の `fieldOverrides`）。

投稿済みと、投稿の履歴（tweet_id とタイ語本文）は
`gs://<project>-uvm-data/x_post/posted.json` に持つ。

## 選び方を変える

選定プロンプトは `select_prompt.txt` に置いてある。ここを書き換えれば選び方を
変えられる（コードは触らなくてよい）。`#` で始まる行は無視される。
差し込み口は `{candidates}`（候補一覧）と `{recent}`（直近の反応。下記）。

## 破綻の除外

Gemini に渡す前に、機械的に分かるものだけ落とす。

- 本文・発音・訳のどれかが空
- 発音表記に算用数字が残っている（例: 「50 บาท」が「5 bàat」。生成側の取りこぼし）
- 本文が80文字を超える（詳細画面の見栄えが崩れる）
- 単語分解が空、または分解した語が本文に見つからない

自然さや訳の妥当性はプロンプト側で Gemini に見させる。

## 直近の反応の参照

`posted.json` の履歴にある tweet_id で自分の投稿の反応（いいね・リポスト・
返信の合計）を引き、伸びたものをプロンプトに添える。

X の読み取りは PPU のクレジットを消費する。クレジットが無い（402）・鍵が無い・
履歴がまだ無い場合は黙って諦め、反応を参照しない選定に落ちる。当面は手元の
感触を `select_prompt.txt` に直接書く運用でよい。

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
