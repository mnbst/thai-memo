"""UVM (User Vocabulary Model) コアロジック

ユーザーごとの語彙習得状態を管理する。
Firestore の users/{uid}/uvm/{word} コレクションに対して読み書きを行う。

【Firestore ドキュメント構造】
  users/{uid}/uvm/{word}:
    - p: float              — P(know) 確率 (0.01〜0.99)
    - quiz_attempts: int    — クイズ回答回数（α減衰に使用）
    - last_seen: float      — 最終閲覧 Unix timestamp
    - last_result: bool     — 直近の正誤

【主な機能】
  - テーマ×語彙レベルに基づくセッション単語の選定 (get_session_words)
  - P(know) 確率の更新 (update_p)
  - クイズ結果からの一括更新 (batch_update_uvm)
  - 語彙スコアの算出 (estimate_vocab, sync_vocab_count)
"""

import json
import math
import random
import time
from collections import Counter
from typing import TYPE_CHECKING, Any, cast

if TYPE_CHECKING:
    import numpy as np

from google.cloud.firestore_v1.base_document import DocumentSnapshot
from google.cloud.firestore_v1.client import Client as FirestoreClient

from embeddings import (
    cosine_similarity,
    find_best_topic,
    get_embedding,
    get_topic_embedding,
)

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------
ALPHA_CORRECT_MAX_TOP = 0.60  # rank≈1（高頻度語）の正解α上限: 1問正解でP=0.1→0.64
ALPHA_CORRECT_MAX_LOW = 0.30  # 高rank（低頻度語）の正解α下限: 2問正解でP>0.5
ALPHA_CORRECT_MIN = 0.02  # 正解時 α の下限（quiz_attempts 大時の収束値）
ALPHA_INCORRECT_MAX_TOP = 0.28  # rank≈1 の不正解α上限
ALPHA_INCORRECT_MAX_LOW = 0.08  # 高rank の不正解α下限
ALPHA_INCORRECT_MIN = 0.02  # 不正解時 α の下限
ALPHA_DECAY_K = 0.08  # α 減衰係数（quiz_attempts による α 減衰速度）
RANK_SCALE_REF = (
    600  # このrankでalpha_maxが上限・下限の中間値になる（rank>3000で3問正解挙動）
)
P_MIN = 0.0  # P の下限
P_MAX = 0.99  # P の上限
NEW_WORD_P = 0.1  # 新規単語の初期 P 値
ALPHA_EXPOSURE = 0.10  # 例文露出時の P 微増率
UNKNOWN_WORD_P = 0.4  # UVM 未登録語の prior P

# get_session_words 用: estimated_vocab 基準の頻度帯
VOCAB_MAX_DELTA = 3  # 1回の sync で estimated_vocab が動ける最大幅
GAP_SCAN_DEPTH = 50  # 後方スキャンの最大深さ: estimated_vocab - GAP_SCAN_DEPTH
# 前方スキャンの初期幅と、estimated_vocab に対する逓減の緩さ。
# ahead = max(SCAN_AHEAD_MIN, SCAN_BAND_WIDTH - estimated_vocab / SCAN_BAND_DECAY)
SCAN_BAND_WIDTH = 50
SCAN_BAND_DECAY = 2
SCAN_AHEAD_MIN = 8  # 前方スキャンの下限（未習語が必ず候補に入るようにする）


