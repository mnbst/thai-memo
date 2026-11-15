"""例文の縦動画を組む（X・Threads・TikTok で共通）。

test/screenshots/tiktok_video_screenshot.dart が書き出した連番フレームに、
frames.json の audio（ファイル・鳴らし始める位置・切る位置）を重ねて mp4 にする。
幅 1080 に縮める（端末の縦長のまま。TikTok は画面収録と同じ比率で出せる）。

出力: <out>/post.mp4
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

WIDTH = 1080


def _place(index: int, clip: dict, label: int) -> str:
    """音声を at_ms から鳴らす。end_ms（動画上の位置）があればそこで切る。"""
    at = int(clip["at_ms"])
    trim = ""
    if "end_ms" in clip:
        length = max(int(clip["end_ms"]) - at, 0)
        trim = f"atrim=end={length / 1000:.3f},"
    return f"[{index}:a]{trim}adelay=delays={at}:all=1[a{label}]"


def build(out: Path) -> Path | None:
    meta = json.loads((out / "frames.json").read_text())
    fps = int(meta["fps"])
    total_ms = round(int(meta["count"]) * 1000 / fps)
    clips = [c for c in meta.get("audio", []) if (out / c["file"]).exists()]

    command = ["ffmpeg", "-y", "-framerate", str(fps),
               "-i", str(out / "frames" / "frame_%04d.png")]
    for clip in clips:
        command += ["-i", str(out / clip["file"])]

    video = f"[0:v]scale={WIDTH}:-2:flags=lanczos[v]"
    if clips:
        delayed = [_place(i + 1, c, i) for i, c in enumerate(clips)]
        mixed = "".join(f"[a{i}]" for i in range(len(clips)))
        # 無音の詰め物は尺で打ち切る。無制限だと ffmpeg が音声を作り続ける。
        audio = f"{mixed}amix=inputs={len(clips)}:normalize=0,apad=whole_dur={total_ms}ms[a]"
        graph = ";".join([video, *delayed, audio])
    else:
        # TikTok は無音でも音声トラックがある方が扱いやすい。
        command += ["-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo"]
        graph = f"{video};[1:a]anull[a]"

    target = out / "post.mp4"
    command += [
        "-filter_complex", graph,
        "-map", "[v]", "-map", "[a]",
        "-t", f"{total_ms / 1000:.3f}",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "30",
        "-c:a", "aac", "-b:a", "128k",
        "-movflags", "+faststart",
        str(target),
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr[-2000:], file=sys.stderr)
        return None
    return target


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="build/x_post")
    args = parser.parse_args()
    return 0 if build(Path(args.out)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
