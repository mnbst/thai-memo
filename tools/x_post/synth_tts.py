"""例文のタイ語読み上げ音声を作る。

アプリ内の読み上げは端末TTS（flutter_tts）なのでCIでは使えない。投稿用は
Google Cloud Text-to-Speech の th-TH を使う。1日1文なら無料枠に収まる。

通常速度 → 間 → ゆっくり、の順で1本にまとめる。聞き取り練習として成立させる
ため。出力は <out>/audio.mp3。
"""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path

from google.cloud import texttospeech

VOICE_NAME = "th-TH-Neural2-C"
SLOW_RATE = 0.7
GAP = "900ms"


def build_ssml(thai_text: str) -> str:
    escaped = html.escape(thai_text)
    return (
        "<speak>"
        f"{escaped}"
        f'<break time="{GAP}"/>'
        f'<prosody rate="{SLOW_RATE}">{escaped}</prosody>'
        f'<break time="600ms"/>'
        "</speak>"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sentence", default="build/x_post/sentence.json")
    parser.add_argument("--out", default="build/x_post")
    args = parser.parse_args()

    sentence = json.loads(Path(args.sentence).read_text(encoding="utf-8"))

    client = texttospeech.TextToSpeechClient()
    response = client.synthesize_speech(
        input=texttospeech.SynthesisInput(ssml=build_ssml(sentence["thai_text"])),
        voice=texttospeech.VoiceSelectionParams(
            language_code="th-TH", name=VOICE_NAME
        ),
        audio_config=texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.MP3
        ),
    )

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "audio.mp3").write_bytes(response.audio_content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
