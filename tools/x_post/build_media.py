"""スクリーンショットと音声から投稿メディアを組む。

- screen.png（画面まるごと1枚の縦長）を X の上限4枚に収まるよう均等に分割する。
- 1枚目と音声を ffmpeg で mp4 にする。X は音声単体を投稿できないため。

出力: <out>/image_1.png ... image_N.png、<out>/post.mp4
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from pathlib import Path

from PIL import Image

MAX_IMAGES = 4
# X の動画は 1:3〜3:1 の範囲。縦長すぎる1枚目は上端だけ使う。
MAX_VIDEO_RATIO = 2.0


def slice_screen(out: Path) -> list[Path]:
    meta = json.loads((out / "screen.json").read_text())
    image = Image.open(out / "screen.png").convert("RGB")
    width, height = image.size

    count = min(MAX_IMAGES, max(1, math.ceil(height / meta["tile_height"])))
    tile = math.ceil(height / count)

    paths = []
    for index in range(count):
        top = index * tile
        bottom = min(height, top + tile)
        if bottom - top < tile * 0.2 and paths:
            # 端数だけの帯は前の1枚に含める。細長い切れ端を出さない。
            break
        path = out / f"image_{index + 1}.png"
        image.crop((0, top, width, bottom)).save(path)
        paths.append(path)
    return paths


def build_video(out: Path, card: Path) -> Path | None:
    audio = out / "audio.mp3"
    if not audio.exists():
        return None

    image = Image.open(card)
    width, height = image.size
    if height > width * MAX_VIDEO_RATIO:
        height = int(width * MAX_VIDEO_RATIO)
        card = out / "video_frame.png"
        image.crop((0, 0, width, height)).save(card)

    video = out / "post.mp4"
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-loop",
            "1",
            "-i",
            str(card),
            "-i",
            str(audio),
            "-c:v",
            "libx264",
            "-tune",
            "stillimage",
            "-pix_fmt",
            "yuv420p",
            "-vf",
            "scale=trunc(iw/2)*2:trunc(ih/2)*2",
            "-r",
            "30",
            "-c:a",
            "aac",
            "-b:a",
            "128k",
            "-shortest",
            "-movflags",
            "+faststart",
            str(video),
        ],
        check=True,
        capture_output=True,
    )
    return video


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="build/x_post")
    args = parser.parse_args()

    out = Path(args.out)
    images = slice_screen(out)
    build_video(out, images[0])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
