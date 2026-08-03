"""key_word の語クラス辞書（word_classes.json）を読む。

分類とルール文はすべて JSON 側に置き、ここはロードと逆引きだけを持つ。
ルールを増やすときは JSON にクラスを足す（このモジュールの変更は不要）。

nlp._POS_OVERRIDE と語が重なるが、あちらは pythainlp を引き込むため import しない
（例文生成パスのコールドスタートを増やさないため）。
"""

import json
import os

_JSON_PATH = os.path.join(os.path.dirname(__file__), "word_classes.json")

with open(_JSON_PATH, encoding="utf-8") as _f:
    CLASSES: dict[str, dict] = json.load(_f)["classes"]

# 単語 → クラスID。同じ語が複数クラスに現れた場合は先に定義したクラスを採用する。
_WORD_TO_CLASS: dict[str, str] = {}
for _cid, _c in CLASSES.items():
    for _w in _c["words"]:
        _WORD_TO_CLASS.setdefault(_w, _cid)


def classify(word: str) -> str | None:
    """語のクラスIDを返す。未分類（内容語）なら None。"""
    return _WORD_TO_CLASS.get(word)


def classify_all(words: list[str] | None) -> list[str]:
    """ターゲット語のクラスIDを、重複を除いて出現順に返す。"""
    if not words:
        return []
    seen: list[str] = []
    for w in words:
        cid = classify(w)
        if cid and cid not in seen:
            seen.append(cid)
    return seen


def is_function_word(word: str) -> bool:
    cid = classify(word)
    return bool(cid and CLASSES[cid].get("function_word"))
