"""動画に敷く BGM を GCS（gs://<project>-uvm-data/x_post/bgm/）から1曲取ってくる。

音源は OpenTracks（旧 DOVA-SYNDROME）のフリー BGM。ライセンス上、音源ファイルを
公開の場所（このリポジトリ）に置けないので、非公開のバケットに置いて動画を作るときだけ取る。
クレジット表記は不要。曲を足すときは同じ場所に mp3 を置く（ファイル名は英数字）。

曲は種（日付と枠）から決める。同じ日の枠で偏らないよう、種のハッシュで選ぶ。
取れなくても動画は作る（BGM なしになるだけ）ので、失敗しても終了コードは 0。

  python tools/x_post/fetch_bgm.py --project thai-memo-prod --seed 2026-11-19-1900 --out build/x_post/bgm.mp3
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

from google.cloud import storage

PREFIX = "x_post/bgm/"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--seed", required=True)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    try:
        bucket = storage.Client(project=args.project).bucket(f"{args.project}-uvm-data")
        blobs = sorted(
            (b for b in bucket.list_blobs(prefix=PREFIX) if b.name.endswith(".mp3")),
            key=lambda b: b.name,
        )
        if not blobs:
            print("BGM が置かれていないので付けない", file=sys.stderr)
            return 0
        index = int(hashlib.sha256(args.seed.encode()).hexdigest(), 16) % len(blobs)
        blob = blobs[index]
        args.out.parent.mkdir(parents=True, exist_ok=True)
        blob.download_to_filename(str(args.out))
        print(f"BGM: {blob.name.removeprefix(PREFIX)}")
    except Exception as error:  # noqa: BLE001 BGM は無くても投稿を止めない
        print(f"BGM を取れなかったので付けない: {error}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