def scan_band(estimated_vocab: int) -> tuple[int, int]:
    """estimated_vocab から key_word 候補のランク帯 [low, high] を返す。

    後方は GAP_SCAN_DEPTH まで深く取り、前方は estimated_vocab が増えるほど狭める。

    前方が広いほど未習語が候補に多く入り estimated_vocab が速く進むが、
    その分だけ後方に未提示語（取りこぼし）が残る。初学者は取りこぼしを許容して
    速く進め、語彙が増えたら後方の穴埋めに寄せる。深い後方が中期に回収する。

    2026-08-05 シミュレーション（1文/日・誤答20%・20シード）:
    後方25/前方10固定は 2年で estimated_vocab 921 に対し取りこぼし 202。
    この設定は d30 の estimated_vocab が 43→73 に上がりつつ取りこぼしは 48 に減る。
    前方下限を 5 まで下げると 3文/日以上で候補が枯渇し、2年の習得語数が
    1037→778 に落ちるため 8 で止める。
    """
    behind = min(max(0, estimated_vocab), GAP_SCAN_DEPTH)
    ahead = max(SCAN_AHEAD_MIN, SCAN_BAND_WIDTH - estimated_vocab / SCAN_BAND_DECAY)
    return max(0, estimated_vocab - behind), estimated_vocab + int(ahead)


def moving_avg(words_by_rank: dict[int, float], center: int, window: int = 10) -> float:
    """rank 周辺の平均習熟度を計算する（語彙境界推定用）。

    window = ±10 の範囲で P の平均を取る。
    UVM 未登録語には UNKNOWN_WORD_P を使用する。

    freq_rank は拘束形態素を除いた連番なので、rank に穴はない。
    """
    total = 0.0
    for r in range(center - window, center + window + 1):
        total += words_by_rank.get(r, UNKNOWN_WORD_P)
    return total / (2 * window + 1)


def estimate_vocab(docs: list, freq_rank: dict[str, int], center: int = 0) -> int:
    """語彙境界（P ≈ 0.5 となる rank）を推定する。

    UVM ドキュメント群を rank でインデックスし、
    moving_avg が 0.5 を下回る最初の rank を返す。
    探索範囲は center ± 200。

    データがスパース（moving_avg が機能しにくい）場合は、
    P > 0.5 の語の最大 rank をフォールバックとして使う。

    Args:
        center: 探索中心（通常は現在の estimated_vocab）。
    """
    # docs から {rank: p} のマップを構築
    words_by_rank: dict[int, float] = {}
    weighted_ranks: list[tuple[float, int]] = []
    for doc in docs:
        p = (doc.to_dict() or {}).get("p", NEW_WORD_P)
        rank = freq_rank.get(doc.id)
        if rank is not None:
            words_by_rank[rank] = p
            weighted_ranks.append((p, rank))

    if not weighted_ranks:
        return 0

    # スパースデータ用フォールバック: P > 0.5 の語の最大 rank
    known_max_rank = max(
        (rank for p, rank in weighted_ranks if p > 0.5),
        default=0,
    )

    # center が未指定 (0) の場合は加重平均を使用
    if center <= 0:
        total_p = sum(p for p, _ in weighted_ranks)
        if total_p <= 0:
            return known_max_rank
        center = int(sum(p * rank for p, rank in weighted_ranks) / total_p)

    # center ± 50 の範囲で P < 0.5 となる rank を探索
    for r in range(center - 50, center + 51):
        avg = moving_avg(words_by_rank, r)
        if avg < 0.42:
            return max(known_max_rank, r, 0)

    return max(known_max_rank, center, 0)


def sync_estimated_vocab(
    db: FirestoreClient,
    uid: str,
    freq_rank: dict[str, int],
    max_vocab: int | None = None,
) -> None:
    """users/{uid} の estimated_vocab を効率的に更新する。

    現在の estimated_vocab を中心に ±50 の freq_rank 範囲の単語だけ
    UVM から取得して再計算する（全件取得を回避）。
    """
    user_ref = db.collection("users").document(uid)
    user_doc = cast("DocumentSnapshot", user_ref.get())
    current_estimate = 0
    if user_doc.exists:
        current_estimate = (user_doc.to_dict() or {}).get("estimated_vocab", 0)

    # freq_rank から探索範囲内の単語を抽出
    scan_low = max(0, current_estimate - 50)
    scan_high = current_estimate + 51
    target_words = [
        word for word, rank in freq_rank.items() if scan_low <= rank < scan_high
    ]

    # 対象単語の UVM ドキュメントだけ取得
    uvm_ref = user_ref.collection("uvm")
    refs = [uvm_ref.document(word) for word in target_words]
    docs = [snap for snap in db.get_all(refs) if snap.exists] if refs else []

    raw = estimate_vocab(docs, freq_rank, center=current_estimate)
    delta = raw - current_estimate
    clamped_delta = max(-VOCAB_MAX_DELTA, min(VOCAB_MAX_DELTA, delta))
    estimated = max(0, current_estimate + clamped_delta)
    if max_vocab is not None:
        estimated = min(estimated, max_vocab)
    user_ref.set({"estimated_vocab": estimated}, merge=True)
    publish_leaderboard_vocab(db, uid, estimated)


