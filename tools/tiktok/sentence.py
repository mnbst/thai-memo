"""例文の X 投稿の素材（x-post-media の text.txt・post.mp4）から TikTok 用の縦動画を組む。

構成: 書き出し（日本語）→ タイ語＋発音（タイ語の読み上げ）→ 訳（日本語）→ アプリ画面の操作 → 機能の締め
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

import common as c


def card_sentence(label: str, thai: str, ipa: str, ja: str | None) -> Image.Image:
    img = c.base(label)
    d = ImageDraw.Draw(img)
    ft, tl = c.fit(d, thai, c.THAI, 110, 60, c.SAFE_W, max_lines=3)
    fi, il = c.fit(d, ipa, c.IPA, 46, 34, c.SAFE_W, max_lines=3)
    fj, jl = c.fit(d, ja, c.JP_BOLD, 60, 44, c.SAFE_W, max_lines=3) if ja else (None, [])
    blocks = [(ft, tl, c.INDIGO, 1.45), (fi, il, c.MUTED, 1.4)]
    total = sum(f.size * r * len(l) for f, l, _, r in blocks) + 30
    jh = 130 + (fj.size * 1.45 * len(jl) if fj else 0)
    y = c.CENTER_Y - (total + jh) / 2
    for f, ls, color, r in blocks:
        for line in ls:
            c.draw_line(img, y, line, f, color)
            y += f.size * r
        y += 30
    if ja:
        y += 40
        d.rectangle((c.W / 2 - 60, y, c.W / 2 + 60, y + 8), fill=c.GOLD)
        y += 60
        for line in jl:
            c.draw_line(img, y, line, fj, c.INDIGO)
            y += fj.size * 1.45
    return img


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--media", required=True)
    p.add_argument("--end", default="quiz", choices=sorted(c.END_FEATURES), help="締めに出す機能")
    p.add_argument("--out", required=True)
    a = p.parse_args()

    media, out = Path(a.media), Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    lines = [l for l in (media / "text.txt").read_text().splitlines() if l.strip()]
    hook, thai, ipa, ja = lines[:4]
    label = c.plain(hook)

    voice = out / "voice.wav"
    c.run(["ffmpeg", "-y", "-i", str(media / "post.mp4"), "-vn", "-af",
           "silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
           "silenceremove=start_periods=1:start_threshold=-45dB,areverse",
           "-ar", "44100", "-ac", "2", str(voice)])
    hv = c.synth(label, out / "hook.mp3")
    jv = c.synth(ja, out / "ja.mp3")

    c.card_hook(hook, c.STR["today"]).save(out / "s1.png")
    card_sentence(label, thai, ipa, None).save(out / "s2.png")
    card_sentence(label, thai, ipa, ja).save(out / "s3.png")
    shot, caption = c.END_FEATURES[a.end]
    c.card_end(c.FEATURE_IMAGES / shot, caption).save(out / "s5.png")

    segs = [
        c.still(out / "s1.png", max(1.8, c.duration(hv) + 0.4), out / "seg1.mp4", hv, fade_in=False),
        c.still(out / "s2.png", c.duration(voice) + 0.6, out / "seg2.mp4", voice),
        c.still(out / "s3.png", c.duration(jv) + 0.6, out / "seg3.mp4", jv, fade_in=False),
    ]

    # アプリ画面の操作（元動画の音声ごと）。上に見出し、下は TikTok の説明文に被るので空ける。
    overlay = c.base()
    od = ImageDraw.Draw(overlay)
    for i, line in enumerate(["アプリでは単語の分解と", "お手本の音声も使えます"]):
        c.draw_line(overlay, c.SAFE_TOP - 40 + i * 84, line, c.font(c.JP_BOLD, 60), c.INDIGO)
    overlay.save(out / "s4.png")
    vh = c.H - 380 - 380
    c.run(["ffmpeg", "-y", "-loop", "1", "-i", str(out / "s4.png"), "-i", str(media / "post.mp4"),
           "-filter_complex",
           f"[1:v]scale=-2:{vh - 40}[app];[0:v][app]overlay=(W-w)/2:380,format=yuv420p,fade=t=in:st=0:d=0.25[v];"
           "[1:a]aresample=44100,aformat=channel_layouts=stereo[a]",
           "-map", "[v]", "-map", "[a]", "-shortest", *c.ENC, str(out / "seg4.mp4")])
    segs.append(out / "seg4.mp4")
    segs.append(c.still(out / "s5.png", 3.0, out / "seg5.mp4"))
    c.concat(segs, out / "video.mp4")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
