"""テーマ・サブテーマの embedding を作る。

ラベルの正本は functions/go/internal/sentence/prompts_data.go。
手で写すと Go 側だけ改名されて embedding が古いラベルのまま残るので、
cmd/corpus -labels に書き出させたものを読む。

既定は差分だけ。既存の値には触らない（閾値 uvm.TopicMatchThreshold は
今の embedding に対して決めてあるため、全部作り直すと基準がずれる）。

usage:
  cd functions/go && go run ./cmd/corpus -labels /tmp/labels.json
  uv run --with numpy,google-cloud-aiplatform \
    python scripts/build_theme_embeddings.py /tmp/labels.json
  # --all を付けると全ラベルを作り直す
"""

import json
import sys
from pathlib import Path

from vertexai.language_models import TextEmbeddingModel

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "scripts" / "corpus"
TOPIC_OUT = CORPUS / "topic_embeddings.json"
SUB_OUT = CORPUS / "sub_theme_embeddings.json"
DIM = 768  # vocab_embeddings.npy と揃える。ずれると次元不一致で候補から落ちる
MODEL = "gemini-embedding-001"


def load(path: Path) -> dict[str, list[float]]:
    if not path.exists():
        return {}
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def sync(model, name: str, path: Path, labels: list[str], rebuild: bool) -> None:
    current = load(path)
    stale = sorted(set(current) - set(labels))
    missing = [l for l in labels if rebuild or l not in current]

    if not missing and not stale:
        print(f"{name}: 変更なし（{len(current)}件）")
        return

    kept = {} if rebuild else {k: v for k, v in current.items() if k in set(labels)}
    for i in range(0, len(missing), 100):
        batch = missing[i : i + 100]
        for label, emb in zip(batch, model.get_embeddings(batch, output_dimensionality=DIM)):
            kept[label] = list(emb.values)
        print(f"  {min(i + 100, len(missing))}/{len(missing)}")

    # 並びは labels の順に揃える（差分を読めるようにするため）
    ordered = {l: kept[l] for l in labels if l in kept}
    with open(path, "w", encoding="utf-8") as f:
        json.dump(ordered, f, ensure_ascii=False)
    print(f"{name}: +{len(missing)} -{len(stale)} -> {len(ordered)}件 {path}")
    for s in stale:
        print(f"    削除: {s}")


def main() -> None:
    args = [a for a in sys.argv[1:] if a != "--all"]
    rebuild = "--all" in sys.argv[1:]
    labels_path = Path(args[0]) if args else Path("/tmp/labels.json")
    with open(labels_path, encoding="utf-8") as f:
        labels = json.load(f)

    topics = labels["topics"]
    subs: list[str] = []
    for topic in topics:
        for s in labels["sub_themes"].get(topic, []):
            if s not in subs:
                subs.append(s)

    model = TextEmbeddingModel.from_pretrained(MODEL)
    sync(model, "topic", TOPIC_OUT, topics, rebuild)
    sync(model, "sub_theme", SUB_OUT, subs, rebuild)


if __name__ == "__main__":
    main()
