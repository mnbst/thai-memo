"""sentence_service.py の生成フローを Python 実装から書き出す。

対象:
  - nlp.localize_pos           品詞ラベルの英訳
  - _apply_response_compat     target_notes の展開と context の注入
  - _generate_single           やり直しの制御フロー（LLM 呼び出しは差し替え）

LLM 呼び出しと NLP 後処理だけ差し替え、制御フローは本物をそのまま動かす。
Go 版 internal/sentence, internal/thainlp との差分テストに使う。

実行: functions/python/venv/bin/python scripts/daily_golden/gen_generate_golden.py
出力: functions/python/scripts/daily_golden/generate_golden.json
"""

import io
import json
import os
import random
import sys
from contextlib import redirect_stdout

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

import nlp  # noqa: E402
import sentence_service as ss  # noqa: E402

THAI = ["ฉัน", "กิน", "ข้าว", "ไป", "ตลาด", "แมว", "สวย", "จริง", "นะ", "ครับ"]
POS_LABELS = [
    "名詞", "動詞", "形容詞", "副詞", "代名詞", "限定詞", "前置詞", "助動詞",
    "接続詞", "助詞", "感嘆詞", "数詞", "固有名詞", "句読点", "類別詞",
    "否定詞", "その他", "未知のラベル", "",
]


def sentence_dict(rng, words, thai=None):
    return {
        "thai_text": thai if thai is not None else "".join(words),
        "japanese_translation": "訳",
        "word_breakdown": [{"word": w, "meaning": f"{w}の意味"} for w in words],
    }


