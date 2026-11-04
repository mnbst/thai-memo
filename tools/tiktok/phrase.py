"""短いひとこと（phrases.json）から TikTok 用の縦動画を組む。

構成: 書き出し（日本語）→ タイ語＋発音（タイ語2回）→ 訳（日本語）→ 機能の締め
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import common as c
from sentence import card_sentence


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--id", required=True)
    p.add_argument("--out", required=True)
    a = p.parse_args()

    items = json.loads(c.data_file("phrases").read_text())
    s = next(x for x in items if x["id"] == a.id)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    label = c.plain(s["hook"])

    hv = c.synth(label, out / "hook.mp3")
    th = c.synth(s["thai"], out / "th.mp3", "th-TH", c.TH_WORD_VOICE)
    tv = c.join_audio([th, th], out / "th2.wav", gap=0.6)
    jv = c.synth(s["ja"], out / "ja.mp3")

    c.card_hook(s["hook"], c.STR["today"]).save(out / "s1.png")
    card_sentence(label, s["thai"], s["roman"], None).save(out / "s2.png")
    card_sentence(label, s["thai"], s["roman"], s["ja"]).save(out / "s3.png")
    shot, caption = c.END_FEATURES[s["end"]]
    c.card_end(c.FEATURE_IMAGES / shot, caption).save(out / "s4.png")

    segs = [
        c.still(out / "s1.png", max(1.8, c.duration(hv) + 0.4), out / "seg1.mp4", hv, fade_in=False),
        c.still(out / "s2.png", c.duration(tv) + 0.6, out / "seg2.mp4", tv),
        c.still(out / "s3.png", c.duration(jv) + 0.8, out / "seg3.mp4", jv, fade_in=False),
        c.still(out / "s4.png", 3.0, out / "seg4.mp4"),
    ]
    c.concat(segs, out / "video.mp4")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
