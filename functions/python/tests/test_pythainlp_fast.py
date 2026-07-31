"""軽量ロードした PyThaiNLP が、通常 import と同じ結果を返すことを確認する。

軽量ロードは sys.modules にスタブを差し込むため、同一プロセス内で通常 import と
共存できない。両方の結果を比べるには別プロセスで実行して出力を突き合わせる。
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# nlp.py が実際に使っている呼び出しパターン（nlp.py の pos_tag / segment_syllables）。
CASES = [
    ["ผม", "กิน", "ข้าว", "ครับ"],
    ["เขา", "ไป", "ตลาด", "เมื่อวาน", "นะ"],
    ["แพนด้า", "น่ารัก", "มาก"],
]
SYLLABLE_WORDS = ["สวัสดี", "ขอบคุณ", "แพนด้า", "โรงเรียน"]

_SCRIPT = """
import json, sys
sys.path.insert(0, {root!r})
mode = sys.argv[1]
if mode == "fast":
    from pythainlp_fast import pos_tag, subword_tokenize, is_fast_path
    assert is_fast_path(), "fast path not taken"
else:
    from pythainlp.tag import pos_tag
    from pythainlp.tokenize import subword_tokenize

cases = json.loads(sys.argv[2])
words = json.loads(sys.argv[3])
out = {{
    "perceptron": [pos_tag(c, engine="perceptron", corpus="orchid_ud") for c in cases],
    "unigram": [pos_tag(c, engine="unigram", corpus="tud") for c in cases],
    "syllables": [subword_tokenize(w, engine="dict") for w in words],
    "empty": pos_tag([], engine="unigram", corpus="tud"),
}}
print(json.dumps(out, ensure_ascii=False))
"""


def _run(mode: str) -> dict:
    proc = subprocess.run(
        [
            sys.executable,
            "-c",
            _SCRIPT.format(root=str(ROOT)),
            mode,
            json.dumps(CASES),
            json.dumps(SYLLABLE_WORDS),
        ],
        capture_output=True,
        text=True,
        cwd=str(ROOT),
    )
    assert proc.returncode == 0, f"{mode} failed:\n{proc.stderr}"
    return json.loads(proc.stdout.strip().splitlines()[-1])


def test_fast_import_matches_normal_import():
    assert _run("fast") == _run("normal")


def test_unsupported_engine_and_corpus_raise():
    from pythainlp_fast import pos_tag

    for kwargs in (
        {"engine": "tltk", "corpus": "tud"},
        {"engine": "unigram", "corpus": "nonexistent"},
    ):
        try:
            pos_tag(["ผม"], **kwargs)
        except ValueError:
            pass
        else:
            raise AssertionError(f"expected ValueError for {kwargs}")
