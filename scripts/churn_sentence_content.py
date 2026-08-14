"""離脱ユーザーが露出した例文の「内容」を定着ユーザーと比べる。

例文docは2026-07以降しか無いため、初回例文docが7月以降のユーザーだけに絞る。
質は「初回3件」（結果が出る前の露出）で測る。

usage:
  cd functions/python
  uv run python ../../scripts/churn_sentence_content.py 2>/dev/null
"""

import os
import json
from collections import Counter
from datetime import datetime, timezone, timedelta

os.environ['GOOGLE_CLOUD_PROJECT'] = 'thai-memo-prod'

import firebase_admin
from firebase_admin import firestore

JST = timezone(timedelta(hours=9))
NOW = datetime.now(timezone.utc)
WINDOW_START = datetime(2026, 7, 1, tzinfo=timezone.utc)
CHURN_DAYS = 10

firebase_admin.initialize_app(options={'projectId': 'thai-memo-prod'})
db = firestore.client()

rows = []
for u in db.collection('users').stream():
    sents = [s.to_dict() or {} for s in
             db.collection('users').document(u.id).collection('sentences').stream()]
    sents = [s for s in sents if s.get('created_at')]
    if not sents:
        continue
    sents.sort(key=lambda s: s['created_at'])
    first, last = sents[0]['created_at'], sents[-1]['created_at']
    if first < WINDOW_START:
        continue
    rows.append({
        'uid': u.id,
        'tier': (u.to_dict() or {}).get('tier', 'free'),
        'ev': (u.to_dict() or {}).get('estimated_vocab', 0) or 0,
        'n': len(sents),
        'span_days': (last - first).days,
        'idle_days': (NOW - last).days,
        'first3': sents[:3],
    })

left = [r for r in rows if r['idle_days'] >= CHURN_DAYS]
stayed = [r for r in rows if r['idle_days'] < CHURN_DAYS]
print(f"母集団: {len(rows)}人 (left={len(left)} / stayed={len(stayed)})\n")


def agg(group, label):
    print(f"===== {label} (n={len(group)}人) =====")
    topics, styles, kws, emos = Counter(), Counter(), Counter(), Counter()
    tiers = Counter()
    lens, wlens, tlens = [], [], []
    for r in group:
        tiers[r['tier']] += 1
        for s in r['first3']:
            c = s.get('context') or {}
            topics[c.get('topic', '?')] += 1
            styles[c.get('style', '?')] += 1
            emos[c.get('emotion', '?')] += 1
            kws[s.get('key_word', '?')] += 1
            wb = s.get('word_breakdown') or []
            wlens.append(len(wb))
            lens.append(len(s.get('thai_text', '')))
            tlens.append(len(s.get('japanese_translation', '')))
    n = max(1, len(lens))
    print(f"  tier: {dict(tiers)}  例文数中央値: {sorted(r['n'] for r in group)[len(group)//2]}")
    print(f"  語数 {sum(wlens)/n:.2f} / タイ語文字数 {sum(lens)/n:.1f} / 訳文字数 {sum(tlens)/n:.1f}")
    print(f"  ユニーク率: topic {len(topics)}/{n}  key_word {len(kws)}/{n}")
    for name, c in (('topic', topics), ('style', styles), ('emotion', emos), ('key_word', kws)):
        top = ', '.join(f'{k} {v}' for k, v in c.most_common(6))
        print(f"  {name} top: {top}")
    print()
    return {'topics': topics, 'styles': styles, 'kws': kws}


a_left = agg(left, 'LEFT (最終例文が10日以上前)')
a_stay = agg(stayed, 'STAYED')

print("===== LEFT 全員の初回3件（本文） =====")
for r in sorted(left, key=lambda r: r['ev']):
    print(f"\n-- {r['uid'][:8]} tier={r['tier']} ev={r['ev']} 生成{r['n']}件 "
          f"span{r['span_days']}d idle{r['idle_days']}d")
    for s in r['first3']:
        c = s.get('context') or {}
        print(f"   [{c.get('topic')}/{c.get('style')}] kw={s.get('key_word')}")
        print(f"   {s.get('thai_text')}  →  {s.get('japanese_translation')}")

with open('/tmp/churn_sentences.json', 'w') as f:
    json.dump(rows, f, ensure_ascii=False, default=str, indent=1)
print("\nraw: /tmp/churn_sentences.json")