# ランキングの表示名に使うタイ人名。
# 名はタイの一般的なチューレン（ชื่อเล่น＝あだ名）、姓はタイに多い姓の形。
# 名＋姓の組み合わせだけで十分にばらけるので、数字は衝突時のみ足す。
NICKNAME_GIVEN_NAMES = (
    "Ploy", "Mint", "Fern", "Nan", "Aum", "Beam", "Boss", "Champ",
    "Earth", "Film", "Gift", "Ice", "June", "Ken", "Mook", "Nut",
    "Oat", "Pim", "Praew", "Tan", "Ton", "View", "Win", "Yok",
    "Bank", "Best", "Gun", "Nam", "Fah", "Bow", "Cake", "Dew",
    "Focus", "Golf", "Jane", "Kwan", "Lek", "May", "Nink", "Opal",
    "Pat", "Puy", "Rung", "Som", "Tar", "Tui", "Ummi", "Vee",
    "Wan", "Yui", "Bam", "Chom", "Da", "Eak", "Grace", "Jib",
    "Kim", "Mai", "New", "Noon", "Pao", "Ping", "Sea", "Tam",
)
NICKNAME_SURNAMES = (
    "Sukjai", "Chaiyaphon", "Srisuwan", "Wongthep", "Rattanakorn", "Boonmee",
    "Phongsak", "Thongchai", "Saetang", "Kittisak", "Jaidee", "Maneerat",
    "Piyawat", "Sombat", "Chansiri", "Preecha", "Narong", "Sirikul",
    "Wattana", "Anuwat", "Kanjana", "Lertsak", "Meesuk", "Nopporn",
    "Panya", "Rojana", "Sanguan", "Suwannee", "Tavorn", "Udomsak",
    "Wiriya", "Yotsapon", "Amporn", "Bunnag", "Charoen", "Duangjai",
    "Intira", "Kraisorn", "Malai", "Nakhon", "Phanit", "Rungrat",
    "Somchai", "Thanapon", "Uthai", "Wichian", "Yindee", "Chaowalit",
)


def _assign_nickname(db: FirestoreClient, uid: str) -> str | None:
    """未設定のユーザーに表示名を自動で割り当てる。

    ユーザーに入力させない代わりに、nicknames/{小文字の名前} を create で
    押さえて一意性を担保する（既存なら AlreadyExists で弾かれる）。
    """
    from google.api_core.exceptions import AlreadyExists

    for attempt in range(5):
        name = (
            f"{random.choice(NICKNAME_GIVEN_NAMES)} "
            f"{random.choice(NICKNAME_SURNAMES)}"
        )
        # 名＋姓が埋まっていたら数字で逃がす
        if attempt >= 2:
            name = f"{name} {random.randint(10, 99)}"
        try:
            db.collection("nicknames").document(name.lower()).create({"uid": uid})
            return name
        except AlreadyExists:
            continue
    return None


