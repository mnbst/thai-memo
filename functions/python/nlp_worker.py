"""NLP 後処理を別プロセスで実行するワーカー。

`nlp` モジュールのインポート（pythainlp + th2ipa）は CPU バウンドで GIL を握り
続けるため、同一プロセス内のスレッドで先読みすると LLM レスポンスの受信・パースや
後続処理を巻き込んで遅くする（dev 実測: コールド時の NLP 後処理 1.2s → 4.8s）。
GIL はプロセス単位なので、インポートと後処理を子プロセスへ追い出して並列化する。

親との通信は stdin/stdout の JSON Lines。multiprocessing の spawn は
`__main__`（Cloud Run では functions-framework）を子で再実行しうるため使わない。

プロトコル:
    親 → 子: {"sentence": {...}, "lang": "ja"|"en"}\\n（lang 省略時は ja）
    子 → 親: {"ok": true, "sentence": {...}}\\n / {"ok": false, "error": "..."}\\n
    子は起動直後、インポート完了時点で {"ready": true}\\n を1行出力する。
"""

import json
import sys
import time


def main() -> None:
    started = time.perf_counter()
    try:
        from nlp import enrich_with_nlp
    except Exception as exc:  # インポート失敗は親にフォールバックさせる
        sys.stdout.write(json.dumps({"ready": False, "error": str(exc)}) + "\n")
        sys.stdout.flush()
        return
    import_ms = round((time.perf_counter() - started) * 1000)

    # PyThaiNLP を軽量ロードできたか。無言で通常 import に落ちていると
    # コールドが遅くなるだけで気付けないため、毎回ログに残す。
    try:
        from pythainlp_fast import is_fast_path

        fast_path = is_fast_path()
    except Exception:
        fast_path = None

    # stdout は親との JSON Lines プロトコルなので、ログは stderr に出す。
    print(
        f"nlp_worker import: {import_ms}ms fast_path={fast_path}",
        file=sys.stderr,
        flush=True,
    )

    sys.stdout.write(json.dumps({"ready": True, "importMs": import_ms}) + "\n")
    sys.stdout.flush()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            sentence = req["sentence"]
            # lang を送らない旧プロトコルは ja（品詞ラベルが日本語のまま）。
            enrich_with_nlp(sentence, req.get("lang", "ja"))
            out = {"ok": True, "sentence": sentence}
        except Exception as exc:
            out = {"ok": False, "error": str(exc)}
        sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
