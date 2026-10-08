"""例文の訳で、タイ語の機能語の意味が落ちた・ずれた文の候補を拾い、修正を当てる。

手順は .claude/skills/fw-trans-audit/SKILL.md。候補の正誤は人か別モデルが判定する
（ルールだけの精度は 3〜5 割。正しい言い換えも拾う）。

usage:
  python3 scripts/fw_trans_audit.py scan --lang ja|en OUT.md FILE.json [FILE.json ...]
  python3 scripts/fw_trans_audit.py apply FIXES.tsv IN.json OUT.json

FILE.json は thai_text / japanese_translation を持つ文の配列（コーパス・プール。
英訳ファイルも訳は japanese_translation に入っている）。
FIXES.tsv は「タイ語<TAB>新しい訳」。apply は訳の項目だけを書き換え、
元ファイルの区切り（コンパクト／空白あり）を保つ。
"""

import json
import re
import sys
from pathlib import Path

# 語クラスごとの (名前, タイ語の正規表現, 除外する綴り, 訳を見て真なら候補)。
# 「期待する表現が無い」か「強すぎる・ずれた表現がある」を拾う。

KEEP_JA = {
    "ทัน": r"間に合|追いつ|期限|内に|うちに|までに|聞き取|よけ|避け|しきれ|ついていけ|ギリギリ|ぎりぎり|時間通り|遅れ|やっと",
    "ไม่ค่อย": r"あまり|あんまり|そんなに|それほど|なかなか|めったに|少し|ちょっと|よく|ほとんど|いまいち|イマイチ|すぐれ|優れ",
    "เพิ่ง": r"ところ|ばかり|さっき|先ほど|今|初めて|やっと|ようやく|最近|先日|この前|新し|新た|直前|直後|たて|立て|ついに|瞬間|つい",
}
STRONG_JA = r"全然|全く|まったく|ちっとも"
PERHAPS_JA = r"はず|だろ|でしょ|かも|と思|みたい|らしい|そう|たぶん|多分|おそらく|きっと|かな|ようだ|違いない|しかない|ほかない|ようです|ないと|なきゃ|かね|ほうがいい|方がいい|べき|気がする|んじゃない|のでは"
PERHAPS_EN = r"probably|should|might|may\b|must|likely|could|guess|think|seem|suppose|bet\b|would|'d\b|maybe|perhaps|ought|better|i'm sure|surely|bound to|have to|has to|got to|gotta|gonna|will|'ll|no choice|expect"
REFL_EN = r"myself|yourself|himself|herself|themselves|ourselves|itself|own\b|by (my|your|him|her|them|our)"


def no(pat):
    return lambda t, j: not re.search(pat, j, re.I)


def has(pat):
    return lambda t, j: bool(re.search(pat, j, re.I))


THAN = r"(ให้|ไม่|ได้)ทัน(?!ที|ใด|สมัย|ตกรรม)"
KWAJA = r"(?<!เกิน)(?<!จน)(?<!นึ)(?<!บอ)(?<!เลือ)กว่าจะ"
PHUENG = r"เพิ่ง(?!จะ)"
ONLY = r"แค่|เท่านั้น|(?<!ตัว)(?<!กัน)เอง"
TANG = r"ตั้ง\s?(\d|หนึ่ง|สอง|สาม|สี่|ห้า|หก|เจ็ด|แปด|เก้า|สิบ|ร้อย|พัน|หมื่น|แสน|ล้าน|หลาย|นาน|ครึ่ง)"
KHONG = r"(?<!มั่น)(?<!ทน)คง(?!ที่|ทน|อยู่|เดิม|ไว้|สภาพ|ความ)"
KHOEI = r"(?<!ไม่)เคย(?!ชิน|ตัว)"
KOEN = r"เกิน(ไป)?(?!กว่า|เวลา|ราคา)"
KHOI = r"(เดี๋ยว|แล้ว|ก่อน|ค่อย)ค่อย(?!ๆ)|ค่อยว่า|ค่อยไป|ค่อยมา|ค่อยทำ|ค่อยกิน|ค่อยคุย"

