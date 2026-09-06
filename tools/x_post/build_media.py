"""読み上げ音声と画面フレームから投稿用の動画を組む。

画像（image_1.png ...）はスクリーンショットのテストが直接書き出す。ここでは
「お手本を聞く」を押す操作の連番フレームに音声を載せて mp4 にする。フレームが
無ければ1枚目の画像に音声を載せた静止動画へ落とす。X は音声単体を投稿できない。

出力: <out>/post.mp4
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

# X の動画は 1:3〜3:1 の範囲。縦長すぎる静止画は上端だけ使う。
MAX_VIDEO_RATIO = 2.0


def build_video(out: Path) -> Path | None:
    audio = out / "audio.mp3"
    if not audio.exists():
        return None

    video = out / "post.mp4"
    frames = out / "frames"
    meta_path = out / "frames.json"
    if frames.is_dir() and meta_path.exists():
        _encode_frames(frames, json.loads(meta_path.read_text()), audio, video)
        return video

    card = out / "image_1.png"
    if not card.exists():
        return None
    print("フレームが無いので静止画で動画を作る", file=sys.stderr)
    _encode_still(card, out, audio, video)
    return video


def _encode_frames(frames: Path, meta: dict, audio: Path, video: Path) -> None:
    """連番PNGと音声から動画を作る。音声はタップした位置から鳴らす。"""
    delay = int(meta.get("audio_delay_ms", 0))
    fps = int(meta.get("fps", 20))
    subprocess.run(
        [
            "ffmpeg", "-y",
            "-framerate", str(fps),
            "-i", str(frames / "frame_%04d.png"),
            "-i", str(audio),
            "-filter_complex",
            "[0:v]scale=trunc(iw/2)*2:trunc(ih/2)*2[v];"
            f"[1:a]adelay={delay}|{delay},apad[a]",
            "-map", "[v]", "-map", "[a]",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-r", str(fps),
            "-c:a", "aac", "-b:a", "128k",
            "-shortest",
            "-movflags", "+faststart",
            str(video),
        ],
        check=True,
        capture_output=True,
    )


def _encode_still(card: Path, out: Path, audio: Path, video: Path) -> None:
    """フレームが無いときの保険。1枚目の画像に音声を載せる。"""
    image = Image.open(card)
    width, height = image.size
    if height > width * MAX_VIDEO_RATIO:
        height = int(width * MAX_VIDEO_RATIO)
        card = out / "video_frame.png"
        image.crop((0, 0, width, height)).save(card)

    subprocess.run(
        [
            "ffmpeg", "-y",
            "-loop", "1",
            "-i", str(card),
            "-i", str(audio),
            "-c:v", "libx264",
            "-tune", "stillimage",
            "-pix_fmt", "yuv420p",
            "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
            "-r", "30",
            "-c:a", "aac", "-b:a", "128k",
            "-shortest",
            "-movflags", "+faststart",
            str(video),
        ],
        check=True,
        capture_output=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="build/x_post")
    args = parser.parse_args()

    build_video(Path(args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
