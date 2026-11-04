"""機能紹介の台本（scripts.json の kind=feature）から TikTok 用の縦動画を組む。

構成: 書き出し（日本語）→ 固定のスクショに本文を1枚ずつ字幕＋読み上げ → アプリ名の締め
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

import common as c

SHOT_H = 1180  # スクショを置く高さ（字幕の上）


def caption_layer(text: str) -> Image.Image:
    img = Image.new("RGBA", (c.W, c.H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f, lines = c.fit(d, text, c.JP_BOLD, 60, 40, c.SAFE_W, max_lines=3, sentences=True)
    lh = f.size * 1.45
    top = c.SAFE_TOP + SHOT_H + 40
    d.rounded_rectangle((60, top - 24, c.W - 60, top + len(lines) * lh + 10), 28, fill=c.INDIGO + (235,))
    y = top
    for line in lines:
        c.draw_line(img, y, line, f, c.PAPER)
        y += lh
    return img


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--id", required=True)
    p.add_argument("--out", required=True)
    a = p.parse_args()

    post = c.load_post(a.id)
    script = c.load_script(a.id)
    body = script["slides"] + [script["outro"]]
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    hv = c.synth(script["hook"]["say"], out / "hook.mp3")
    c.card_hook(script["hook"]["text"], c.STR["app"]).save(out / "f0.png")
    segs = [c.still(out / "f0.png", max(1.8, c.duration(hv) + 0.4), out / "seg0.mp4", hv, fade_in=False)]

    bg = c.base()
    shot = Image.open(c.FEATURE_IMAGES / Path(post["image_file"]).name).convert("RGB")
    shot.thumbnail((c.W, SHOT_H))
    bg.paste(shot, ((c.W - shot.width) // 2, c.SAFE_TOP))
    bg.save(out / "bg.png")

    for i, slide in enumerate(body, 1):
        text = slide["text"]
        voice = c.synth(slide["say"], out / f"b{i}.mp3")
        sec = c.duration(voice) + 0.5
        # スクショは動かさず、字幕だけ差し替える（寄せる動きは酔うと言われた）。
        frame = Image.open(out / "bg.png").convert("RGBA")
        frame.alpha_composite(caption_layer(text))
        frame.convert("RGB").save(out / f"s{i}.png")
        segs.append(c.still(out / f"s{i}.png", sec, out / f"seg{i}.mp4", voice, fade_in=i == 1))

    c.card_end(None, None).save(out / "end.png")
    segs.append(c.still(out / "end.png", 2.5, out / "segE.mp4"))
    c.concat(segs, out / "video.mp4")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