RULES = {
    "ja": [
        ("ทัน（間に合う）", THAN, None, no(KEEP_JA["ทัน"])),
        ("ไม่ค่อย（あまり〜ない）", r"ไม่ค่อย", None,
         lambda t, j: has(STRONG_JA)(t, j) or no(KEEP_JA["ไม่ค่อย"])(t, j)),
        ("ยังไม่（まだ）", r"ยังไม่", r"แม้แต่|ยังไม่ถึง", no(r"まだ")),
        ("กว่าจะ（〜する頃には）", KWAJA, None,
         lambda t, j: has(r"までに")(t, j) and no(r"かか|時間|頃|ころ")(t, j)),
        ("เพิ่ง（〜したばかり）", PHUENG, r"อย่าเพิ่ง",
         lambda t, j: no(KEEP_JA["เพิ่ง"])(t, j)
         or ("ちょうど" in j and "พอดี" not in t and no(r"ところ|ばかり|時に|ときに")(t, j))),
        ("แค่/เท่านั้น/เอง（だけ・自分で）", ONLY, r"ตัวเอง|กันเอง|ด้วยตัว",
         no(r"だけ|しか|ほんの|たった|ばかり|のみ|程度|くらい|ぐらい|わずか|ちょっと|少し|単に|ただ|自分|自ら|自身|ひとり|一人|自力")),
        ("ตั้ง+数量（〜も）", TANG, None, no(r"も|なんと|もの|ほど")),
        ("หรือยัง（もう〜した？）", r"หรือยัง", None,
         no(r"もう|まだ|済|終わ|た？|た\?|ました？|ました\?|たか|てる？|ている？|できた|てある|った？|んだ？")),
        ("ยัง..อยู่（まだ）", r"ยัง(?!ไม่|ไง|งั้น|คง).*อยู่", None, no(r"まだ|今も|今でも|相変わらず|依然|いまだ|ずっと|続")),
        ("น่าจะ（推量）", r"น่าจะ", None, no(PERHAPS_JA)),
        ("คง（推量）", KHONG, r"คงที่|คงทน|คงอยู่|คงเดิม|คงไว้|ยังคง|มั่นคง|คงคลัง|คงความ", no(PERHAPS_JA)),
        ("เคย（経験・以前）", KHOEI, r"ไม่เคย|คุ้นเคย|เคยชิน",
         no(r"ことがあ|ことはあ|ことある|以前|昔|前に|前は|かつて|よく|経験|これまで|今まで|たことが|一度|頃|時代|当時|いつも|もと|元")),
        ("เกิน（すぎる）", KOEN, r"เกินกว่า|เกินเวลา",
         no(r"すぎ|過ぎ|過度|あまりに|超え|以上|オーバー|余計|余分|過剰|行き過")),
        ("ถึงได้（だから）", r"ถึงได้", None, no(r"だから|それで|ので|から|わけ|道理|ため|せいで|こそ|おかげ")),
        ("ไม่ไหว（無理）", r"ไม่ไหว", None,
         no(r"無理|できな|もたな|限界|きつ|耐え|やっと|られな|ず|ダメ|だめ|参|しんど|厳し|きれな|けな|めな|べな")),
        ("เดี๋ยวค่อย（あとで）", KHOI, r"ไม่ค่อย",
         no(r"あとで|後で|それから|てから|そのあと|その後|改めて|次|今度|後から|あと|してから|でから|たら|それで|うちに|まず")),
    ],
    "en": [
        ("ทัน（in time）", THAN, None,
         no(r"in time|on time|make it|catch|keep up|deadline|before|by |miss|late|finish|fast enough|quick enough|enough time|follow|dodge")),
        ("ไม่ค่อย（not very）", r"ไม่ค่อย", None,
         has(r"\bat all\b|really (don't|can't|do not|cannot|isn't|is not)|completely|totally|never")),
        ("ยังไม่（yet）", r"ยังไม่", r"แม้แต่|ยังไม่ถึง", no(r"\byet\b|\bstill\b|not even|even|enough")),
        ("กว่าจะ（by the time）", KWAJA, None, no(r"by the time|took|long|until|before|finally|by then")),
        ("เพิ่ง（just）", PHUENG, r"อย่าเพิ่ง",
         no(r"\bjust\b|recent|\bnew|only|first|finally|a moment ago|earlier|fresh|right after")),
        ("แค่/เท่านั้น/เอง（only・oneself）", ONLY, r"ตัวเอง|กันเอง|ด้วยตัว",
         no(r"\bonly\b|\bjust\b|merely|simply|alone|a little|a bit|\bfew\b|barely|nothing but|all it|that.s all|" + REFL_EN)),
        ("ตั้ง+数量（as many as）", TANG, None,
         no(r"as (many|much|long)|whole|full|entire|no less|whopping|over|more than|a good|even|all|such a long|so long|ages|forever")),
        ("หรือยัง（yet）", r"หรือยัง", None,
         no(r"\byet\b|already|\bdone\b|finished|have you|has (it|he|she|the)|did you|ready")),
        ("ยัง..อยู่（still）", r"ยัง(?!ไม่|ไง|งั้น|คง).*อยู่", None,
         no(r"still|\byet\b|keep|continu|remain|ongoing|even now|to this day|always")),
        ("น่าจะ（probably）", r"น่าจะ", None, no(PERHAPS_EN)),
        ("คง（probably）", KHONG, r"คงที่|คงทน|คงอยู่|คงเดิม|คงไว้|ยังคง|มั่นคง|คงคลัง|คงความ", no(PERHAPS_EN)),
        ("เคย（ever・used to）", KHOEI, r"ไม่เคย|คุ้นเคย|เคยชิน",
         no(r"used to|\bever\b|before|once|previously|experience|in the past|back (when|then|in)|when i was|have been|'ve \w+|have \w+(ed|en)\b|had \w+ed|ago|earlier|formerly|at one point|one time")),
        ("เกิน（too）", KOEN, r"เกินกว่า|เกินเวลา",
         no(r"\btoo\b|\bover|exceed|beyond|more than|excess|so much|overly|way more|extra|out of|past\b|outweigh")),
        ("ถึงได้（that's why）", r"ถึงได้", None,
         no(r"that.s why|which is why|that is why|\bso\b|no wonder|explains|because|reason|that.s how|hence|therefore")),
        ("ไม่ไหว（can't take）", r"ไม่ไหว", None,
         no(r"can.t|cannot|can not|unable|too |exhausted|anymore|any more|no longer|not up to|bear|stand|handle|enough|limit|give up|worn out|hardly|barely|couldn.t")),
        ("เดี๋ยวค่อย（later）", KHOI, r"ไม่ค่อย",
         no(r"later|then|after|first|afterwards|next|once|until|before|when|wait|in a (bit|while|moment)|another time|for now|eventually|tomorrow|tonight")),
    ],
}


