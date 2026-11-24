"""例文のタイ語読み上げ音声を作る。

アプリ内の読み上げは端末TTS（flutter_tts）なのでCIでは使えない。投稿用は
Google Cloud Text-to-Speech の th-TH を使う。1日1文なら無料枠に収まる。

読み上げは通常速度の1回だけ。動画では「お手本を聞く」を押す操作と重ねるので、
アプリで1回再生したのと同じ長さに揃える。出力は <out>/audio.mp3。

声はアプリのお手本と同じく例文の中身で決める（文末 → 一人称 → BL → ฉัน → ハッシュ）。
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

# 文末の丁寧語（女性）。男性の ครับ・คับ は _polite_gender に直書き。
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
    """単語分解があれば後ろの語から丁寧語の語を探す（丁寧語の後ろに呼びかけ等が続く文のため）。
    無ければ文字列の末尾で見る。"""
    thai_words = [w for w in ((x.get("word") or "").strip() for x in words) if _has_thai(w)]
    if not thai_words:
        tail = text
        while tail and not _is_thai(tail[-1]):
            tail = tail[:-1]
        return _polite_gender(tail, False)
    for w in reversed(thai_words):
        if g := _polite_gender(w, True):
            return g
    return None


def _polite_gender(s: str, is_word: bool) -> str | None:
    """คับ は語そのもののときだけ。単語なら ครับผม のように ครับ で始まるものも数える。"""
    if s.endswith(FEMALE_ENDS):
        return FEMALE
    if s.endswith("ครับ") or (is_word and (s == "คับ" or s.startswith("ครับ"))):
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


def _chan_speaker(words: list[dict]) -> bool:
    """一人称 ฉัน（ของฉัน も）があるか。ฉัน は男女とも使うので BL より後に見る。"""
    for w in words:
        role = (w.get("grammatical_role") or "").lower()
        if not ("代名詞" in role or "pronoun" in role or "私" in (w.get("meaning") or "")):
            continue
        word = (w.get("word") or "").strip()
        if word.removeprefix("ของ") == "ฉัน":
            return True
    return False


def choose_voice(sentence: dict) -> str:
    text = normalize(sentence["thai_text"])
    words = [w or {} for w in sentence.get("word_breakdown") or []]
    topic = (sentence.get("context") or {}).get("topic") or ""
    digest = hashlib.sha256(text.encode("utf-8")).digest()
    gender = (
        _ending_gender(text, words)
        or _pronoun_gender(words)
        or (MALE if "BL" in topic else None)
        or (FEMALE if _chan_speaker(words) else None)
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
