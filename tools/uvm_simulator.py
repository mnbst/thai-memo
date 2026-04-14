"""UVM 語彙成長シミュレーター

語彙スコア(estimated_vocab)の日次推移をシミュレートし、
定数チューニングの最適解を探るための Streamlit アプリ。

Usage:
    cd tools && uv run streamlit run uvm_simulator.py
"""

import math
import random

import streamlit as st
import pandas as pd
import plotly.graph_objects as go

# ---------------------------------------------------------------------------
# シミュレーション本体
# ---------------------------------------------------------------------------


def update_p(
    p: float,
    correct: bool,
    quiz_attempts: int,
    alpha_correct_max: float,
    alpha_correct_min: float,
    alpha_incorrect_max: float,
    alpha_incorrect_min: float,
    alpha_decay_k: float,
    p_min: float,
    p_max: float,
) -> float:
    if correct:
        alpha = alpha_correct_min + (alpha_correct_max - alpha_correct_min) * math.exp(
            -alpha_decay_k * quiz_attempts
        )
        p = p + alpha * (1 - p)
    else:
        alpha = alpha_incorrect_min + (
            alpha_incorrect_max - alpha_incorrect_min
        ) * math.exp(-alpha_decay_k * quiz_attempts)
        p = p - alpha * p
    return max(p_min, min(p_max, p))


def moving_avg(
    words_by_rank: dict[int, float], center: int, window: int, unknown_word_p: float
) -> float:
    """rank 周辺の平均 P を計算する（実アプリの estimate_vocab と同ロジック）。"""
    total = sum(
        words_by_rank.get(r, unknown_word_p)
        for r in range(center - window, center + window + 1)
    )
    return total / (2 * window + 1)


