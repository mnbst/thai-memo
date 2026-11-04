"""Tips の台本（scripts.json の kind=tip）から TikTok 用の縦動画を組む。

構成: 書き出し → スライド（word: タイ語2回→日本語 / text: 日本語）→ まとめ → 機能の締め
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import ImageDraw

import common as c


def card_word(label: str, thai: str, roman: str, note: str, gloss: str):
    img = c.base(label)
    d = ImageDraw.Draw(img)
    ft, tl = c.fit(d, thai, c.THAI, 200, 90, c.SAFE_W)
    y = c.CENTER_Y - 300
    for line in tl:
        c.draw_line(img, y, line, ft, c.INDIGO)
        y += ft.size * 1.4
    c.draw_line(img, y + 10, roman, c.font(c.IPA, 64), c.MUTED)
    y += 110
    if note:
        fn = c.font(c.JP_BOLD, 44)
        tw = d.textlength(note, font=fn)
        d.rounded_rectangle(((c.W - tw) / 2 - 28, y, (c.W + tw) / 2 + 28, y + 76), 38, outline=c.GOLD, width=4)
        d.text(((c.W - tw) / 2, y + 12), note, font=fn, fill=c.GOLD)
        y += 130
    d.rectangle((c.W / 2 - 60, y, c.W / 2 + 60, y + 8), fill=c.GOLD)
    y += 50
    fg, gl = c.fit(d, gloss, c.JP_BOLD, 80, 56, c.SAFE_W, max_lines=2)
    for line in gl:
        c.draw_line(img, y, line, fg, c.INDIGO)
        y += fg.size * 1.4
    return img


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--id", required=True)
    p.add_argument("--out", required=True)
    a = p.parse_args()

    script = c.load_script(a.id)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    label = c.STR["tips"]

    hv = c.synth(script["hook"]["say"], out / "hook.mp3")
    c.card_hook(script["hook"]["text"], label).save(out / "t0.png")
    segs = [c.still(out / "t0.png", max(1.8, c.duration(hv) + 0.4), out / "seg0.mp4", hv, fade_in=False)]

    slides = script["slides"] + [{"type": "text", **script["outro"]}]
    for n, s in enumerate(slides, 1):
        ja = c.synth(s["say"], out / f"ja{n}.mp3")
        if s["type"] == "word":
            th = c.synth(s["thai"], out / f"th{n}.mp3", "th-TH", c.TH_WORD_VOICE)
            audio = c.join_audio([th, th, ja], out / f"a{n}.wav")
            card_word(label, s["thai"], s["roman"], s.get("note", ""), s["gloss"]).save(out / f"t{n}.png")
        else:
            audio = ja
            c.card_text(label, s["text"]).save(out / f"t{n}.png")
        segs.append(c.still(out / f"t{n}.png", c.duration(audio) + 0.4, out / f"seg{n}.mp4", audio))

    shot, caption = c.END_FEATURES[script["end"]]
    c.card_end(c.FEATURE_IMAGES / shot, caption).save(out / "end.png")
    segs.append(c.still(out / "end.png", 3.0, out / "segE.mp4"))
    c.concat(segs, out / "video.mp4")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
