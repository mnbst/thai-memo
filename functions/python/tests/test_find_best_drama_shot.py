"""find_best_drama_shot の選出ロジックのテスト。

GCS アクセスは行わず、_shot_embeddings / get_embedding を差し替えて検証する。
"""

from unittest.mock import patch

import numpy as np
import pytest

import embeddings

SHOTS = {"a": "セリフA", "b": "セリフB", "c": "セリフC"}


def _emb(*values: float) -> list[float]:
    return list(values)


@pytest.fixture
def stub_embeddings():
    """embedding テーブルを差し替え、GCS ロードを無効化する。"""
    original = embeddings._shot_embeddings
    with (
        patch.object(embeddings, "_load_data"),
        patch.object(embeddings, "_load_shot_embeddings"),
    ):
        yield
    embeddings._shot_embeddings = original


def _set_table(table: dict[str, list[float]]) -> None:
    embeddings._shot_embeddings = table


class TestFindBestDramaShot:
    def test_picks_the_most_similar_shot(self, stub_embeddings):
        # 単語ベクトルと完全に同じ向きの "b" が最類似。
        _set_table(
            {
                "セリフA": _emb(1.0, 0.0),
                "セリフB": _emb(0.0, 1.0),
                "セリフC": _emb(-1.0, 0.0),
            }
        )
        word_emb = np.array([0.0, 1.0], dtype=np.float32)

        # 重みつきランダムのため、最類似が支配的に選ばれることを分布で確認する。
        with patch.object(embeddings, "get_embedding", return_value=word_emb):
            picks = [embeddings.find_best_drama_shot("รัก", SHOTS) for _ in range(200)]

        assert picks.count("b") > picks.count("a")
        assert picks.count("b") > picks.count("c")
        # 下駄 0.1 があるため最下位も稀に選ばれる（多様性の確保）
        assert set(picks) <= {"a", "b", "c"}

    def test_skips_shots_without_embedding(self, stub_embeddings):
        _set_table({"セリフB": _emb(0.0, 1.0)})
        word_emb = np.array([0.0, 1.0], dtype=np.float32)

        with patch.object(embeddings, "get_embedding", return_value=word_emb):
            picks = {embeddings.find_best_drama_shot("รัก", SHOTS) for _ in range(20)}

        # 本文を書き換えた等で embedding が引けない行は候補に入らない
        assert picks == {"b"}

    def test_skips_dimension_mismatch(self, stub_embeddings):
        # 生成時の output_dimensionality 違い。例外ではなく候補除外になること。
        _set_table(
            {
                "セリフA": _emb(*([0.1] * 3072)),
                "セリフB": _emb(0.0, 1.0),
            }
        )
        word_emb = np.array([0.0, 1.0], dtype=np.float32)

        with patch.object(embeddings, "get_embedding", return_value=word_emb):
            picks = {embeddings.find_best_drama_shot("รัก", SHOTS) for _ in range(20)}

        assert picks == {"b"}

    def test_returns_none_when_all_dimensions_mismatch(self, stub_embeddings):
        # 全滅時も例外を投げない。呼び出し側がランダムへ縮退する。
        _set_table({"セリフA": _emb(*([0.1] * 3072))})
        word_emb = np.array([0.0, 1.0], dtype=np.float32)

        with patch.object(embeddings, "get_embedding", return_value=word_emb):
            assert embeddings.find_best_drama_shot("รัก", SHOTS) is None

    def test_returns_none_when_word_embedding_unavailable(self, stub_embeddings):
        _set_table({"セリフA": _emb(1.0, 0.0)})

        with patch.object(embeddings, "get_embedding", return_value=None):
            assert embeddings.find_best_drama_shot("ไม่มี", SHOTS) is None


class TestShotEmbeddingDataContract:
    """本番データとコードの整合。ズレると全ショットが候補から外れる。"""

    def test_every_shot_text_is_unique(self):
        from themes.bl_drama import BL_DRAMA_SHOTS

        # embedding はタイ語本文をキーにするため、重複本文があると
        # 別ショットが同一エントリを共有してしまう。
        texts = list(BL_DRAMA_SHOTS.values())
        assert len(texts) == len(set(texts))
