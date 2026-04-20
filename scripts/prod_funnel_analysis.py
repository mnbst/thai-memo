"""prod ユーザーの「詰まりポイント」深掘り分析

調査軸:
  1. 例文 → クイズ到達率 (quiz_attempts > 0 の語の割合)
  2. SRS消化率 (key_word のうちクイズ済みの割合)
  3. 1日あたり新語/露出/正解語数の分布
  4. 例文生成頻度 vs estimated_vocab 進捗

usage:
  cd functions/python
  uv run python ../../scripts/prod_funnel_analysis.py 2>/dev/null
"""

import os
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

print("Loading freq_rank...", flush=True)
gcs = storage.Client(project='thai-memo-prod')
blob = gcs.bucket('thai-memo-prod-uvm-data').blob('freq_rank_top10000.json')
freq_rank: dict[str, int] = json.loads(blob.download_as_text())

print("Fetching all users...", flush=True)
user_docs = list(db.collection('users').stream())
print(f"Total users: {len(user_docs)}\n")

# 全ユーザーから sentences と uvm を集計
per_user = []
for u in user_docs:
    uid = u.id
    d = u.to_dict() or {}
    tier = d.get('tier', 'free')
    ev = d.get('estimated_vocab', 0) or 0

    sentences = list(db.collection('users').document(uid).collection('sentences').stream())
    uvms = list(db.collection('users').document(uid).collection('uvm').stream())

    if not sentences and not uvms:
        per_user.append({
            'uid': uid, 'tier': tier, 'ev': ev,
            'sentences': 0, 'uvm_total': 0,
            'quiz_done': 0, 'quiz_done_kw': 0,
            'kw_total': 0, 'p_above_05': 0, 'p_mid': 0,
            'days_since_first': 0, 'days_since_last': 0,
            'sentences_per_day': 0,
        })
        continue

    # 例文の最初・最終日
    s_dates = []
    key_words = []
    for s in sentences:
        sd = s.to_dict()
        c = sd.get('created_at')
        if c:
            s_dates.append(c.replace(tzinfo=timezone.utc).astimezone(JST))
        kw = sd.get('key_word', '')
        if kw:
            key_words.append(kw)

    days_since_first = (NOW - min(s_dates)).days if s_dates else 0
    days_since_last = (NOW - max(s_dates)).days if s_dates else 999
    spd = len(sentences) / max(days_since_first + 1, 1)

    # UVM 集計
    uvm_dict = {}
    quiz_done = 0
    p_above_05 = 0
    p_mid = 0
    for udoc in uvms:
        ud = udoc.to_dict() or {}
        uvm_dict[udoc.id] = ud
        if ud.get('quiz_attempts', 0) > 0:
            quiz_done += 1
        p = ud.get('p', 0)
        if p > 0.5:
            p_above_05 += 1
        elif 0.3 < p <= 0.5:
            p_mid += 1

    # key_word のうちクイズ到達済み数
    kw_unique = set(key_words)
    quiz_done_kw = sum(1 for kw in kw_unique
                       if uvm_dict.get(kw, {}).get('quiz_attempts', 0) > 0)

    per_user.append({
        'uid': uid, 'tier': tier, 'ev': ev,
        'sentences': len(sentences), 'uvm_total': len(uvms),
        'quiz_done': quiz_done, 'quiz_done_kw': quiz_done_kw,
        'kw_total': len(kw_unique), 'p_above_05': p_above_05, 'p_mid': p_mid,
        'days_since_first': days_since_first, 'days_since_last': days_since_last,
        'sentences_per_day': spd,
    })

# -------- ファネル分析 --------
print("=== ファネル: 例文 → クイズ到達 → 習得 (free ユーザーのみ) ===")
free_users = [u for u in per_user if u['tier'] == 'free' and u['sentences'] > 0]
print(f"free アクティブユーザー: {len(free_users)}人\n")

# 各指標の平均
def avg(key):
    vals = [u[key] for u in free_users]
    return sum(vals) / len(vals) if vals else 0

