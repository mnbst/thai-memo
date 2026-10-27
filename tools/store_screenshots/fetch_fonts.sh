#!/usr/bin/env bash
# ストア用スクショの見出しに使う太字の日本語・韓国語フォントと、
# ko の画面に描く韓国語フォント、ヘッダー（header.py）用の Medium・Bold を取ってくる。
# リポジトリには置かない（tools/store_screenshots/fonts/ は gitignore 済み）。
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)/fonts"
mkdir -p "$dir"
base="https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/SubsetOTF"
for f in JP/NotoSansJP-Black.otf JP/NotoSansJP-Medium.otf JP/NotoSansJP-Bold.otf \
  KR/NotoSansKR-Black.otf KR/NotoSansKR-Regular.otf KR/NotoSansKR-Medium.otf KR/NotoSansKR-Bold.otf; do
  target="$dir/${f#*/}"
  [ -f "$target" ] || curl -sfL -o "$target" "$base/$f"
done
