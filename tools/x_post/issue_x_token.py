"""別の X アカウント用の Access Token を発行し、Secret Manager に直接入れる。

今の開発者アプリ（x-api-key / x-api-secret）を使い回し、PIN 方式の OAuth 1.0a で
そのアカウントに投稿の許可をもらう。トークンは画面にもファイルにも出さない。

  python tools/x_post/issue_x_token.py --project thai-memo-prod --lang en --expect daily_thai11
  python tools/x_post/issue_x_token.py --project thai-memo-prod --lang en --expect daily_thai11 --pin <PIN>

1. 1回目でブラウザに許可の画面が開く。投稿させたいアカウント（--expect）でログインした状態で「許可」を押す
2. 表示された PIN を --pin に付けてもう一度実行する（入力待ちにしないのは、Claude Code の ! から動かすため）
3. 許可したアカウントが --expect と一致したときだけ、x-access-token-<lang> と
   x-access-token-secret-<lang> に新しい版を足す

1回目の request token は一時フォルダに本人だけ読める形で置き、2回目で消す。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import webbrowser
from pathlib import Path

from google.cloud import secretmanager
from requests_oauthlib import OAuth1Session

REQUEST_TOKEN_URL = "https://api.x.com/oauth/request_token"
AUTHORIZE_URL = "https://api.x.com/oauth/authorize"
ACCESS_TOKEN_URL = "https://api.x.com/oauth/access_token"


def read_secret(client, project: str, name: str) -> str:
    path = f"projects/{project}/secrets/{name}/versions/latest"
    return client.access_secret_version(request={"name": path}).payload.data.decode()


def add_version(client, project: str, name: str, value: str) -> None:
    client.add_secret_version(
        request={
            "parent": f"projects/{project}/secrets/{name}",
            "payload": {"data": value.encode()},
        }
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--lang", required=True, help="シークレット名の接尾辞（en など）")
    parser.add_argument("--expect", required=True, help="許可するアカウントのユーザー名（@なし）")
    parser.add_argument("--pin", default="", help="許可の画面に出た PIN（2回目）")
    args = parser.parse_args()
    expect = args.expect.lstrip("@").lower()
    state = Path(tempfile.gettempdir()) / f"x_request_token_{args.lang}.json"

    client = secretmanager.SecretManagerServiceClient()
    key = read_secret(client, args.project, "x-api-key")
    secret = read_secret(client, args.project, "x-api-secret")

    if not args.pin:
        session = OAuth1Session(key, client_secret=secret, callback_uri="oob")
        request = session.fetch_request_token(REQUEST_TOKEN_URL)
        state.touch(mode=0o600)
        state.write_text(json.dumps(request))
        url = session.authorization_url(AUTHORIZE_URL)
        print(f"@{expect} でログインした状態で許可し、出た PIN を --pin に付けてもう一度実行:\n{url}")
        webbrowser.open(url)
        return 0

    if not state.exists():
        print("先に --pin なしで実行して許可の画面を開く", file=sys.stderr)
        return 1
    request = json.loads(state.read_text())
    session = OAuth1Session(
        key,
        client_secret=secret,
        resource_owner_key=request["oauth_token"],
        resource_owner_secret=request["oauth_token_secret"],
        verifier=args.pin.strip(),
    )
    try:
        tokens = session.fetch_access_token(ACCESS_TOKEN_URL)
    finally:
        os.remove(state)
    screen_name = str(tokens.get("screen_name", ""))
    if screen_name.lower() != expect:
        print(
            f"許可したのは @{screen_name}（@{expect} ではない）。保存しない。",
            file=sys.stderr,
        )
        return 1

    add_version(client, args.project, f"x-access-token-{args.lang}", tokens["oauth_token"])
    add_version(
        client,
        args.project,
        f"x-access-token-secret-{args.lang}",
        tokens["oauth_token_secret"],
    )
    print(f"@{screen_name} のトークンを x-access-token-{args.lang} / x-access-token-secret-{args.lang} に入れた")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
