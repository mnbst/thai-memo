"""themes/bl_drama.py のプロンプト断片を Python 実装から書き出す。

Go 版 internal/bldrama との差分テストに使う。全ショットぶんを固定で出す
（選出の抽選部分は Go 側の単体テストで見る）。

実行: functions/python/venv/bin/python scripts/daily_golden/gen_bldrama_golden.py
出力: functions/python/scripts/daily_golden/bldrama_golden.json
"""

import json
import os
import sys
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from themes import bl_drama as bd  # noqa: E402


def main() -> None:
    sections = []
    for shot_id in bd._SHOT_CONTEXT:
        # pick_drama_shot を固定して、断片の組み立てだけを取り出す。
        with mock.patch.object(bd, "pick_drama_shot", return_value=shot_id):
            section = bd.build_drama_prompt_section(["กิน"])
        sections.append({
            "shot_id": shot_id,
            "shot": bd.BL_DRAMA_SHOTS[shot_id],
            "context": section["context"],
            "required": section["required"],
        })

    out = {
        "sections": sections,
        "shot_ids": list(bd._SHOT_CONTEXT),
        "shots": bd.BL_DRAMA_SHOTS,
        "shot_context": bd._SHOT_CONTEXT,
    }

    path = os.path.join(os.path.dirname(__file__), "bldrama_golden.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print("wrote", path)
    print(f"  sections: {len(sections)}")


if __name__ == "__main__":
    main()
