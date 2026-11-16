"""Google Drive へ投稿素材を置くための鍵を作り、Secret Manager に入れる。

個人の Gmail ではサービスアカウントが Drive にファイルを持てないので、本人の
アカウントで1回だけ許可し、リフレッシュトークンを CI に持たせる。権限は
drive.file（このツールが作ったファイル・フォルダだけ触れる）に絞る。

  uv run --with google-auth-oauthlib --with google-cloud-secret-manager \\
    python tools/x_post/issue_drive_token.py --project thai-memo-prod \\
    --client-secret ~/Downloads/client_secret_xxx.json

1. GCP コンソール（--project）の「API とサービス → 認証情報」で
   OAuth クライアント ID（種類: デスクトップ アプリ）を作り、JSON をダウンロードする。
   Google Drive API を有効にしておく。
2. 上のコマンドを実行するとブラウザが開く。素材を置きたいアカウントで「許可」を押す。
3. Drive に「--folder」のフォルダを作り、client_id・client_secret・refresh_token・
   folder_id を1つの JSON にして secret `google-drive-upload` に新しい版として足す。
   トークンは画面にもファイルにも出さない。
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import requests
from google.cloud import secretmanager
from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = ["https://www.googleapis.com/auth/drive.file"]
SECRET = "google-drive-upload"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--client-secret", required=True, type=Path)
    parser.add_argument("--folder", default="まいにちタイ語 SNS素材")
    args = parser.parse_args()

    flow = InstalledAppFlow.from_client_secrets_file(
        str(args.client_secret.expanduser()), SCOPES
    )
    creds = flow.run_local_server(port=0, prompt="consent", access_type="offline")
    if not creds.refresh_token:
        print("リフレッシュトークンが返らなかった。許可を取り消してからやり直す")
        return 1

    # drive.file では自分で作ったフォルダにしか置けないので、ここで作る。
    response = requests.post(
        "https://www.googleapis.com/drive/v3/files",
        headers={"Authorization": f"Bearer {creds.token}"},
        json={"name": args.folder, "mimeType": "application/vnd.google-apps.folder"},
        timeout=30,
    )
    response.raise_for_status()
    folder_id = response.json()["id"]

    payload = json.dumps(
        {
            "client_id": creds.client_id,
            "client_secret": creds.client_secret,
            "refresh_token": creds.refresh_token,
            "folder_id": folder_id,
        }
    ).encode()
    client = secretmanager.SecretManagerServiceClient()
    client.add_secret_version(
        request={
            "parent": f"projects/{args.project}/secrets/{SECRET}",
            "payload": {"data": payload},
        }
    )
    print(f"フォルダ「{args.folder}」を作り、{SECRET} に新しい版を足した")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