def publish_leaderboard_vocab(db: FirestoreClient, uid: str, vocab: int) -> None:
    """語彙スコアをランキング用の公開コレクションへ複製する。

    users/{uid} は本人しか読めないため、ランキングは leaderboard/{uid} を別に持つ。
    vocab も nickname もサーバー専用（rules でクライアント書き込みを全面禁止）。
    表示名は最初の1回だけ自動採番し、以降は触らない。
    free は estimated_vocab 自体が FREE_TIER_MAX_VOCAB でキャップされた値なので、
    ここでは追加のキャップをしない。
    """
    try:
        ref = db.collection("leaderboard").document(uid)
        doc = cast("DocumentSnapshot", ref.get())
        payload: dict[str, Any] = {"vocab": int(vocab), "updated_at": time.time()}
        if not (doc.exists and (doc.to_dict() or {}).get("nickname")):
            nickname = _assign_nickname(db, uid)
            if nickname:
                payload["nickname"] = nickname
        ref.set(payload, merge=True)
    except Exception as exc:  # ランキングの失敗で例文生成を止めない
        print(f"publish_leaderboard_vocab failed: {exc}")


def update_p(
    p: float,
    correct: bool,
    quiz_attempts: int = 0,
    rank: int | None = None,
    hint_multiplier: float = 1.0,
) -> float:
    """P(know) を正誤に基づいて更新する。

    【更新式】
      rank に応じて alpha_max をスケーリングする。
        scale = RANK_SCALE_REF / (rank + RANK_SCALE_REF)  ← rank が低いほど 1 に近い
        alpha_max = ALPHA_*_MAX_LOW + (ALPHA_*_MAX_TOP - ALPHA_*_MAX_LOW) * scale
      正解時: α = ALPHA_CORRECT_MIN + (alpha_max - ALPHA_CORRECT_MIN) * exp(-k * quiz_attempts)
              p_new = p + α(1 - p)
      不正解: α = ALPHA_INCORRECT_MIN + (alpha_max - ALPHA_INCORRECT_MIN) * exp(-k * quiz_attempts)
              p_new = p - α * p

    【rank による挙動（quiz_attempts=0, p=0.1 から）】
      rank ≈ 1  (scale≈1, α≈0.50): 正解1問で P > 0.5
      rank ≈ 600 (scale=0.5, α=0.35): 正解2問で P > 0.5
      rank > 3000 (scale<0.17, α<0.25): 正解3問で P > 0.5

    rank=None の場合は scale=0.5（中間値）を使用する。
    quiz_attempts が多いほど α が小さくなり、P 変化量が小さくなる（収束挙動）。
    結果は [P_MIN, P_MAX] にクリッピングして返す。
    """
    scale = RANK_SCALE_REF / (rank + RANK_SCALE_REF) if rank is not None else 0.5
    if correct:
        alpha_max = (
            ALPHA_CORRECT_MAX_LOW
            + (ALPHA_CORRECT_MAX_TOP - ALPHA_CORRECT_MAX_LOW) * scale
        )
        alpha = ALPHA_CORRECT_MIN + (alpha_max - ALPHA_CORRECT_MIN) * math.exp(
            -ALPHA_DECAY_K * quiz_attempts
        )
        p = p + alpha * hint_multiplier * (1 - p)
    else:
        alpha_max = (
            ALPHA_INCORRECT_MAX_LOW
            + (ALPHA_INCORRECT_MAX_TOP - ALPHA_INCORRECT_MAX_LOW) * scale
        )
        alpha = ALPHA_INCORRECT_MIN + (alpha_max - ALPHA_INCORRECT_MIN) * math.exp(
            -ALPHA_DECAY_K * quiz_attempts
        )
        p = p - alpha * hint_multiplier * p
    return max(P_MIN, min(P_MAX, p))


TOPIC_FILTER_THRESHOLD = 0.3
TOPIC_FILTER_EXPAND_STEP = 50


