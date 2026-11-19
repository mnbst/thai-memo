"""YouTube Shorts へ投稿するための鍵を作り、Secret Manager に入れる。

YouTube のチャンネルを持つアカウントで1回だけ許可し、リフレッシュトークンを CI に持たせる。
権限は動画の投稿（youtube.upload）と、再生回数の読み取り（youtube.readonly）だけ。

  uv run --with google-auth-oauthlib --with google-cloud-secret-manager --with requests \\
    python tools/x_post/issue_youtube_token.py --project thai-memo-prod

1. OAuth クライアントは、既定で Drive 用の secret `google-drive-upload` に入っている
   デスクトップ アプリのクライアント（client_id・client_secret）を使い回す。
   別のクライアントを使うときは --client-secret に JSON を渡す（作成済みのクライアントの
   シークレットは後から落とせないので、作った時の画面で落とす）。
2. OAuth 同意画面を「本番」にしておく。「テスト」のままだとリフレッシュトークンが7日で切れる。
3. 上のコマンドを実行するとブラウザが開く。投稿するチャンネルのアカウント（ブランド
   アカウントならそのチャンネル）を選んで「許可」を押す。
4. client_id・client_secret・refresh_token を1つの JSON にして secret `youtube-upload`
   に新しい版として足す。トークンは画面にもファイルにも出さない。
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import requests
from google.cloud import secretmanager
from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = [
    "https://www.googleapis.com/auth/youtube.upload",
    "https://www.googleapis.com/auth/youtube.readonly",
]
SECRET = "youtube-upload"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--client-secret", type=Path,
                        help="OAuth クライアントの JSON。無ければ google-drive-upload のものを使う")
    args = parser.parse_args()

    client = secretmanager.SecretManagerServiceClient()
    if args.client_secret:
        flow = InstalledAppFlow.from_client_secrets_file(
            str(args.client_secret.expanduser()), SCOPES
        )
    else:
        drive = json.loads(
            client.access_secret_version(
                name=f"projects/{args.project}/secrets/google-drive-upload/versions/latest"
            ).payload.data
        )
        flow = InstalledAppFlow.from_client_config(
            {
                "installed": {
                    "client_id": drive["client_id"],
                    "client_secret": drive["client_secret"],
                    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                    "token_uri": "https://oauth2.googleapis.com/token",
                    "redirect_uris": ["http://localhost"],
                }
            },
            SCOPES,
        )
    creds = flow.run_local_server(port=0, prompt="consent", access_type="offline")
    if not creds.refresh_token:
        print("リフレッシュトークンが返らなかった。許可を取り消してからやり直す")
        return 1

    # 違うチャンネルで許可していないか、名前を出して確かめる。
    response = requests.get(
        "https://www.googleapis.com/youtube/v3/channels",
        headers={"Authorization": f"Bearer {creds.token}"},
        params={"part": "snippet", "mine": "true"},
        timeout=30,
    )
    response.raise_for_status()
    items = response.json().get("items", [])
    if not items:
        print("このアカウントにはチャンネルが無い。YouTube でチャンネルを作ってからやり直す")
        return 1
    print(f"チャンネル: {items[0]['snippet']['title']}")

    payload = json.dumps(
        {
            "client_id": creds.client_id,
            "client_secret": creds.client_secret,
            "refresh_token": creds.refresh_token,
        }
    ).encode()
    client.add_secret_version(
        request={
            "parent": f"projects/{args.project}/secrets/{SECRET}",
            "payload": {"data": payload},
        }
    )
    print(f"{SECRET} に新しい版を足した")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
