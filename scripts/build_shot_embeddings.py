"""BLドラマの参考セリフの embedding を作る。

セリフの正本は functions/go/internal/bldrama/data.go の shots。
FindBestDramaShot はセリフ本文で embedding を引き、無いセリフは候補から外すので、
セリフを足したらこれを流して upload_corpus.sh で GCS に上げる。

既定は差分だけ。既存の値には触らない。

usage:
  uv run --with google-cloud-aiplatform python scripts/build_shot_embeddings.py
  # --all を付けると全セリフを作り直す
"""

import json
import re
import sys
from pathlib import Path

from vertexai.language_models import TextEmbeddingModel

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "functions" / "go" / "internal" / "bldrama" / "data.go"
OUT = ROOT / "scripts" / "corpus" / "shot_embeddings.json"
DIM = 768  # vocab_embeddings.npy と揃える。ずれると次元不一致で候補から落ちる
MODEL = "gemini-embedding-001"


def load_shots() -> list[str]:
    src = DATA.read_text(encoding="utf-8")
    block = src[src.index("var shots = map[string]string{") : src.index("\n}\n")]
    return [json.loads(m) for m in re.findall(r'^\t"[a-z]+_\d+": ("(?:[^"\\]|\\.)*"),$', block, re.M)]


def main() -> None:
    rebuild = "--all" in sys.argv[1:]
    shots = load_shots()
    current = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else {}
    stale = sorted(set(current) - set(shots))
    missing = [s for s in shots if rebuild or s not in current]
    if not missing and not stale:
        print(f"変更なし（{len(current)}件）")
        return

    kept = {} if rebuild else {k: v for k, v in current.items() if k in set(shots)}
    model = TextEmbeddingModel.from_pretrained(MODEL)
    for i in range(0, len(missing), 100):
        batch = missing[i : i + 100]
        for text, emb in zip(batch, model.get_embeddings(batch, output_dimensionality=DIM)):
            kept[text] = list(emb.values)
        print(f"  {min(i + 100, len(missing))}/{len(missing)}")

    ordered = {s: kept[s] for s in shots if s in kept}
    OUT.write_text(json.dumps(ordered, ensure_ascii=False), encoding="utf-8")
    print(f"+{len(missing)} -{len(stale)} -> {len(ordered)}件 {OUT}")
    for s in stale:
        print(f"    削除: {s}")


if __name__ == "__main__":
    main()
