#!/usr/bin/env python3
"""cmd/translate の JSONL を、アプリに同梱する読み取り専用SQLiteにまとめる。

    python3 scripts/pack_corpus.py /tmp/corpus.jsonl assets/corpus.db

列名はアプリ側の既存テーブル（database_constants.dart）に合わせてある。
訳は日英を1行に持ち、表示時に app_language で選ぶ。

同じ (語, テーマ) が二重に入っている入力（途中再開で重複した行など）は
後の行で上書きする。訳に失敗した行（error 付き）は入れない。
"""

import json
import sqlite3
import sys
from pathlib import Path

DENYLIST_PATH = Path(__file__).parent / "word_denylist.json"

SCHEMA = """
PRAGMA journal_mode = DELETE;

CREATE TABLE corpus_sentences (
  id            INTEGER PRIMARY KEY,
  word_rank     INTEGER NOT NULL,
  target_word   TEXT    NOT NULL,
  topic         TEXT    NOT NULL,
  sub_theme     TEXT,
  thai_text     TEXT    NOT NULL,
  pronunciation TEXT,
  ja            TEXT    NOT NULL,
  en            TEXT    NOT NULL,
  note_ja       TEXT,
  note_en       TEXT,
  UNIQUE (target_word, topic)
);

CREATE TABLE corpus_words (
  sentence_id      INTEGER NOT NULL,
  word_order       INTEGER NOT NULL,
  word_text        TEXT    NOT NULL,
  ja               TEXT    NOT NULL,
  en               TEXT    NOT NULL,
  pronunciation    TEXT,
  syllables_json   TEXT,
  grammatical_role TEXT,
  PRIMARY KEY (sentence_id, word_order)
) WITHOUT ROWID;

CREATE INDEX idx_corpus_rank ON corpus_sentences(word_rank);
CREATE INDEX idx_corpus_word ON corpus_sentences(target_word);

CREATE TABLE corpus_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""


def load_denylist() -> set[str]:
    """除外語。生成後に判定が拾った語もここへ足すので、詰め込みでも弾く。"""
    data = json.loads(DENYLIST_PATH.read_text(encoding="utf-8"))
    return {
        w
        for key, cat in data.items()
        if not key.startswith("_")
        for w in cat["words"]
    }


def load(path: Path) -> list[dict]:
    # 後勝ちで重複を潰す。dict は挿入順を保つので語順は入力のまま。
    deny = load_denylist()
    rows: dict[tuple[str, str], dict] = {}
    for line in path.open(encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        r = json.loads(line)
        if r.get("error") or not r.get("ja") or not r.get("en"):
            continue
        if r["target_word"] in deny:
            continue
        rows[(r["target_word"], r["topic"])] = r
    return list(rows.values())


def build(rows: list[dict], out: Path) -> None:
    if out.exists():
        out.unlink()
    db = sqlite3.connect(out)
    db.executescript(SCHEMA)

    for i, r in enumerate(rows, start=1):
        db.execute(
            "INSERT INTO corpus_sentences VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (i, r["key_word_rank"], r["target_word"], r["topic"],
             r.get("sub_theme"), r["thai_text"], r.get("pronunciation"),
             r["ja"], r["en"], r.get("note_ja") or None, r.get("note_en") or None),
        )
        db.executemany(
            "INSERT INTO corpus_words VALUES (?,?,?,?,?,?,?,?)",
            [(i, k, w["word"], w["ja"], w["en"], w.get("pronunciation"),
              json.dumps(w["syllables"], ensure_ascii=False) if w.get("syllables") else None,
              w.get("grammatical_role"))
             for k, w in enumerate(r["words"])],
        )

    ranks = {r["key_word_rank"] for r in rows}
    db.executemany("INSERT INTO corpus_meta VALUES (?,?)", [
        ("schema_version", "1"),
        ("sentences", str(len(rows))),
        ("words", str(len(ranks))),
        ("max_rank", str(max(ranks) if ranks else 0)),
    ])
    db.commit()
    db.execute("VACUUM")
    db.close()


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    rows = load(src)
    if not rows:
        sys.exit(f"{src} に使える行がない")
    out.parent.mkdir(parents=True, exist_ok=True)
    build(rows, out)
    per_word: dict[str, int] = {}
    for r in rows:
        per_word[r["target_word"]] = per_word.get(r["target_word"], 0) + 1
    print(f"{out}  {out.stat().st_size / 1e6:.1f}MB")
    print(f"  {len(rows)}文 / {len(per_word)}語 / 平均 {len(rows) / len(per_word):.2f}文per語")


if __name__ == "__main__":
    main()
