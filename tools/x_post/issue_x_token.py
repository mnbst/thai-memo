"""別の X アカウント用の Access Token を発行し、Secret Manager に直接入れる。

今の開発者アプリ（x-api-key / x-api-secret）を使い回し、PIN 方式の OAuth 1.0a で
そのアカウントに投稿の許可をもらう。トークンは画面にもファイルにも出さない。

  python tools/x_post/issue_x_token.py --project thai-memo-prod --lang en --expect daily_thai11

1. ブラウザで許可の画面が開く。投稿させたいアカウント（--expect）でログインした状態で「許可」を押す
2. 表示された PIN を入力する
3. 許可したアカウントが --expect と一致したときだけ、x-access-token-<lang> と
   x-access-token-secret-<lang> に新しい版を足す
"""

from __future__ import annotations

import argparse
import sys
import webbrowser

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
    args = parser.parse_args()
    expect = args.expect.lstrip("@").lower()

    client = secretmanager.SecretManagerServiceClient()
    key = read_secret(client, args.project, "x-api-key")
    secret = read_secret(client, args.project, "x-api-secret")

    session = OAuth1Session(key, client_secret=secret, callback_uri="oob")
    session.fetch_request_token(REQUEST_TOKEN_URL)
    url = session.authorization_url(AUTHORIZE_URL)
    print(f"@{expect} でログインした状態で許可してください:\n{url}")
    webbrowser.open(url)

    pin = input("PIN: ").strip()
    tokens = session.fetch_access_token(ACCESS_TOKEN_URL, verifier=pin)
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