def _filter_candidates_by_topic(
    candidates: list[dict[str, Any]],
    topic_emb: "np.ndarray",
    freq_rank: dict[str, int],
    scan_low: int,
) -> list[dict[str, Any]]:
    """テーマembeddingとの類似度で候補をフィルタする。

    帯域内で閾値以上の候補がなければ、低頻度側へ帯域を広げて探索する。
    """
    filtered = []
    for w in candidates:
        word_emb = get_embedding(w["word"])
        if word_emb is None:
            continue
        sim = cosine_similarity(word_emb, topic_emb)
        if sim >= TOPIC_FILTER_THRESHOLD:
            filtered.append(w)

    if filtered:
        return filtered

    # 帯域外を低頻度側（rank が大きい方）へ段階的に探索
    expand_low = scan_low
    for _ in range(5):
        expand_high = expand_low
        expand_low = max(0, expand_low - TOPIC_FILTER_EXPAND_STEP)
        if expand_low >= expand_high:
            break
        extra = [
            {"word": word, "rank": rank}
            for word, rank in freq_rank.items()
            if expand_low <= rank < expand_high and len(word) >= 2
        ]
        for w in extra:
            word_emb = get_embedding(w["word"])
            if word_emb is None:
                continue
            if cosine_similarity(word_emb, topic_emb) >= TOPIC_FILTER_THRESHOLD:
                filtered.append(w)
        if filtered:
            return filtered

    return candidates


def get_session_words(
    db: FirestoreClient,
    uid: str,
    freq_rank: dict[str, int],
    topic: str,
    count: int = 1,
    max_vocab: int | None = None,
    topics_pool: list[str] | None = None,
    estimated_vocab: int | None = None,
) -> tuple[list[str], str]:
    """統合スキャン方式でセッション単語を選定する。

    【選定ロジック】
    1. scan_band(estimated_vocab) が返すランク帯の範囲で
       UVM未登録 or P=0 の語を、rank が高いほど選ばれやすい重み付きで選出
       → 取りこぼしを拾いつつ境界付近の語も混ざるためスコアも徐々に上がる
    2. 選出した key_word の embedding と topic_embeddings のコサイン類似度で最適テーマを決定
    3. テーマ指定がある場合はそのまま使用

    Args:
        db: Firestore クライアント
        uid: ユーザー UID
        freq_rank: {word: rank} — 頻出順位辞書
        topic: テーマ文字列（空ならembeddingで自動選択）
        count: 選定する単語数（デフォルト 1）
        max_vocab: 語彙帯域の上限（free ティアでは 100）。None なら制限なし。
        topics_pool: テーマ候補リスト（embedding でのテーマ選択に使用）。
        estimated_vocab: 呼び出し元で取得済みの語彙スコア。省略時は Firestore から読む。

    Returns:
        (選定された単語のリスト, 使用されたテーマ)
    """
    # ユーザーの語彙スコアを取得
    if estimated_vocab is None:
        user_doc = db.collection("users").document(uid).get()
        user_data = (user_doc.to_dict() or {}) if user_doc.exists else {}  # type: ignore
        estimated_vocab = user_data.get("estimated_vocab", 0)
    if max_vocab is not None and isinstance(estimated_vocab, int):
        estimated_vocab = min(estimated_vocab, max_vocab)

    scan_low, scan_high = scan_band(estimated_vocab)  # type: ignore
    if max_vocab is not None:
        scan_high = min(scan_high, max_vocab)

    selected: list[dict[str, Any]] = []

    # --- 統合スキャン: scan_low ~ scan_high で P=0/未登録の語を rank 重み付き選出 ---
    candidates = [
        {"word": word, "rank": rank}
        for word, rank in freq_rank.items()
        if scan_low <= rank <= scan_high and len(word) >= 2
    ]

    # --- テーマ指定時: embeddingフィルタで候補を絞り込む ---
    topic_emb = get_topic_embedding(topic) if topic else None
    if topic and topic_emb is not None and candidates:
        candidates = _filter_candidates_by_topic(
            candidates, topic_emb, freq_rank, scan_low,
        )

    if not candidates:
        print(
            f"get_session_words: no candidates, estimated_vocab={estimated_vocab}, "
            f"scan=[{scan_low}, {scan_high}], topic={topic}"
        )
        return [], topic or ""

    word_set = {w["word"] for w in candidates}
    uvm_ref = db.collection("users").document(uid).collection("uvm")
    refs = [uvm_ref.document(w) for w in word_set]
    p_map: dict[str, float] = {}
    for snap in db.get_all(refs):
        if snap.exists:
            p_val = (snap.to_dict() or {}).get("p")
            if isinstance(p_val, (int, float)):
                p_map[snap.id] = float(p_val)

    zero_p = [
        w for w in candidates
        if w["word"] not in p_map or p_map[w["word"]] == 0.0
    ]
    if zero_p:
        max_rank = max(w["rank"] for w in zero_p)
        weights = [math.sqrt(max_rank - w["rank"] + 1) for w in zero_p]
        for _ in range(min(count, len(zero_p))):
            index = random.choices(range(len(zero_p)), weights=weights, k=1)[0]
            selected.append(zero_p.pop(index))
            weights.pop(index)
    else:
        remaining = list(candidates)
        remaining_weights = [
            max(0.0, 1.0 - p_map.get(w["word"], 0.0))
            for w in remaining
        ]
        for _ in range(min(count, len(remaining))):
            if sum(remaining_weights) <= 0:
                index = random.randrange(len(remaining))
            else:
                index = random.choices(
                    range(len(remaining)),
                    weights=remaining_weights,
                    k=1,
                )[0]
            selected.append(remaining.pop(index))
            remaining_weights.pop(index)

    words = [w["word"] for w in selected]

    # --- テーマ選択: 指定あり→そのまま / なし→embedding自動選択 ---
    if topic:
        chosen_topic = topic
    else:
        # 閾値未達（＝key_word がどのテーマとも結びつかない機能語など）は
        # "" のまま返し、テーマを LLM に決めさせる。ランダムに埋めない。
        chosen_topic = (
            find_best_topic(words[0], topics_pool, top_k=5, threshold=0.545) or ""
        )

    print(
        json.dumps(
            {
                "message": "get_session_words",
                "topic": chosen_topic,
                "estimated_vocab": estimated_vocab,
                "scan": [scan_low, scan_high],
                "selected": words,
            }
        )
    )

    return words, chosen_topic


