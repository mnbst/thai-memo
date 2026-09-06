#!/usr/bin/env bash
# スクリーンショット生成に使う日本語フォントを取ってくる。
# アプリは日本語を端末のシステムフォントに任せているが、flutter_test には
# システムフォントが無いので、ここで明示的に用意する。リポジトリには置かない。
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)/fonts"
mkdir -p "$dir"
target="$dir/NotoSansJP-Regular.otf"

if [ -f "$target" ]; then
  exit 0
fi

curl -sfL -o "$target" \
  "https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/SubsetOTF/JP/NotoSansJP-Regular.otf"
