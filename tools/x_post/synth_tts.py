"""例文のタイ語読み上げ音声を作る。

アプリ内の読み上げは端末TTS（flutter_tts）なのでCIでは使えない。投稿用は
Google Cloud Text-to-Speech の th-TH を使う。1日1文なら無料枠に収まる。

読み上げは通常速度の1回だけ。動画では「お手本を聞く」を押す操作と重ねるので、
アプリで1回再生したのと同じ長さに揃える。出力は <out>/audio.mp3。

声はアプリのお手本と同じく例文の中身で決める（文末 → 一人称 → BL → ハッシュ）。
functions/go/internal/ttsaudio/voice.go の写し。あちらを変えたらこちらも合わせる。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import unicodedata
from pathlib import Path

from google.cloud import texttospeech

MALE_VOICES = ("th-TH-Chirp3-HD-Charon", "th-TH-Chirp3-HD-Puck", "th-TH-Chirp3-HD-Orus")
FEMALE_VOICES = ("th-TH-Chirp3-HD-Kore", "th-TH-Chirp3-HD-Aoede", "th-TH-Chirp3-HD-Leda")

# 文末の丁寧語（女性）。男性の ครับ・คับ は _ending_gender に直書き。
FEMALE_ENDS = ("ค่ะ", "คะ", "คร่ะ")
# 一人称。ผม（髪）・หนู（ネズミ）と紛れるので、単語分解で代名詞の語に限る。
MALE_PRONOUNS = ("ผม", "กระผม")
FEMALE_PRONOUNS = ("ดิฉัน", "หนู")

MALE, FEMALE = "male", "female"


def normalize(text: str) -> str:
    """絵文字を落とし、空白を1つにまとめる。"""
    chars = []
    for ch in text:
        if ch in "\u200d\ufe0f\ufe0e":
            continue
        if unicodedata.category(ch) in ("So", "Sk", "Cs"):
            continue
        chars.append(" " if ch.isspace() else ch)
    return " ".join("".join(chars).split())


def _is_thai(ch: str) -> bool:
    return "\u0e00" <= ch <= "\u0e7f"


def _has_thai(s: str) -> bool:
    return any(_is_thai(ch) for ch in s)


def _ending_gender(text: str, words: list[dict]) -> str | None:
    """単語分解があれば最後の語（記号は飛ばす）、無ければ文字列の末尾で見る。"""
    tail, is_word = text, False
    while tail and not _is_thai(tail[-1]):
        tail = tail[:-1]
    for w in reversed(words):
        word = (w.get("word") or "").strip()
        if _has_thai(word):
            tail, is_word = word, True
            break
    if tail.endswith(FEMALE_ENDS):
        return FEMALE
    if tail.endswith("ครับ") or (is_word and tail == "คับ"):
        return MALE
    return None


def _pronoun_gender(words: list[dict]) -> str | None:
    for w in words:
        role = (w.get("grammatical_role") or "").lower()
        if not ("代名詞" in role or "pronoun" in role or "私" in (w.get("meaning") or "")):
            continue
        word = (w.get("word") or "").strip()
        if word in MALE_PRONOUNS:
            return MALE
        if word in FEMALE_PRONOUNS:
            return FEMALE
    return None


def choose_voice(sentence: dict) -> str:
    text = normalize(sentence["thai_text"])
    words = [w or {} for w in sentence.get("word_breakdown") or []]
    topic = (sentence.get("context") or {}).get("topic") or ""
    digest = hashlib.sha256(text.encode("utf-8")).digest()
    gender = (
        _ending_gender(text, words)
        or _pronoun_gender(words)
        or (MALE if "BL" in topic else None)
        or (MALE if digest[0] % 2 == 0 else FEMALE)
    )
    voices = MALE_VOICES if gender == MALE else FEMALE_VOICES
    return voices[int.from_bytes(digest[1:5], "big") % len(voices)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sentence", default="build/x_post/sentence.json")
    parser.add_argument("--out", default="build/x_post")
    args = parser.parse_args()

    sentence = json.loads(Path(args.sentence).read_text(encoding="utf-8"))

    # Chirp3-HD は SSML を受けないので、アプリと同じく整えた文をそのまま渡す。
    client = texttospeech.TextToSpeechClient()
    response = client.synthesize_speech(
        input=texttospeech.SynthesisInput(text=normalize(sentence["thai_text"])),
        voice=texttospeech.VoiceSelectionParams(
            language_code="th-TH", name=choose_voice(sentence)
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
