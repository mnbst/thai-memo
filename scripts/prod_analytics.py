"""prod Firestore 全ユーザー集計スクリプト

usage:
  cd functions/python
  uv run python ../../scripts/prod_analytics.py
"""

import os
import sys
import json
from datetime import datetime, timezone, timedelta
from collections import Counter

os.environ['GOOGLE_CLOUD_PROJECT'] = 'thai-memo-prod'

import firebase_admin
from firebase_admin import firestore
from google.cloud import storage

JST = timezone(timedelta(hours=9))
NOW = datetime.now(JST)

app = firebase_admin.initialize_app(options={'projectId': 'thai-memo-prod'})
db = firestore.client()

# freq_rank ロード
print("Loading freq_rank...", flush=True)
gcs = storage.Client(project='thai-memo-prod')
blob = gcs.bucket('thai-memo-prod-uvm-data').blob('freq_rank_top10000.json')
freq_rank: dict[str, int] = json.loads(blob.download_as_text())

# -------------------------
# 全ユーザー取得
# -------------------------
print("Fetching all users...", flush=True)
user_docs = list(db.collection('users').stream())
print(f"Total users: {len(user_docs)}\n")

tiers = Counter()
estimated_vocabs = []
vocab_counts = []
uvm_word_counts = []
sentence_counts = []

# サインアップ日の分布
signup_days_ago = []

# 課金ユーザー vs フリーユーザーの vocab 比較
premium_vocabs = []
free_vocabs = []

for user_doc in user_docs:
    d = user_doc.to_dict() or {}
    uid = user_doc.id
    tier = d.get('tier', 'free')
    tiers[tier] += 1

    ev = d.get('estimated_vocab', 0) or 0
    estimated_vocabs.append(ev)

    if tier == 'premium':
        premium_vocabs.append(ev)
    else:
        free_vocabs.append(ev)

print("=== Tier Distribution ===")
total = len(user_docs)
for tier, count in sorted(tiers.items()):
    pct = count / total * 100 if total else 0
    print(f"  {tier:10s}: {count:4d} ({pct:.1f}%)")

# -------------------------
# estimated_vocab 分布
# -------------------------
print("\n=== estimated_vocab Distribution (all users) ===")
buckets = [(0, 0), (1, 100), (101, 300), (301, 500), (501, 1000), (1001, 2000), (2001, 9999)]
for lo, hi in buckets:
    count = sum(1 for v in estimated_vocabs if lo <= v <= hi)
    pct = count / total * 100 if total else 0
    print(f"  {lo:5d}–{hi:5d}: {count:4d} ({pct:.1f}%)")