def get_sentence_words(sentence: dict[str, Any]) -> list[str]:
    """例文の word_breakdown から全単語を重複なしで返す。"""
    seen: set[str] = set()
    words: list[str] = []
    for wb in sentence.get("word_breakdown", []):
        if not isinstance(wb, dict):
            continue
        w = str(wb.get("word", "")).strip()
        if w and w not in seen:
            seen.add(w)
            words.append(w)
    return words


def get_exposed_words(
    sentence: dict[str, Any],
    target_words: list[str] | None,
) -> list[str]:
    """例文内に実際に出現したターゲット語を単語ごとに1回だけ返す。"""
    if not target_words:
        return []

    target_word_set = set(target_words)
    return [w for w in get_sentence_words(sentence) if w in target_word_set]


def register_exposure(
    db: FirestoreClient,
    uid: str,
    words: list[str],
    target_words: list[str] | None = None,
) -> None:
    """露出による P 微増を適用する。

    - 登録済み語: P を ALPHA_EXPOSURE 分微増
    - 未登録語: target_words に含まれる場合のみ新規作成（P=NEW_WORD_P で登録）
    """
    now = time.time()
    batch = db.batch()
    uvm_ref = db.collection("users").document(uid).collection("uvm")
    target_word_set = set(target_words) if target_words else set()
    wrote = 0

    for word, count in Counter(words).items():
        doc_ref = uvm_ref.document(word)
        doc = doc_ref.get()
        if doc.exists:
            data = doc.to_dict() or {}
            old_p = data.get("p", NEW_WORD_P)
            new_p = old_p
            for _ in range(count):
                new_p = new_p + ALPHA_EXPOSURE * (1 - new_p)
            batch.update(
                doc_ref,
                {
                    "p": max(P_MIN, min(P_MAX, new_p)),
                    "last_seen": now,
                },
            )
            wrote += count
        elif word in target_word_set:
            # key_word として選出された未登録語は新規作成
            batch.set(
                doc_ref,
                {
                    "word": word,
                    "p": NEW_WORD_P,
                    "quiz_attempts": 0,
                    "last_seen": now,
                    "last_result": None,
                },
            )
            wrote += 1

    if wrote:
        batch.commit()
        print(f"register_exposure: uid={uid}, updated {wrote} word(s)")