def main() -> None:
    rng = random.Random(20260829)
    out: dict = {}

    # --- localize_pos ---
    # lang は handlers 側で ja/en に正規化済みのものしか来ない。
    # Python 版は "ja" 以外を全て英語に倒すので、正規化前の値を入れると
    # Go 版（ja/en の型で受ける）と食い違う。実入力に合わせて ja/en だけ見る。
    out["localize_pos"] = [
        {"label": label, "lang": lang, "result": nlp.localize_pos(label, lang)}
        for label in POS_LABELS
        for lang in ("ja", "en")
    ]

    # --- _apply_response_compat ---
    compat = []
    for _ in range(1200):
        words = [rng.choice(THAI) for _ in range(rng.randint(1, 5))]
        # ๆ を混ぜて、空白の有無で表記が揺れる語を作る
        if rng.random() < 0.4:
            i = rng.randrange(len(words))
            words[i] = words[i] + rng.choice([" ๆ", "ๆ", "  ๆ"])
        sentence = sentence_dict(rng, words)

        notes = []
        for _ in range(rng.randint(0, 4)):
            target = rng.choice(words + THAI)
            if rng.random() < 0.5:
                target = target.replace(" ๆ", "ๆ") if " ๆ" in target else target + " "
            notes.append({"word": target, "note": f"{target}の補足"})
        if rng.random() < 0.15:
            notes.append({"word": rng.choice(words), "note": ""})
        sentence["target_notes"] = notes

        if rng.random() < 0.6:
            sentence["context"] = {
                k: rng.choice(["買い物", "丁寧", "うれしい", ""])
                for k in ("topic", "style", "emotion")
                if rng.random() < 0.7
            }
        resolved = None
        if rng.random() < 0.6:
            resolved = {
                k: rng.choice(["食べ物", "カジュアル", "おだやか"])
                for k in ("topic", "style", "emotion")
                if rng.random() < 0.6
            }
            if rng.random() < 0.2:
                resolved = {}

        before = json.loads(json.dumps(sentence))
        result = ss._apply_response_compat(sentence, resolved)
        compat.append({
            "sentence": before,
            "resolved_context": resolved,
            "result": result,
        })
    out["apply_response_compat"] = compat

    # --- enrich_with_nlp ---
    # 実際に生成された例文（scripts/output/）の word_breakdown を素材にする。
    import glob

    enrich_cases = []
    seen: set = set()
    for path_ in sorted(glob.glob(
        os.path.join(os.path.dirname(__file__), "..", "output", "*.json")
    )):
        try:
            data = json.load(open(path_, encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(data, list):
            continue
        for item in data:
            if not isinstance(item, dict):
                continue
            words = [
                str(wb.get("word", ""))
                for wb in item.get("word_breakdown") or []
                if isinstance(wb, dict)
            ]
            if not words:
                continue
            key = "|".join(words)
            if key in seen:
                continue
            seen.add(key)
            for lang_ in ("ja", "en"):
                sentence = {
                    "thai_text": item.get("thai_text", ""),
                    "word_breakdown": [{"word": w, "meaning": ""} for w in words],
                }
                nlp.enrich_with_nlp(sentence, lang_)
                enrich_cases.append({
                    "words": words,
                    "lang": lang_,
                    "enriched": [
                        {
                            "syllables": wb.get("syllables"),
                            "pronunciation": wb.get("pronunciation"),
                            "grammatical_role": wb.get("grammatical_role"),
                        }
                        for wb in sentence["word_breakdown"]
                    ],
                    "pronunciation": sentence.get("pronunciation", ""),
                })
            if len(seen) >= 600:
                break
        if len(seen) >= 600:
            break
    # 退化したケース。語が1つも無いと文全体の発音を作らない（既存値を残す）。
    for words in ([], [""], ["ๆ"], [" "], ["abc"], ["๑๒๓"], ["ฉัน", "", "กิน"]):
        for lang_ in ("ja", "en"):
            sentence = {
                "thai_text": "".join(words),
                "word_breakdown": [{"word": w, "meaning": ""} for w in words],
            }
            nlp.enrich_with_nlp(sentence, lang_)
            enrich_cases.append({
                "words": words,
                "lang": lang_,
                "enriched": [
                    {
                        "syllables": wb.get("syllables"),
                        "pronunciation": wb.get("pronunciation"),
                        "grammatical_role": wb.get("grammatical_role"),
                    }
                    for wb in sentence["word_breakdown"]
                ],
                "pronunciation": sentence.get("pronunciation", ""),
            })
    out["enrich"] = enrich_cases

    # --- _generate_single の制御フロー ---
    # LLM と NLP を差し替えて、何回・どのプロンプトで呼ばれたかを記録する。
    real_llm = ss._llm_generate_sync
    real_enrich = ss._enrich_with_nlp
    real_prewarm = ss._prewarm_nlp_async
    ss._enrich_with_nlp = lambda sentence, lang="ja": None
    ss._prewarm_nlp_async = lambda: None

    flows = []
    try:
        for case in flow_cases():
            calls: list = []
            responses = list(case["responses"])

            def fake_llm(system_prompt, prompt, is_premium, tier_label,
                         schema=None):
                calls.append({
                    "prompt": prompt,
                    "tier_label": tier_label,
                    "is_premium": is_premium,
                })
                if not responses:
                    raise RuntimeError("LLM_API_ERROR: no more responses")
                nxt = responses.pop(0)
                if isinstance(nxt, str):
                    raise RuntimeError(nxt)
                return json.loads(json.dumps(nxt))

            ss._llm_generate_sync = fake_llm
            record = {
                "name": case["name"],
                "prompt": case["prompt"],
                "target_words": case["target_words"],
                "responses": case["responses"],
            }
            try:
                with redirect_stdout(io.StringIO()):
                    result = ss._generate_single(
                        "SYS", case["prompt"], case.get("is_premium", False),
                        "free", case["target_words"], None, "ja",
                    )
                record["ok"] = True
                record["result"] = result
            except RuntimeError as exc:
                record["ok"] = False
                record["error"] = str(exc)
            record["calls"] = calls
            flows.append(record)
    finally:
        ss._llm_generate_sync = real_llm
        ss._enrich_with_nlp = real_enrich
        ss._prewarm_nlp_async = real_prewarm
    out["generate_single"] = flows

    path = os.path.join(os.path.dirname(__file__), "generate_golden.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print("wrote", path)
    for k, v in out.items():
        print(f"  {k}: {len(v)}")


def sent(thai, words, notes=None, context=None):
    d = {
        "thai_text": thai,
        "japanese_translation": "訳",
        "word_breakdown": [
            {"word": w, "meaning": f"{w}の意味"} for w in words
        ],
    }
    if notes is not None:
        d["target_notes"] = notes
    if context is not None:
        d["context"] = context
    return d


def flow_cases() -> list[dict]:
    """制御フローの分岐を一通り踏む手作りケース。"""
    ok = sent("ฉันกินข้าว", ["ฉัน", "กิน", "ข้าว"])
    # ターゲット語が欠けている
    missing = sent("ฉันไปตลาด", ["ฉัน", "ไป", "ตลาด"])
    # word_breakdown に thai_text へ無い語（綴り不一致）
    mismatch = sent("ฉันกินข้าว", ["ฉัน", "กิน", "แมว"])
    # thai_text に word_breakdown で埋まらない部分がある（欠落）
    gap = sent("ฉันกินข้าวสวย", ["ฉัน", "กิน", "ข้าว"])
    # 分かち書きが漏れた文（4トークン以上・連結一致）
    collapsed = sent("ฉัน กิน ข้าว สวย", ["ฉัน", "กิน", "ข้าว", "สวย"])
    # 正しい2節の文（触ってはいけない）
    two_clause = sent("ฉันกินข้าว สวยมาก", ["ฉันกินข้าว", "สวยมาก"])

    return [
        {"name": "1回で成功", "prompt": "P", "target_words": ["กิน"],
         "responses": [ok]},
        {"name": "ターゲット語なし（検証しない）", "prompt": "P",
         "target_words": None, "responses": [ok]},
        {"name": "空のターゲット語", "prompt": "P", "target_words": [],
         "responses": [ok]},
        {"name": "欠落→再生成で成功", "prompt": "P", "target_words": ["แมว"],
         "responses": [missing, sent("ฉันเห็นแมว", ["ฉัน", "เห็น", "แมว"])]},
        {"name": "欠落→再生成でも欠落", "prompt": "P", "target_words": ["แมว"],
         "responses": [missing, missing]},
        {"name": "欠落が複数", "prompt": "P", "target_words": ["แมว", "สวย"],
         "responses": [missing, missing]},
        {"name": "綴り不一致→作り直しで成功", "prompt": "P",
         "target_words": ["กิน"], "responses": [mismatch, ok]},
        {"name": "綴り不一致→2回目も不一致（そのまま返す）", "prompt": "P",
         "target_words": ["กิน"], "responses": [mismatch, mismatch]},
        {"name": "欠落補完が走る", "prompt": "P", "target_words": ["กิน"],
         "responses": [gap, {"words": [{"word": "สวย", "meaning": "きれい"}]}]},
        {"name": "欠落補完しても既存の notes は残る", "prompt": "P",
         "target_words": ["กิน"],
         "responses": [sent("\u0e09\u0e31\u0e19\u0e01\u0e34\u0e19\u0e02\u0e49\u0e32\u0e27\u0e2a\u0e27\u0e22",
                            ["\u0e09\u0e31\u0e19", "\u0e01\u0e34\u0e19", "\u0e02\u0e49\u0e32\u0e27"],
                            notes=[{"word": "\u0e01\u0e34\u0e19", "note": "食べる"},
                                   {"word": "\u0e02\u0e49\u0e32\u0e27", "note": "ごはん"}]),
                       {"words": [{"word": "\u0e2a\u0e27\u0e22", "meaning": "きれい"}]}]},
        {"name": "欠落補完が的外れ", "prompt": "P", "target_words": ["กิน"],
         "responses": [gap, {"words": [{"word": "แมว", "meaning": "猫"}]}]},
        {"name": "欠落補完が失敗（例外）", "prompt": "P", "target_words": ["กิน"],
         "responses": [gap, "LLM_API_ERROR: boom"]},
        {"name": "分かち書きの漏れを詰める", "prompt": "P",
         "target_words": ["กิน"], "responses": [collapsed]},
        {"name": "正しい2節は触らない", "prompt": "P", "target_words": [],
         "responses": [two_clause]},
        {"name": "target_notes を展開して返す", "prompt": "P",
         "target_words": ["กิน"],
         "responses": [sent("ฉันกินข้าว", ["ฉัน", "กิน", "ข้าว"],
                            notes=[{"word": "กิน", "note": "食べる"}])]},
        {"name": "1回目でLLMが落ちる", "prompt": "P", "target_words": ["กิน"],
         "responses": ["LLM_API_ERROR: OpenAI API error status=500: boom"]},
        {"name": "premium", "prompt": "P", "target_words": ["กิน"],
         "is_premium": True, "responses": [ok]},
    ]


if __name__ == "__main__":
    main()