if estimated_vocabs:
    avg = sum(estimated_vocabs) / len(estimated_vocabs)
    med = sorted(estimated_vocabs)[len(estimated_vocabs) // 2]
    print(f"  avg={avg:.0f}, median={med}")

print("\n=== estimated_vocab by tier ===")
if premium_vocabs:
    avg_p = sum(premium_vocabs) / len(premium_vocabs)
    med_p = sorted(premium_vocabs)[len(premium_vocabs) // 2]
    print(f"  premium: avg={avg_p:.0f}, median={med_p}, n={len(premium_vocabs)}")
if free_vocabs:
    avg_f = sum(free_vocabs) / len(free_vocabs)
    med_f = sorted(free_vocabs)[len(free_vocabs) // 2]
    print(f"  free:    avg={avg_f:.0f}, median={med_f}, n={len(free_vocabs)}")

# -------------------------
# アクティブユーザー（例文数で判断）
# -------------------------
print("\n=== Activity (sampling up to 200 users) ===")
sample = user_docs[:200]
active_7d = 0
active_30d = 0
never_generated = 0
sentence_count_list = []

for user_doc in sample:
    uid = user_doc.id
    sentences = list(db.collection('users').document(uid).collection('sentences')
                     .order_by('created_at', direction=firestore.Query.DESCENDING)
                     .limit(1).stream())
    if not sentences:
        never_generated += 1
        sentence_count_list.append(0)
        continue

    last = sentences[0].to_dict()
    created = last.get('created_at')
    if created:
        created_dt = created.replace(tzinfo=timezone.utc).astimezone(JST)
        diff = (NOW - created_dt).days
        if diff <= 7:
            active_7d += 1
        if diff <= 30:
            active_30d += 1

    # 例文総数
    total_s = len(list(db.collection('users').document(uid).collection('sentences').stream()))
    sentence_count_list.append(total_s)

n = len(sample)
print(f"  Sample size: {n}")
print(f"  Never generated: {never_generated} ({never_generated/n*100:.1f}%)")
print(f"  Active 7d:  {active_7d} ({active_7d/n*100:.1f}%)")
print(f"  Active 30d: {active_30d} ({active_30d/n*100:.1f}%)")
if sentence_count_list:
    avg_s = sum(sentence_count_list) / len(sentence_count_list)
    med_s = sorted(sentence_count_list)[len(sentence_count_list) // 2]
    print(f"  Sentences per user: avg={avg_s:.1f}, median={med_s}")

# -------------------------
# UVM サンプリング（最初の50ユーザー）
# -------------------------
print("\n=== UVM Stats (sampling up to 50 active users) ===")
active_users = [u for u in user_docs if (u.to_dict() or {}).get('estimated_vocab', 0) > 0][:50]
uvm_totals = []
p_above_05_counts = []
p_in_mid_counts = []

for user_doc in active_users:
    uid = user_doc.id
    uvm_docs = list(db.collection('users').document(uid).collection('uvm').stream())
    if not uvm_docs:
        continue
    uvm_totals.append(len(uvm_docs))
    above_05 = sum(1 for d in uvm_docs if (d.to_dict() or {}).get('p', 0) > 0.5)
    mid = sum(1 for d in uvm_docs if 0.3 < (d.to_dict() or {}).get('p', 0) <= 0.5)
    p_above_05_counts.append(above_05)
    p_in_mid_counts.append(mid)

if uvm_totals:
    print(f"  UVM words per user: avg={sum(uvm_totals)/len(uvm_totals):.1f}, median={sorted(uvm_totals)[len(uvm_totals)//2]}")
    print(f"  P>0.5 words per user: avg={sum(p_above_05_counts)/len(p_above_05_counts):.1f}")
    print(f"  0.3<P≤0.5 words per user: avg={sum(p_in_mid_counts)/len(p_in_mid_counts):.1f}")

# -------------------------
# リテンション分析（users ドキュメントの timestamp フィールドで集計）
# -------------------------
print("\n=== Retention Analysis ===")

from collections import defaultdict

cohorts = defaultdict(lambda: {'total': 0, 'd1': 0, 'd7': 0, 'd30': 0})
dau = 0
wau = 0
mau = 0

for user_doc in user_docs:
    d = user_doc.to_dict() or {}
    first = d.get('first_generated_at')
    last = d.get('last_active_at')
    if not first:
        continue

    first_dt = first.replace(tzinfo=timezone.utc).astimezone(JST)
    age_days = (NOW - first_dt).days

    # WAU / MAU
    if last:
        last_dt = last.replace(tzinfo=timezone.utc).astimezone(JST)
        inactive_days = (NOW - last_dt).days
        if inactive_days <= 0:
            dau += 1
        if inactive_days <= 7:
            wau += 1
        if inactive_days <= 30:
            mau += 1

        # コホート（登録週）ごとのリテンション
        cohort_key = first_dt.strftime('%Y-W%W')
        cohorts[cohort_key]['total'] += 1
        active_span = (last_dt - first_dt).days
        if active_span >= 1:
            cohorts[cohort_key]['d1'] += 1
        if active_span >= 7:
            cohorts[cohort_key]['d7'] += 1
        if active_span >= 30:
            cohorts[cohort_key]['d30'] += 1

users_with_activity = sum(1 for u in user_docs if (u.to_dict() or {}).get('first_generated_at'))
print(f"  Users with activity: {users_with_activity}")
print(f"  DAU (today): {dau}")
print(f"  WAU (7d):  {wau}")
print(f"  MAU (30d): {mau}")

print("\n=== Cohort Retention (by signup week) ===")
print(f"  {'Cohort':>10s}  {'N':>4s}  {'D1':>6s}  {'D7':>6s}  {'D30':>6s}")
for cohort_key in sorted(cohorts.keys()):
    c = cohorts[cohort_key]
    n = c['total']
    if n < 2:
        continue
    d1 = f"{c['d1']/n*100:.0f}%" if (NOW - datetime.strptime(cohort_key + '-1', '%Y-W%W-%w').replace(tzinfo=JST)).days >= 1 else '-'
    d7 = f"{c['d7']/n*100:.0f}%" if (NOW - datetime.strptime(cohort_key + '-1', '%Y-W%W-%w').replace(tzinfo=JST)).days >= 7 else '-'
    d30 = f"{c['d30']/n*100:.0f}%" if (NOW - datetime.strptime(cohort_key + '-1', '%Y-W%W-%w').replace(tzinfo=JST)).days >= 30 else '-'
    print(f"  {cohort_key:>10s}  {n:4d}  {d1:>6s}  {d7:>6s}  {d30:>6s}")

firebase_admin.delete_app(app)
print("\nDone.")
