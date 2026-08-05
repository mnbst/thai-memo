"""word_breakdown の欠落を検出し、欠落分だけ LLM に問い合わせて補完する。

文全体の発音は word_breakdown の各語の発音を連結して作っている（nlp.py）。
そのため word_breakdown に語の抜けがあると、発音からその語が丸ごと消える
（2026-08-05 実測: 622文中2件。例: ทางปิดหรอ งั้นไปทางไหนดี の2つ目の ทาง）。

文全体の再生成はコスト・レイテンシが見合わないため、欠落した文字列だけを
補完する小さなクエリを1回だけ投げる。補完に失敗した場合でも、発音だけは
thai_text から直接作り直して壊れたまま返さない。
"""

from typing import Any

try:
    from .pronunciation import thai_to_pronunciation
except ImportError:
    from pronunciation import thai_to_pronunciation


# 補完クエリのレスポンススキーマ。word と meaning だけを返させる。
GAP_RESPONSE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "words": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "word": {"type": "string"},
                    "meaning": {"type": "string"},
                },
                "required": ["word", "meaning"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["words"],
    "additionalProperties": False,
}

GAP_SYSTEM_PROMPT = (
    "タイ語文の単語分解から抜け落ちた部分を補う。"
    "指定された文字列だけを語に分け、word と meaning（日本語の語義）を返す。"
    "文全体を作り直さない。指定された文字列以外の語を足さない。"
)


def find_gaps(sentence: dict) -> list[tuple[int, str]]:
    """word_breakdown が thai_text を再構成できない箇所を返す。

    Returns:
        [(word_breakdown への挿入位置, 欠落している文字列), ...]
        欠落が無ければ空リスト。
    """
    thai = (sentence.get("thai_text") or "").replace(" ", "")
    breakdown = sentence.get("word_breakdown") or []
    if not thai:
        return []

    gaps: list[tuple[int, str]] = []
    pos = 0
    for index, entry in enumerate(breakdown):
        word = (entry.get("word") or "").replace(" ", "")
        if not word:
            continue
        found = thai.find(word, pos)
        if found < 0:
            # word_breakdown に thai_text へ無い語がある。補完では直せないため
            # 呼び出し側の発音フォールバックに任せる。
            return [(-1, "")]
        if found > pos:
            gaps.append((index, thai[pos:found]))
        pos = found + len(word)

    if pos < len(thai):
        gaps.append((len(breakdown), thai[pos:]))
    return gaps


def build_gap_prompt(thai_text: str, gaps: list[tuple[int, str]]) -> str:
    """欠落文字列を補完させる user prompt を組み立てる。"""
    segments = "／".join(seg for _, seg in gaps)
    return (
        f"タイ語文:\n<thai_text>\n{thai_text}\n</thai_text>\n\n"
        f"単語分解から抜けている文字列:\n<missing>\n{segments}\n</missing>\n\n"
        "抜けている文字列だけを語に分け、出現順に words へ入れて返す。"
    )


def apply_gap_words(sentence: dict, gaps: list[tuple[int, str]], filled: list[dict]) -> bool:
    """補完結果を word_breakdown の正しい位置へ挿入する。

    Returns:
        挿入後に thai_text を再構成できれば True。
    """
    if not filled:
        return False
    breakdown = list(sentence.get("word_breakdown") or [])
    remaining = [
        {"word": (w.get("word") or "").strip(), "meaning": (w.get("meaning") or "").strip()}
        for w in filled
        if (w.get("word") or "").strip()
    ]

    # 後ろの位置から挿入するとインデックスがずれない。
    for index, segment in sorted(gaps, key=lambda g: g[0], reverse=True):
        picked: list[dict] = []
        joined = ""
        while remaining and joined != segment:
            candidate = remaining.pop()
            picked.insert(0, candidate)
            joined = "".join(w["word"] for w in picked)
        if joined != segment:
            return False
        breakdown[index:index] = picked

    sentence["word_breakdown"] = breakdown
    return not find_gaps(sentence)


def repair_pronunciation(sentence: dict) -> None:
    """word_breakdown を直せなかったときに、文全体の発音だけ作り直す。

    表記は通常経路（語ごとに変換してスペース結合）に揃える。thai_text を
    そのまま一括変換すると全音節がハイフンで繋がり、語の切れ目が読めなくなる。
    """
    thai = sentence.get("thai_text") or ""
    if not thai:
        return
    try:
        words = _tokenize_words(thai)
        if words:
            sentence["pronunciation"] = " ".join(
                thai_to_pronunciation(w) for w in words
            )
        else:
            sentence["pronunciation"] = thai_to_pronunciation(thai)
    except Exception as exc:  # 発音変換の失敗で生成全体を落とさない
        print(f"word_gap: pronunciation fallback failed: {exc}")


def _tokenize_words(thai_text: str) -> list[str]:
    """thai_text を語に分割する。分割できなければ空リスト。

    pythainlp.tokenize は nlp.py が subword_tokenize で既に読み込んでいるため、
    ここでの import による追加のコールドスタントコストは無い。
    """
    try:
        from pythainlp.tokenize import word_tokenize
    except Exception as exc:
        print(f"word_gap: tokenizer unavailable: {exc}")
        return []
    return [w for w in word_tokenize(thai_text) if w.strip()]
