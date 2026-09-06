"""例文のタイ語読み上げ音声を作る。

アプリ内の読み上げは端末TTS（flutter_tts）なのでCIでは使えない。投稿用は
Google Cloud Text-to-Speech の th-TH を使う。1日1文なら無料枠に収まる。

読み上げは通常速度の1回だけ。動画では「お手本を聞く」を押す操作と重ねるので、
アプリで1回再生したのと同じ長さに揃える。出力は <out>/audio.mp3。
"""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path

from google.cloud import texttospeech

VOICE_NAME = "th-TH-Neural2-C"


def build_ssml(thai_text: str) -> str:
    escaped = html.escape(thai_text)
    return f"<speak>{escaped}</speak>"


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