def scan(lang, out, files):
    rows = []
    for f in files:
        for s in json.loads(Path(f).read_text()):
            rows.append((Path(f).stem, s["thai_text"], s["japanese_translation"]))
    lines, seen, n = [], set(), 0
    for name, thai, skip, bad in RULES[lang]:
        hits = [r for r in rows if re.search(thai, r[1]) and not (skip and re.search(skip, r[1]))]
        cand = [r for r in hits if bad(r[1], r[2])]
        print(f"{name}\t語を含む {len(hits)}\t候補 {len(cand)}", file=sys.stderr)
        cand = [r for r in cand if r[1] not in seen]
        if not cand:
            continue
        lines.append(f"\n## {name}\n\n| id | 出典 | タイ語 | 訳 |\n|---|---|---|---|")
        for src, t, j in cand:
            seen.add(t)
            n += 1
            lines.append(f"| {n} | {src} | {t} | {j} |")
    Path(out).write_text("\n".join(lines) + "\n")
    print(f"候補 計 {n} 件 → {out}", file=sys.stderr)


def apply(fixes, src, dst):
    fix = dict(l.rstrip("\n").split("\t") for l in Path(fixes).read_text().splitlines(True) if l.strip())
    raw = Path(src).read_text()
    data = json.loads(raw)
    n, hit = 0, set()
    for s in data:
        if s["thai_text"] in fix:
            s["japanese_translation"] = fix[s["thai_text"]]
            n += 1
            hit.add(s["thai_text"])
    compact = '","' in raw[:2000] or '":"' in raw[:2000]
    sep = (",", ":") if compact else (", ", ": ")
    Path(dst).write_text(json.dumps(data, ensure_ascii=False, separators=sep))
    before = json.loads(raw)
    changed = {k for a, b in zip(before, data) for k in a if a[k] != b[k]}
    assert len(before) == len(data) and changed <= {"japanese_translation"}, changed
    print(f"{Path(src).name}: {n} 行を更新・該当なし {len(set(fix) - hit)} 件", file=sys.stderr)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "scan" and len(sys.argv) >= 6 and sys.argv[2] == "--lang":
        scan(sys.argv[3], sys.argv[4], sys.argv[5:])
    elif cmd == "apply" and len(sys.argv) == 5:
        apply(*sys.argv[2:])
    else:
        sys.exit(__doc__)