def med(key):
    vals = sorted(u[key] for u in free_users)
    return vals[len(vals)//2] if vals else 0

print(f"  例文数               : avg={avg('sentences'):.1f}  median={med('sentences')}")
print(f"  UVM登録語数          : avg={avg('uvm_total'):.1f}  median={med('uvm_total')}")
print(f"  key_word ユニーク数  : avg={avg('kw_total'):.1f}  median={med('kw_total')}")
print(f"  クイズ到達 key_word  : avg={avg('quiz_done_kw'):.1f}  median={med('quiz_done_kw')}")
print(f"  全クイズ到達語数     : avg={avg('quiz_done'):.1f}  median={med('quiz_done')}")
print(f"  P>0.5 (習得済み)     : avg={avg('p_above_05'):.1f}  median={med('p_above_05')}")
print(f"  0.3<P≤0.5 (中間)     : avg={avg('p_mid'):.1f}  median={med('p_mid')}")

# 比率
total_sent = sum(u['sentences'] for u in free_users)
total_kw = sum(u['kw_total'] for u in free_users)
total_quiz_kw = sum(u['quiz_done_kw'] for u in free_users)
total_uvm = sum(u['uvm_total'] for u in free_users)
total_quiz = sum(u['quiz_done'] for u in free_users)
total_p05 = sum(u['p_above_05'] for u in free_users)

print("\n--- ファネル通過率 ---")
if total_kw:
    print(f"  key_word のクイズ到達率: {total_quiz_kw}/{total_kw} = {total_quiz_kw/total_kw*100:.1f}%")
if total_uvm:
    print(f"  全UVM語のクイズ到達率   : {total_quiz}/{total_uvm} = {total_quiz/total_uvm*100:.1f}%")
if total_quiz:
    print(f"  クイズ到達語の習得率    : {total_p05}/{total_quiz} = {total_p05/total_quiz*100:.1f}%")

# -------- 利用継続日数の分布 --------
print("\n=== 利用継続 (free) ===")
days_buckets = [(0, 0), (1, 3), (4, 7), (8, 14), (15, 30), (31, 90), (91, 999)]
print("  初回例文からの経過日数:")
for lo, hi in days_buckets:
    c = sum(1 for u in free_users if lo <= u['days_since_first'] <= hi)
    print(f"    {lo:3d}-{hi:3d}日: {c}人")

print("  最終例文からの経過日数:")
for lo, hi in [(0, 0), (1, 1), (2, 3), (4, 7), (8, 30), (31, 999)]:
    c = sum(1 for u in free_users if lo <= u['days_since_last'] <= hi)
    print(f"    {lo:3d}-{hi:3d}日: {c}人")

# -------- estimated_vocab とクイズ到達率の関係 --------
print("\n=== estimated_vocab=0 ユーザーの内訳 (free) ===")
ev0 = [u for u in free_users if u['ev'] == 0]
print(f"  該当: {len(ev0)}人")
if ev0:
    print(f"    平均 例文数         : {sum(u['sentences'] for u in ev0)/len(ev0):.1f}")
    print(f"    平均 key_word 数    : {sum(u['kw_total'] for u in ev0)/len(ev0):.1f}")
    print(f"    平均 quiz到達 key_word: {sum(u['quiz_done_kw'] for u in ev0)/len(ev0):.1f}")
    print(f"    平均 P>0.5 語数     : {sum(u['p_above_05'] for u in ev0)/len(ev0):.1f}")
    print(f"    平均 中間層P語数    : {sum(u['p_mid'] for u in ev0)/len(ev0):.1f}")
    # クイズに1回でも到達した人の数
    has_quiz = sum(1 for u in ev0 if u['quiz_done'] > 0)
    print(f"    クイズ到達経験あり  : {has_quiz}/{len(ev0)}人 ({has_quiz/len(ev0)*100:.1f}%)")

# -------- ev > 0 ユーザーとの差 --------
print("\n=== estimated_vocab>0 ユーザーの内訳 (free) ===")
ev_pos = [u for u in free_users if u['ev'] > 0]
print(f"  該当: {len(ev_pos)}人")
if ev_pos:
    print(f"    平均 estimated_vocab: {sum(u['ev'] for u in ev_pos)/len(ev_pos):.1f}")
    print(f"    平均 例文数         : {sum(u['sentences'] for u in ev_pos)/len(ev_pos):.1f}")
    print(f"    平均 quiz到達 key_word: {sum(u['quiz_done_kw'] for u in ev_pos)/len(ev_pos):.1f}")
    print(f"    平均 P>0.5 語数     : {sum(u['p_above_05'] for u in ev_pos)/len(ev_pos):.1f}")
    print(f"    平均 中間層P語数    : {sum(u['p_mid'] for u in ev_pos)/len(ev_pos):.1f}")

firebase_admin.delete_app(app)
print("\nDone.")
