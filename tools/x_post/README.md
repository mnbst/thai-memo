# X（Twitter）自動投稿

`@everydaythai775` に毎日の例文を自動投稿する。手で出していた
「今日のタイ語＋アプリ画面のスクショ」を、読み上げ音声つきの動画にして出す。

## 流れ

| 手順 | 中身 |
| --- | --- |
| `pick_sentence.py` | GCS の free 例文バンクから未投稿を1件選び、本文を組む |
| `test/screenshots/x_post_screenshot.dart` | `DetailScreen` をそのまま描画して PNG に落とす |
| `synth_tts.py` | Google Cloud TTS（th-TH）で読み上げ音声を作る |
| `build_media.py` | PNG を4枚以内に分割し、1枚目＋音声を mp4 にする |
| `post_to_x.py` | X に投稿し、投稿済みを GCS に記録する |

実行は `.github/workflows/post-daily-x.yml`（毎日 07:00 JST）。

## 例文のソース

`gs://<project>-uvm-data/free_sentences_ja.json`（free 例文バンク）を使う。
毎日配信の例文はユーザーごとに生成される個人データなので公開投稿には使わない。
バンクは同じ生成パイプラインで作った共有プールなので内容は同等。

投稿済みは `gs://<project>-uvm-data/x_post/posted.json` に持つ。

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

動画の添付は X の API プラン次第で使えないことがある。その場合 `post_to_x.py` は
自動で画像4枚に、それも駄目ならテキストのみに落として投稿を止めない。

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
