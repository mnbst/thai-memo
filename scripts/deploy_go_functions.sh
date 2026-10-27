#!/usr/bin/env bash
# =============================================================================
# deploy_go_functions.sh
# Go の Cloud Functions を origin/main からデプロイする。
#
#   scripts/deploy_go_functions.sh <dev|tester|prod> <関数名>...
#   scripts/deploy_go_functions.sh dev --local <関数名>...   # dev の動作確認だけ作業ツリーから
#
# ローカルの作業ツリーからデプロイすると、main にある変更が抜けたり未コミットの
# ファイルが混ざったりする（2026-10 に App Check の回数上限が本番から外れていた）。
# そのため tester / prod は必ず origin/main を detached で取り出した worktree から出す。
#
# 既存の関数の設定（メモリ・タイムアウト・サービスアカウント・環境変数・公開設定）は
# gcloud が引き継ぐので、ここでは指定しない。新しい関数を作るときは functions.go の
# 例（--service-account など）を見て手で出す。
# =============================================================================
set -euo pipefail

usage() {
  echo "usage: $0 <dev|tester|prod> [--local] <function>..." >&2
  exit 1
}

[ $# -ge 2 ] || usage
env="$1"; shift
case "$env" in
  dev) project=thai-memo-dev ;;
  tester) project=thai-memo-67139 ;;
  prod) project=thai-memo-prod ;;
  *) usage ;;
esac

local_tree=false
if [ "${1:-}" = "--local" ]; then
  [ "$env" = dev ] || { echo "--local は dev だけ" >&2; exit 1; }
  local_tree=true
  shift
fi
[ $# -ge 1 ] || usage

repo="$(git rev-parse --show-toplevel)"
if $local_tree; then
  src="$repo"
else
  git -C "$repo" fetch -q origin main
  src="$(mktemp -d)/thai-memo-deploy"
  git -C "$repo" worktree add -q --detach "$src" origin/main
  trap 'git -C "$repo" worktree remove --force "$src"' EXIT
  echo "deploy from origin/main $(git -C "$src" log --oneline -1)"
fi

for fn in "$@"; do
  # 既存の関数だけを更新する（新規作成は設定を手で決める）。
  if ! gcloud functions describe "$fn" --project "$project" \
      --region asia-northeast1 --format="value(name)" >/dev/null 2>&1; then
    echo "$fn は $project に無い。新規作成は functions.go の例を見て手で出す" >&2
    exit 1
  fi
done

pids=()
logs=()
for fn in "$@"; do
  log="$(mktemp)"
  logs+=("$fn:$log")
  # トリガーは引き継がれないので、今の関数から読んで同じものを付け直す。
  # Pub/Sub の関数に --trigger-http を付けると 400 で落ちる。
  topic="$(gcloud functions describe "$fn" --project "$project" \
    --region asia-northeast1 --format="value(eventTrigger.pubsubTopic)")"
  if [ -n "$topic" ]; then
    trigger=(--trigger-topic="${topic##*/}")
  else
    trigger=(--trigger-http)
  fi
  gcloud functions deploy "$fn" --project "$project" --gen2 --runtime=go126 \
    --region=asia-northeast1 --source="$src/functions/go" --entry-point="$fn" \
    "${trigger[@]}" --quiet >"$log" 2>&1 &
  pids+=($!)
done

failed=0
for i in "${!pids[@]}"; do
  fn="${logs[$i]%%:*}"; log="${logs[$i]#*:}"
  if wait "${pids[$i]}"; then
    echo "$fn: $(grep -E '^updateTime:' "$log" | tr -d "'" )"
  else
    echo "$fn: FAILED" >&2
    tail -20 "$log" >&2
    failed=1
  fi
done
exit $failed
