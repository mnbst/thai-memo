#!/bin/zsh
# YouTube 動画にタイ語の人手字幕があるかを確かめ、あれば vtt を落とす。
#
#   scripts/yt_th_subs.sh ids.txt out_dir
#
# ids.txt は1行1動画 ID。結果は out_dir/subs.tsv（ID・字幕の形式 or NONE・秒数）。
# 並列にしないこと。8並列で約400本を叩いたら HTTP 429 と bot 判定で止められた
# （2026-10-23）。1本ずつ、リクエストの間と動画の間に待機を入れている。
# 止められたら（429 / Sign in to confirm）そこで止まる。時間をおいて再実行すると
# subs.tsv にある ID は飛ばす。
set -u
ids=$1 out=$2
mkdir -p $out/vtt
touch $out/subs.tsv
for id in ${(f)"$(<$ids)"}; do
  grep -q "^$id	" $out/subs.tsv && continue
  line=$(yt-dlp --skip-download --no-simulate --sleep-requests 2 --sleep-subtitles 3 \
    --write-subs --sub-langs th --sub-format vtt -o "$out/vtt/%(id)s" \
    --print "$id	%(subtitles.th.0.ext|NONE)s	%(duration)s" \
    "https://youtu.be/$id" 2>$out/last_err.log)
  if grep -q "429\|confirm you" $out/last_err.log; then
    echo "blocked at $id; retry later" >&2
    exit 1
  fi
  [ -n "$line" ] && echo "$line" >> $out/subs.tsv
  sleep 5
done
echo "done: $(wc -l < $out/subs.tsv) checked"