LEARNING_CORRECT_MULTIPLIER = 0.1
SENTENCE_REVIEW_CORRECT_MULTIPLIER = 0.1


def batch_update_uvm(
    db: FirestoreClient,
    uid: str,
    results: list[dict[str, Any]],
    freq_rank: dict[str, int] | None = None,
    quiz_type: str = "",
    is_premium: bool = True,
) -> None:
    """クイズ/例文の正誤結果をもとに UVM を一括更新する。

    既存の UVM ドキュメントがあれば P を更新、なければ新規作成する。

    Args:
        db: Firestore クライアント
        uid: ユーザー UID
        results: [{"word": str, "is_correct": bool}, ...] — 各単語の正誤
        quiz_type: "learning" の場合、正解時の α を LEARNING_CORRECT_MULTIPLIER で減衰
    """
    now = time.time()
    batch = db.batch()
    uvm_ref = db.collection("users").document(uid).collection("uvm")

    # 全単語のドキュメントを一括取得
    words = [r["word"] for r in results]
    refs = [uvm_ref.document(word) for word in words]
    docs_map: dict[str, Any] = {}
    for snap in db.get_all(refs):
        if snap.exists:
            docs_map[snap.id] = snap.to_dict() or {}

    for r in results:
        word = r["word"]
        is_correct = r["is_correct"]
        doc_ref = uvm_ref.document(word)

        rank = freq_rank.get(word) if freq_rank else None
        hint_level_raw = r.get("hint_level")
        hint_level = (
            int(hint_level_raw) if isinstance(hint_level_raw, (int, float)) else 0
        )
        hint_multiplier = 1.0 if hint_level == 0 else (0.5 if hint_level == 1 else 0.25)
        if quiz_type == "learning" and is_correct:
            hint_multiplier *= LEARNING_CORRECT_MULTIPLIER
        if r.get("sentence_reviewed") is True and is_correct:
            hint_multiplier *= SENTENCE_REVIEW_CORRECT_MULTIPLIER
        if word in docs_map:
            # --- 既存単語の更新 ---
            data = docs_map[word]
            old_p = data.get("p", NEW_WORD_P)
            quiz_attempts = data.get("quiz_attempts", 0)
            new_p = update_p(old_p, is_correct, quiz_attempts, rank, hint_multiplier)
            batch.update(
                doc_ref,
                {
                    "p": new_p,
                    "quiz_attempts": quiz_attempts + 1,
                    "last_seen": now,
                    "last_result": is_correct,
                },
            )
        else:
            # --- 新規単語の作成（初めて見た単語） ---
            new_p = update_p(NEW_WORD_P, is_correct, 0, rank, hint_multiplier)
            batch.set(
                doc_ref,
                {
                    "word": word,
                    "p": new_p,
                    "quiz_attempts": 1,
                    "last_seen": now,
                    "last_result": is_correct,
                },
            )
    batch.commit()

    if freq_rank is not None:
        from constants import FREE_TIER_MAX_VOCAB

        max_vocab = None if is_premium else FREE_TIER_MAX_VOCAB
        sync_estimated_vocab(db, uid, freq_rank, max_vocab=max_vocab)
