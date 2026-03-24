# AGENTS.md

## Python test environment

- Python のテスト、lint、スクリプト実行は常に `functions/python/.venv` の環境を優先して使うこと。
- 特に `functions/python` 配下で検証する場合は、`functions/python/.venv/bin/python` を使ってテストを実行すること。
- `pytest` を使う場合もグローバル環境や `uv run` より先に `functions/python/.venv/bin/python -m pytest` を試すこと。
