#!/usr/bin/env bash
# ストア用スクショの見出しに使う太字の日本語フォントを取ってくる。
# リポジトリには置かない（tools/store_screenshots/fonts/ は gitignore 済み）。
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)/fonts"
mkdir -p "$dir"
target="$dir/NotoSansJP-Black.otf"

if [ -f "$target" ]; then
  exit 0
fi

curl -sfL -o "$target" \
  "https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/SubsetOTF/JP/NotoSansJP-Black.otf"
