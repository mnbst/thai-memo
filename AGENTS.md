# AGENTS.md

## Go Cloud Functions

- Go 関数のテストは `functions/go` で `go test ./...` を実行すること。
- Go 関数は Firebase CLI ではなく `gcloud functions deploy --gen2` で個別デプロイすること。
- ランタイムは `go126`、リージョンは `asia-northeast1`。

## Firebase deploy

- `functions/javascript` の Cloud Functions は `firebase.json` で codebase `js-functions` として定義されている。
- JS に残す関数は `onUserCreate` と `deleteUserData` の2本だけ。
- JS 関数を個別デプロイするときは `functions:<functionName>` ではなく `functions:js-functions:<functionName>` を使うこと。
- 例: dev の `onUserCreate` は `firebase deploy --only functions:js-functions:onUserCreate --project dev`。
