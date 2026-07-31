"""PyThaiNLP を必要なサブモジュールだけロードする軽量ローダ。

`from pythainlp.tag import pos_tag` と書くと `pythainlp/__init__.py` が実行され、
使っていない soundex / spell / transliterate / util まで芋づるで読み込まれる。
特に `util.wordtonum` は import 時に thai_words() のトライを構築するため単独で
約0.9秒かかる（ローカル実測、Cloud Run のコールドではイメージ層の遅延ロードが
上乗せされる）。このモジュールはどれも使っていない。

そこで `sys.modules` に軽量スタブを先に置いてパッケージ `__init__` の実行を飛ばし、
実際に使う submodule だけを直接ロードする。`pythainlp/tag/pos_tag.py` の重い実装は
関数内 import なので、`tag.perceptron` と `tag.unigram` を直接掴めば足りる。

ローカル実測: import 1.319s → 0.370s（出力は現行と完全一致）。

内部レイアウトに依存するため、PyThaiNLP のアップグレードで壊れうる。失敗時は
通常の import に自動フォールバックする（`is_fast_path()` でどちらを使ったか分かる）。
"""

import importlib
import importlib.util
import sys
import types

# pos_tag が受け付けるコーパス。pythainlp/tag/pos_tag.py の _support_corpus と同じ。
_SUPPORT_CORPUS = frozenset(
    {
        "blackboard",
        "blackboard_ud",
        "orchid",
        "orchid_ud",
        "pud",
        "tdtb",
        "tud",
    }
)

_fast_path = False


def is_fast_path() -> bool:
    """軽量ロードに成功したかどうか。テストとログ用。"""
    return _fast_path


def _purge_pythainlp() -> None:
    """スタブを含む pythainlp 関連モジュールを sys.modules から全て消す。

    中途半端なスタブが残ったままだと、その後の通常 import が壊れる。
    """
    for name in [n for n in sys.modules if n == "pythainlp" or n.startswith("pythainlp.")]:
        del sys.modules[name]


def _stub(name: str, path: str) -> types.ModuleType:
    """パッケージの `__init__.py` を実行せずに、submodule 探索だけ通るスタブを作る。"""
    module = types.ModuleType(name)
    module.__path__ = [path]
    module.__file__ = f"{path}/__init__.py"
    sys.modules[name] = module
    return module


def _load_fast() -> tuple:
    """スタブ経由で必要な submodule だけ読み、(perceptron, unigram, tokenize) を返す。"""
    spec = importlib.util.find_spec("pythainlp")  # ここでは実行されない
    if spec is None or not spec.submodule_search_locations:
        raise ImportError("pythainlp not found")
    base = list(spec.submodule_search_locations)[0]

    # pythainlp.corpus.core が `from pythainlp import __version__` を要求する。
    from importlib.metadata import version as _dist_version

    root = _stub("pythainlp", base)
    root.__version__ = _dist_version("pythainlp")

    # pythainlp.tag.perceptron が `from pythainlp.tag import PerceptronTagger,
    # blackboard, orchid` を要求するので、スタブに手で生やしておく。
    tag = _stub("pythainlp.tag", f"{base}/tag")
    tag.PerceptronTagger = importlib.import_module(
        "pythainlp.tag._tag_perceptron"
    ).PerceptronTagger
    tag.blackboard = importlib.import_module("pythainlp.tag.blackboard")
    tag.orchid = importlib.import_module("pythainlp.tag.orchid")

    perceptron = importlib.import_module("pythainlp.tag.perceptron")
    unigram = importlib.import_module("pythainlp.tag.unigram")

    # pythainlp.tokenize が要るのは util.trie.Trie だけ。util の __init__ は
    # spell_words 経由で pythainlp の文字定数を引くので実行させない。
    util = _stub("pythainlp.util", f"{base}/util")
    util.Trie = importlib.import_module("pythainlp.util.trie").Trie

    tokenize = importlib.import_module("pythainlp.tokenize")
    return perceptron, unigram, tokenize


if "pythainlp" in sys.modules:
    # 既に誰かが通常 import している。スタブを挟む余地はないのでそのまま使う。
    from pythainlp.tag import pos_tag as _pos_tag
    from pythainlp.tokenize import subword_tokenize
else:
    try:
        _perceptron, _unigram, _tokenize = _load_fast()
    except Exception as e:  # pragma: no cover - 依存側の変更でしか起きない
        print(f"pythainlp fast import failed, falling back: {e}")
        _purge_pythainlp()
        from pythainlp.tag import pos_tag as _pos_tag
        from pythainlp.tokenize import subword_tokenize
    else:
        _fast_path = True
        subword_tokenize = _tokenize.subword_tokenize

        def _pos_tag(words: list, engine: str = "unigram", corpus: str = "orchid"):
            """`pythainlp.tag.pos_tag` の必要な部分だけを再実装したもの。

            tltk / transformers エンジンは使っていないので対応しない。
            """
            if not words:
                return []
            if corpus not in _SUPPORT_CORPUS:
                raise ValueError(f"pos_tag not support {corpus} corpus.")
            if engine == "perceptron":
                return _perceptron.tag(words, corpus=corpus)
            if engine == "unigram":
                return _unigram.tag(words, corpus=corpus)
            raise ValueError(f"pos_tag not support {engine} engine.")


pos_tag = _pos_tag

__all__ = ["pos_tag", "subword_tokenize", "is_fast_path"]