def simulate(
    days: int,
    sentences_per_day: int,
    quizzes_per_day: int,
    questions_per_quiz: int,
    max_review_sentences: int,
    first_correct_rate: float,
    subsequent_correct_rate: float,
    usage_rate: float,
    srs_days: list[int],
    # UVM constants
    alpha_correct_max: float,
    alpha_correct_min: float,
    alpha_incorrect_max: float,
    alpha_incorrect_min: float,
    alpha_decay_k: float,
    new_word_p: float,
    alpha_exposure: float,
    freq_band_forward: int,
    band_lookback: int,
    p_decay_per_day: float,
    p_min: float,
    p_max: float,
    exposure_words_per_sentence: int,
    unknown_word_p: float = 0.3,
    moving_avg_window: int = 10,
    monotonic_vocab: bool = True,
) -> pd.DataFrame:
    """日次シミュレーションを実行し、結果を DataFrame で返す。"""

    # 状態: word_id -> {p, quiz_attempts, last_quiz_day}
    words: dict[int, dict] = {}
    # 例文: [{day_created, key_word_id, exposed_word_ids}]
    sentences: list[dict] = []
    # freq_rank 的な順序: word_id = rank (0-indexed)
    # next_word_id = 0
    estimated_vocab = 0

    history = []

    for day in range(days):
        # --- 日次 P 減衰 ---
        if p_decay_per_day > 0:
            for w in words.values():
                w["p"] = max(p_min, w["p"] - p_decay_per_day)

        # --- 使用しない日はスキップ (P減衰のみ適用) ---
        active_today = random.random() < usage_rate

        # --- 例文生成 ---
        for _ in range(sentences_per_day if active_today else 0):
            # 帯域内の key_word 選定 (P 昇順)
            band_low = max(0, estimated_vocab - band_lookback)
            band_high = estimated_vocab + freq_band_forward

            # 帯域内の候補を P 昇順でソート
            candidates = []
            for wid in range(band_low, band_high + 1):
                p_val = words[wid]["p"] if wid in words else new_word_p
                candidates.append((wid, p_val))
            candidates.sort(key=lambda x: (x[1], random.random()))

            if not candidates:
                continue

            key_word_id = candidates[0][0]

            # 露出: key_word + 帯域内の周辺語
            exposed = [key_word_id]
            nearby = [wid for wid, _ in candidates if wid != key_word_id]
            extra_count = min(exposure_words_per_sentence - 1, len(nearby))
            if extra_count > 0:
                exposed.extend(random.sample(nearby, extra_count))

            # 露出による P 更新 (key_word のみ UVM 登録)
            wid = key_word_id
            if wid not in words:
                words[wid] = {
                    "p": new_word_p,
                    "quiz_attempts": 0,
                    "last_quiz_day": -999,
                }
            else:
                w = words[wid]
                w["p"] = min(p_max, w["p"] + alpha_exposure * (1 - w["p"]))

            sentences.append(
                {
                    "day_created": day,
                    "key_word_id": key_word_id,
                    "exposed_word_ids": exposed,
                }
            )

        # --- クイズ (SRS) ---
        for _quiz in range(quizzes_per_day if active_today else 0):
            # ① SRS_DAYSからランダムにmax_review_sentences間隔を選び、各1文を選出
            shuffled_intervals = random.sample(
                srs_days, min(max_review_sentences, len(srs_days))
            )
            selected = []
            used_ids = set()

            def p_of(s):
                kw = s["key_word_id"]
                return words[kw]["p"] if kw in words else new_word_p

            for interval in shuffled_intervals:
                if len(selected) >= max_review_sentences:
                    break

                # 当日±1日の全候補をP値昇順で選出
                candidates = [
                    (s, p_of(s))
                    for s in sentences
                    if id(s) not in used_ids
                    and abs((day - s["day_created"]) - interval) <= 1
                ]
                if candidates:
                    candidates.sort(key=lambda x: (x[1], random.random()))
                    s, pv = candidates[0]
                    selected.append((s, pv))
                    used_ids.add(id(s))

            # ② 不足分は SRS 対象外から P 昇順で補充
            if len(selected) < questions_per_quiz:
                non_srs = [(s, p_of(s)) for s in sentences if id(s) not in used_ids]
                non_srs.sort(key=lambda x: (x[1], random.random()))
                remaining = questions_per_quiz - len(selected)
                selected.extend(non_srs[:remaining])

            # クイズ実行
            for s, _ in selected[:questions_per_quiz]:
                kw = s["key_word_id"]
                if kw not in words:
                    words[kw] = {
                        "p": new_word_p,
                        "quiz_attempts": 0,
                        "last_quiz_day": -999,
                    }
                w = words[kw]
                rate = (
                    first_correct_rate
                    if w["quiz_attempts"] == 0
                    else subsequent_correct_rate
                )
                correct = random.random() < rate
                w["p"] = update_p(
                    w["p"],
                    correct,
                    w["quiz_attempts"],
                    alpha_correct_max,
                    alpha_correct_min,
                    alpha_incorrect_max,
                    alpha_incorrect_min,
                    alpha_decay_k,
                    p_min,
                    p_max,
                )
                w["quiz_attempts"] += 1
                w["last_quiz_day"] = day

        # --- estimated_vocab 計算 (実アプリと同ロジック: moving_avg が 0.5 を下回る最初の rank) ---
        words_by_rank = {wid: w["p"] for wid, w in words.items()}
        known_max_rank = max(
            (wid for wid, w in words.items() if w["p"] > 0.5),
            default=0,
        )
        new_estimated = estimated_vocab
        for r in range(estimated_vocab - 50, estimated_vocab + 51):
            if r < 0:
                continue
            avg = moving_avg(words_by_rank, r, moving_avg_window, unknown_word_p)
            if avg < 0.5:
                new_estimated = max(known_max_rank, r, 0)
                break
        else:
            new_estimated = max(known_max_rank, estimated_vocab, 0)
        if monotonic_vocab:
            estimated_vocab = max(estimated_vocab, new_estimated)
        else:
            estimated_vocab = new_estimated

        # 統計収集
        total_words = len(words)
        known_count = sum(1 for w in words.values() if w["p"] > 0.5)
        avg_p = sum(w["p"] for w in words.values()) / total_words if total_words else 0
        p_above_04 = sum(1 for w in words.values() if 0.4 < w["p"] <= 0.5)
        quiz_zero = sum(1 for w in words.values() if w["quiz_attempts"] == 0)

        history.append(
            {
                "day": day + 1,
                "estimated_vocab": estimated_vocab,
                "known_words": known_count,
                "total_words": total_words,
                "avg_p": avg_p,
                "p_0.4-0.5": p_above_04,
                "quiz_attempts=0": quiz_zero,
            }
        )

    return pd.DataFrame(history)


# ---------------------------------------------------------------------------
# Streamlit UI
# ---------------------------------------------------------------------------

st.set_page_config(page_title="UVM Simulator", layout="wide")
st.title("UVM Vocab Growth Simulator")

# --- Sidebar: Parameters ---
with st.sidebar:
    st.header("Simulation")
    days = st.slider("Days", 7, 365, 60)
    sentences_per_day = st.slider("Sentences/day", 1, 15, 10)
    quizzes_per_day = st.slider("Quizzes/day", 1, 15, 10)
    questions_per_quiz = st.slider("Questions/quiz", 1, 10, 8)
    max_review = st.slider("MAX_REVIEW_SENTENCES", 1, 20, 1)
    first_correct_rate = st.slider("Correct rate (1st attempt)", 0.0, 1.0, 0.8, 0.05)
    subsequent_correct_rate = st.slider(
        "Correct rate (2nd+ attempts)", 0.0, 1.0, 0.95, 0.05
    )
    monotonic_vocab = st.checkbox("Monotonic vocab (不減少)", value=True)
    usage_rate = st.slider("Usage rate (days active)", 0.0, 1.0, 1.0, 0.05)
    exposure_words = st.slider("Exposure words/sentence", 1, 15, 5)

    st.header("UVM Constants")
    col1, col2 = st.columns(2)
    with col1:
        alpha_correct_max = st.number_input("ALPHA_CORRECT_MAX", 0.01, 1.0, 0.35, 0.01)
        alpha_incorrect_max = st.number_input(
            "ALPHA_INCORRECT_MAX", 0.01, 1.0, 0.18, 0.01
        )
        alpha_decay_k = st.number_input("ALPHA_DECAY_K", 0.01, 1.0, 0.08, 0.01)
        alpha_exposure = st.number_input(
            "ALPHA_EXPOSURE", 0.001, 0.2, 0.03, 0.005, format="%.3f"
        )
    with col2:
        alpha_correct_min = st.number_input(
            "ALPHA_CORRECT_MIN", 0.001, 0.5, 0.02, 0.005, format="%.3f"
        )
        alpha_incorrect_min = st.number_input(
            "ALPHA_INCORRECT_MIN", 0.001, 0.5, 0.02, 0.005, format="%.3f"
        )
        new_word_p = st.number_input("NEW_WORD_P", 0.01, 0.5, 0.1, 0.01)
        unknown_word_p = st.number_input("UNKNOWN_WORD_P", 0.01, 0.5, 0.3, 0.01)

    freq_band_forward = st.slider("FREQ_BAND_FORWARD", 1, 50, 15)
    band_lookback = st.slider("Band lookback (backward)", 0, 20, 5)
    moving_avg_window = st.slider("Moving avg window (±ranks)", 1, 30, 10)
    p_decay = st.number_input("P_DECAY_PER_DAY", 0.0, 0.1, 0.0, 0.005, format="%.3f")

    seed = st.number_input("Random seed", 0, 9999, 42, 1)

