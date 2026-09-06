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


def _run(command: list[str]) -> bool:
    """ffmpeg を実行する。失敗したら ffmpeg の言い分をそのまま出す。"""
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode == 0:
        return True
    print(f"ffmpeg が失敗した（{result.returncode}）", file=sys.stderr)
    print(result.stderr[-2000:], file=sys.stderr)
    return False


def build_video(out: Path) -> Path | None:
    audio = out / "audio.mp3"
    if not audio.exists():
        return None

    video = out / "post.mp4"
    frames = out / "frames"
    meta_path = out / "frames.json"
    if frames.is_dir() and meta_path.exists():
        if _encode_frames(frames, json.loads(meta_path.read_text()), audio, video):
            return video
        print("操作の録画を組めなかった。静止画に落とす", file=sys.stderr)

    # 保険。動画が無くても画像とテキストは出せるので、ここで止めない。
    card = out / "image_1.png"
    if not card.exists():
        return None
    if not _encode_still(card, out, audio, video):
        return None
    return video


def _encode_frames(frames: Path, meta: dict, audio: Path, video: Path) -> bool:
    """連番PNGと音声から動画を作る。音声はタップした位置から鳴らす。"""
    delay = int(meta.get("audio_delay_ms", 0))
    fps = int(meta.get("fps", 20))
    count = int(meta.get("count", 0))
    # フレーム数で尺が決まる。無音の詰め物もここで打ち切る。`apad` を
    # 無制限にすると ffmpeg が音声を作り続けて filtering で落ちる。
    total_ms = round(count * 1000 / fps)
    return _run(
        [
            "ffmpeg", "-y",
            "-framerate", str(fps),
            "-i", str(frames / "frame_%04d.png"),
            "-i", str(audio),
            "-filter_complex",
            "[0:v]scale=trunc(iw/2)*2:trunc(ih/2)*2[v];"
            # 音声はモノラルのことがある。all=1 で全チャンネルに同じ遅延を掛ける。
            f"[1:a]adelay=delays={delay}:all=1,apad=whole_dur={total_ms}ms[a]",
            "-map", "[v]", "-map", "[a]",
            "-t", f"{total_ms / 1000:.3f}",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-r", str(fps),
            "-c:a", "aac", "-b:a", "128k",
            "-movflags", "+faststart",
            str(video),
        ],
    )


def _encode_still(card: Path, out: Path, audio: Path, video: Path) -> bool:
    """フレームが無いときの保険。1枚目の画像に音声を載せる。"""
    image = Image.open(card)
    width, height = image.size
    if height > width * MAX_VIDEO_RATIO:
        height = int(width * MAX_VIDEO_RATIO)
        card = out / "video_frame.png"
        image.crop((0, 0, width, height)).save(card)

    return _run(
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
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="build/x_post")
    args = parser.parse_args()

    build_video(Path(args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
