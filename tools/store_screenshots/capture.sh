#!/usr/bin/env bash
# ストア用スクショの素材（アプリの画面そのまま）をシミュレータから撮る。
#
#   tools/store_screenshots/capture.sh <iphone|ipad> <ja|en> [shot_id]
#
# シミュレータを起動してステータスバーを 9:41・電池満タンに固定し、
# captions.json の順に「その画面にしたら Enter」で撮っていく。
# アプリは別ターミナルで `flutter run -d <表示される UDID>` で立ち上げておく。
# 表示言語はアプリ内の設定で切り替える（端末の言語には従わない）。
#
# 出力: build/store_shots/raw/<device>/<lang>/<shot_id>.png
set -euo pipefail

device="${1:?iphone か ipad を指定}"
lang="${2:?ja か en を指定}"
only="${3:-}"

root="$(cd "$(dirname "$0")/../.." && pwd)"
captions="$root/tools/store_screenshots/captions.json"

# 6.9インチ（1320x2868）と 13インチ（2064x2752）。ストアが求める寸法そのまま。
case "$device" in
  iphone)
    name="Store iPhone 6.9"
    type="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
    size="1320x2868"
    ;;
  ipad)
    name="Store iPad 13"
    type="com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"
    size="2064x2752"
    ;;
  *) echo "device は iphone か ipad" >&2; exit 1 ;;
esac

udid="$(xcrun simctl list devices -j | python3 -I -c '
import json, sys
name = sys.argv[1]
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if d["name"] == name and d["isAvailable"]:
            print(d["udid"]); sys.exit()
' "$name")"
if [ -z "$udid" ]; then
  runtime="$(xcrun simctl list runtimes -j | python3 -I -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(rs[-1]["identifier"])
')"
  udid="$(xcrun simctl create "$name" "$type" "$runtime")"
fi

xcrun simctl boot "$udid" 2>/dev/null || true
open "$(xcode-select -p)/Applications/Simulator.app" --args -CurrentDeviceUDID "$udid"
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl status_bar "$udid" override \
  --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

out="$root/build/store_shots/raw/$device/$lang"
mkdir -p "$out"

echo "シミュレータ: $name ($udid)"
echo "アプリ起動: flutter run -d $udid --dart-define=ENV=dev"
echo "アプリの表示言語を [$lang] にしてから進める。"
echo

python3 -I -c '
import json, sys
for s in json.load(open(sys.argv[1]))["shots"]:
    print(s["id"] + "\t" + s["screen"])
' "$captions" | while IFS=$'\t' read -r id screen; do
  if [ -n "$only" ] && [ "$id" != "$only" ]; then continue; fi
  read -r -p "[$id] $screen → Enter で撮影（s でスキップ）: " ans </dev/tty
  if [ "$ans" = "s" ]; then continue; fi
  xcrun simctl io "$udid" screenshot --type=png "$out/$id.png" >/dev/null 2>&1
  got="$(sips -g pixelWidth -g pixelHeight "$out/$id.png" | awk '/pixel/{print $2}' | paste -sd x -)"
  if [ "$got" != "$size" ]; then
    echo "  寸法が $got（期待値 $size）。端末の向きを確認する。" >&2
  fi
  echo "  → $out/$id.png"
done