# --- Run simulation ---
random.seed(seed)
df = simulate(
    days=days,
    sentences_per_day=sentences_per_day,
    quizzes_per_day=quizzes_per_day,
    questions_per_quiz=questions_per_quiz,
    max_review_sentences=max_review,
    first_correct_rate=first_correct_rate,
    subsequent_correct_rate=subsequent_correct_rate,
    usage_rate=usage_rate,
    srs_days=[1, 3, 7, 14, 30],
    alpha_correct_max=alpha_correct_max,
    alpha_correct_min=alpha_correct_min,
    alpha_incorrect_max=alpha_incorrect_max,
    alpha_incorrect_min=alpha_incorrect_min,
    alpha_decay_k=alpha_decay_k,
    new_word_p=new_word_p,
    alpha_exposure=alpha_exposure,
    freq_band_forward=freq_band_forward,
    band_lookback=band_lookback,
    p_decay_per_day=p_decay,
    p_min=0.0,
    p_max=0.99,
    unknown_word_p=unknown_word_p,
    moving_avg_window=moving_avg_window,
    monotonic_vocab=monotonic_vocab,
    exposure_words_per_sentence=exposure_words,
)

# --- Charts ---
fig = go.Figure()
fig.add_trace(
    go.Scatter(
        x=df["day"], y=df["estimated_vocab"], name="estimated_vocab", line=dict(width=3)
    )
)
fig.add_trace(
    go.Scatter(
        x=df["day"],
        y=df["known_words"],
        name="known (P>0.5)",
        line=dict(dash="dash"),
    )
)
fig.add_trace(
    go.Scatter(
        x=df["day"], y=df["total_words"], name="total UVM words", line=dict(dash="dot")
    )
)
fig.update_layout(
    title="Vocab Growth",
    xaxis_title="Day",
    yaxis_title="Words",
    height=500,
)
st.plotly_chart(fig, width="stretch")

# P distribution over time
col1, col2 = st.columns(2)
with col1:
    fig2 = go.Figure()
    fig2.add_trace(go.Scatter(x=df["day"], y=df["avg_p"], name="avg P"))
    fig2.add_trace(
        go.Scatter(x=df["day"], y=df["p_0.4-0.5"], name="0.4<P<=0.5 count", yaxis="y2")
    )
    fig2.update_layout(
        title="P Value Trends",
        xaxis_title="Day",
        yaxis_title="Avg P",
        yaxis2=dict(title="Count", overlaying="y", side="right"),
        height=400,
    )
    st.plotly_chart(fig2, width="stretch")

with col2:
    fig3 = go.Figure()
    fig3.add_trace(
        go.Scatter(x=df["day"], y=df["quiz_attempts=0"], name="quiz_attempts=0")
    )
    fig3.update_layout(
        title="Unquizzed Words",
        xaxis_title="Day",
        yaxis_title="Count",
        height=400,
    )
    st.plotly_chart(fig3, width="stretch")

# Growth rate
df["daily_growth"] = df["estimated_vocab"].diff().fillna(df["estimated_vocab"].iloc[0])
fig4 = go.Figure()
fig4.add_trace(go.Bar(x=df["day"], y=df["daily_growth"], name="Daily growth"))
fig4.add_trace(
    go.Scatter(
        x=df["day"],
        y=df["daily_growth"].rolling(7).mean(),
        name="7-day avg",
        line=dict(color="red", width=2),
    )
)
fig4.update_layout(
    title="Daily Vocab Growth Rate",
    xaxis_title="Day",
    yaxis_title="Words/day",
    height=400,
)
st.plotly_chart(fig4, width="stretch")

# Raw data
with st.expander("Raw data"):
    st.dataframe(df, width="stretch")
