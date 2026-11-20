"""例文の縦動画を組む。

test/screenshots/tiktok_video_screenshot.dart が書き出した連番フレーム
（<frames>/frames/、<frames>/frames.json）に、frames.json の audio
（<out> にあるファイル・鳴らし始める位置・切る位置）を重ねて mp4 にする。
大きさは 1080x1920（9:16）。

--bgm を渡すと BGM を小さく敷く。読み上げの間はさらに下げ（サイドチェーン）、
尺に合わせてループし、最後はフェードアウトする。音源は fetch_bgm.py が GCS から取る
（ライセンス上、音源ファイルは公開リポジトリに置けない）。

出力: <out>/<target>（既定 post.mp4）
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

SIZES = {"tiktok": (1080, 1920)}
# BGM の大きさ（ラウドネス）。曲ごとの音量差をならす。読み上げ（約 -16 LUFS）より
# 10dB ほど小さく、読み上げ中はここからさらに下がる。
BGM_LUFS = -28
BGM_FADE_MS = 1500


def _place(index: int, clip: dict, label: int) -> str:
    """音声を at_ms から鳴らす。end_ms（動画上の位置）があればそこで切る。"""
    at = int(clip["at_ms"])
    trim = ""
    if "end_ms" in clip:
        length = max(int(clip["end_ms"]) - at, 0)
        trim = f"atrim=end={length / 1000:.3f},"
    return f"[{index}:a]{trim}adelay=delays={at}:all=1[a{label}]"


def _bgm_graph(index: int, total_ms: int, voice: str | None) -> str:
    """BGM を [a] に出す。voice（読み上げのラベル）があれば、その間は下げて重ねる。"""
    fade_at = max(total_ms - BGM_FADE_MS, 0) / 1000
    bgm = (
        f"[{index}:a]atrim=end={total_ms / 1000:.3f},"
        f"loudnorm=I={BGM_LUFS}:TP=-9:LRA=11,aresample=44100,"
        f"afade=t=out:st={fade_at:.3f}:d={BGM_FADE_MS / 1000:.3f}[bg]"
    )
    if voice is None:
        return f"{bgm};[bg]anull[a]"
    return ";".join([
        bgm,
        # sidechaincompress は短い方の入力で止まるので、読み上げを尺まで無音で伸ばしてから分ける。
        # 伸ばさないと最後の読み上げ以降の BGM が消える。
        f"[{voice}]apad=whole_dur={total_ms}ms,asplit=2[voice][key]",
        "[bg][key]sidechaincompress=threshold=0.02:ratio=6:attack=20:release=500[duck]",
        "[voice][duck]amix=inputs=2:normalize=0[a]",
    ])


def build(out: Path, frames: Path, fmt: str, target: Path,
          bgm: Path | None = None) -> Path | None:
    width, height = SIZES[fmt]
    meta = json.loads((frames / "frames.json").read_text())
    fps = int(meta["fps"])
    total_ms = round(int(meta["count"]) * 1000 / fps)
    clips = [c for c in meta.get("audio", []) if (out / c["file"]).exists()]

    command = ["ffmpeg", "-y", "-framerate", str(fps),
               "-i", str(frames / "frames" / "frame_%04d.png")]
    for clip in clips:
        command += ["-i", str(out / clip["file"])]
    if bgm:
        # 尺より短い曲もあるのでループさせ、atrim で尺に切る。
        command += ["-stream_loop", "-1", "-i", str(bgm)]

    # 書き出しの高さは論理座標の端数で1〜2px ずれることがあるので、大きさを決め打ちする。
    video = f"[0:v]scale={width}:{height}:flags=lanczos,setsar=1[v]"
    bgm_index = len(clips) + 1
    if clips:
        delayed = [_place(i + 1, c, i) for i, c in enumerate(clips)]
        mixed = "".join(f"[a{i}]" for i in range(len(clips)))
        if bgm:
            audio = (f"{mixed}amix=inputs={len(clips)}:normalize=0[speech];"
                     + _bgm_graph(bgm_index, total_ms, "speech"))
        else:
            # 無音の詰め物は尺で打ち切る。無制限だと ffmpeg が音声を作り続ける。
            audio = f"{mixed}amix=inputs={len(clips)}:normalize=0,apad=whole_dur={total_ms}ms[a]"
        graph = ";".join([video, *delayed, audio])
    elif bgm:
        graph = ";".join([video, _bgm_graph(bgm_index, total_ms, None)])
    else:
        # TikTok は無音でも音声トラックがある方が扱いやすい。
        command += ["-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo"]
        graph = f"{video};[1:a]anull[a]"

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
    parser.add_argument("--frames", help="連番フレームの置き場（既定は --out）")
    parser.add_argument("--format", choices=sorted(SIZES), default="tiktok")
    parser.add_argument("--target", default="post.mp4", help="--out からの出力先")
    parser.add_argument("--bgm", type=Path, help="敷く BGM（無ければ付けない）")
    args = parser.parse_args()
    out = Path(args.out)
    target = out / args.target
    target.parent.mkdir(parents=True, exist_ok=True)
    frames = Path(args.frames) if args.frames else out
    bgm = args.bgm if args.bgm and args.bgm.exists() else None
    if args.bgm and not bgm:
        print(f"BGM が無いので付けない: {args.bgm}", file=sys.stderr)
    return 0 if build(out, frames, args.format, target, bgm) else 1


if __name__ == "__main__":
    raise SystemExit(main())
