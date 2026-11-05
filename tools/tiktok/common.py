"""TikTok 用の縦動画（1080x1920）を組むための共通部品（試作）。"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import unicodedata
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
W, H = 1080, 1920
FPS = 30
# TikTok の UI（上の切り替え・右のボタン・下の説明文）を避けた範囲。
SAFE_W = W - 220
SAFE_TOP = 220
CENTER_Y = 860

PAPER = (246, 242, 234)
INDIGO = (22, 36, 63)
GOLD = (195, 154, 78)
MUTED = (110, 116, 130)

# 動画の言語（日本語・韓国語・英語）。環境変数 TIKTOK_LANG で切り替える。
LANG = os.environ.get("TIKTOK_LANG", "ja")
TIKTOK_DIR = Path(__file__).resolve().parent

_KR_FONTS = ROOT / "tools/store_screenshots/fonts"
if LANG == "ko":
    JP_BOLD = str(_KR_FONTS / "NotoSansKR-Bold.otf")
    JP_REG = str(_KR_FONTS / "NotoSansKR-Regular.otf")
else:
    JP_BOLD = "/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc"
    JP_REG = "/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc"
THAI = str(ROOT / "google_fonts/Sarabun-Bold.ttf")
IPA = str(ROOT / "google_fonts/NotoSans-Medium.ttf")
EMOJI = "/System/Library/Fonts/Apple Color Emoji.ttc"

# 訳・説明の読み上げ（名前は昔のまま JA_VOICE）。
VOICE_LANG, JA_VOICE = {
    "ja": ("ja-JP", "ja-JP-Chirp3-HD-Aoede"),
    "ko": ("ko-KR", "ko-KR-Chirp3-HD-Aoede"),
    "en": ("en-US", "en-US-Chirp3-HD-Aoede"),
}[LANG]
# 単語1つだと Chirp3 は声調が崩れる（ซวย で確認）。Neural2 は正しく読む。
TH_WORD_VOICE = "th-TH-Neural2-C"

# 締めのスクショ。日本語は X の機能紹介と同じ画像、ほかはストア用の各言語版。
FEATURE_IMAGES = ROOT / "tools/x_post/feature_images" if LANG == "ja" else TIKTOK_DIR / "shots" / LANG

# 画面に出す決まり文句。
STR = {
    "ja": {"app": "まいにちタイ語", "link": "プロフィールのリンクからどうぞ", "today": "今日の例文", "tips": "タイ語のコツ"},
    "ko": {"app": "매일 태국어", "link": "프로필 링크에서 확인해요", "today": "오늘의 예문", "tips": "태국어 학습 팁"},
    "en": {"app": "Daily Thai", "link": "Tap the link in our bio", "today": "Today's Example", "tips": "Thai Learning Tips"},
}[LANG]

# 締めに出す機能（台本の end）。Tips の中身に合う機能を選ぶ。
_END_CAPTIONS = {
    "ja": ["語彙に合う例文が毎日届きます", "声調をアプリで採点します", "例文を1語ずつ分解します",
           "クイズで復習できます", "旅行・暮らしのテーマで学べます"],
    "ko": ["어휘에 맞는 예문이 매일 와요", "성조를 채점해요", "예문을 한 단어씩 나눠 봐요",
           "퀴즈로 복습해요", "여행·생활 같은 주제로 배워요"],
    "en": ["Daily examples matched to your vocab", "Get your tones scored", "Break examples down word by word",
           "Review with quizzes", "Learn by topic: travel, daily life"],
}[LANG]
END_FEATURES = {k: (f"0{i}.png", _END_CAPTIONS[i - 1])
                for i, k in enumerate(["daily", "pron", "breakdown", "quiz", "topics"], 1)}


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def is_emoji(ch: str) -> bool:
    return (ord(ch) >= 0x2190 and unicodedata.category(ch) in ("So", "Sk")) or ch in "\ufe0f\u200d"


def plain(text: str) -> str:
    return "".join(c for c in text if not is_emoji(c)).strip()


def _runs(text: str):
    out: list[tuple[bool, str]] = []
    for ch in text:
        e = is_emoji(ch)
        if out and out[-1][0] == e:
            out[-1] = (e, out[-1][1] + ch)
        else:
            out.append((e, ch))
    return out


JOINERS = "\ufe0f\u200d"


def _thai_split(s: str, f):
    """日本語フォントにタイ文字は無いので、タイ文字の部分だけタイ語フォントに替える。"""
    parts: list[list] = []
    for ch in s:
        is_th = "\u0e00" <= ch <= "\u0e7f"
        if parts and parts[-1][2] == is_th:
            parts[-1][0] += ch
        else:
            parts.append([ch, font(THAI, f.size) if is_th and f.path != THAI else f, is_th])
    return [(t, ff) for t, ff, _ in parts]


def _width(draw, text, f):
    w = 0
    for e, s in _runs(text):
        if e:
            w += f.size * len([c for c in s if c not in JOINERS])
        else:
            w += sum(draw.textlength(t, font=ff) for t, ff in _thai_split(s, f))
    return w


def draw_line(img, y, text, f, fill):
    """中央寄せで1行描く。絵文字は Apple Color Emoji、タイ文字はタイ語フォントで描く。"""
    draw = ImageDraw.Draw(img)
    x = (W - _width(draw, text, f)) / 2
    for e, s in _runs(text):
        if not e:
            for t, ff in _thai_split(s, f):
                draw.text((x, y), t, font=ff, fill=fill)
                x += draw.textlength(t, font=ff)
            continue
        for ch in s:
            if ch in JOINERS:
                continue
            tile = Image.new("RGBA", (180, 180), (0, 0, 0, 0))
            ImageDraw.Draw(tile).text((0, 0), ch, font=font(EMOJI, 160), embedded_color=True)
            tile = tile.crop(tile.getbbox() or (0, 0, 160, 160)).resize((f.size, f.size))
            img.paste(tile, (int(x), int(y + f.size * 0.1)), tile)
            x += f.size


NO_LINE_START = "、。，．）」』！？ー…っゃゅょァィゥェォッャュョ"


def _greedy(draw, tokens, sep, f, max_w):
    lines: list[str] = []
    cur = ""
    for t in tokens:
        cand = (cur + sep + t) if cur else t
        # 句読点などは行頭に置かず、前の行にぶら下げる。
        if _width(draw, cand, f) <= max_w or (not sep and t in NO_LINE_START):
            cur = cand
        else:
            if cur:
                lines.append(cur)
            cur = t
    if cur:
        lines.append(cur)
    return lines


def wrap(draw, text, f, max_w):
    """幅に収まるように折り返す。日本語は1文字単位、それ以外は空白で。
    日本語は行の長さをそろえる（「〜打ち明け／る」のように1、2字だけ落ちるのを避ける）。"""
    japanese = any("぀" <= c <= "鿿" for c in text)
    tokens, sep = (list(text), "") if japanese else (text.split(" "), " ")
    lines = _greedy(draw, tokens, sep, f, max_w)
    if japanese and len(lines) == 2:
        # 2行なら助詞・読点の後で切れる位置のうち、左右の長さが近いものを選ぶ。
        best = None
        for i in range(1, len(text)):
            if text[i - 1] not in "をにはがでのと、も" or text[i] in NO_LINE_START:
                continue
            left, right = text[:i], text[i:]
            wl, wr = _width(draw, left, f), _width(draw, right, f)
            if max(wl, wr) <= max_w and (best is None or abs(wl - wr) < best[0]):
                best = (abs(wl - wr), [left, right])
        if best:
            return best[1]
    if japanese and len(lines) > 1:
        target = _width(draw, text, f) / len(lines) + f.size
        balanced = _greedy(draw, tokens, sep, f, min(max_w, target))
        if len(balanced) == len(lines):
            return balanced
    return lines


def wrap_sentences(draw, text, f, max_w):
    """「。」で必ず改行し、それぞれを幅で折り返す。"""
    sents = [s + "。" for s in text.rstrip("。").split("。")] if "。" in text else [text]
    return [l for s in sents for l in wrap(draw, s, f, max_w)]


def fit(draw, text, path, start, minimum, max_w, max_lines=1, sentences=False):
    """max_lines 行以内・各行が幅に収まる最大の大きさを探す。"""
    split = wrap_sentences if sentences else wrap
    for size in range(start, minimum - 1, -4):
        f = font(path, size)
        lines = split(draw, text, f, max_w)
        # 日本語の2行が助詞の後で切れないなら、もう少し小さくして切れ目を探す。
        awkward = (len(lines) == 2 and any("぀" <= ch <= "鿿" for ch in text)
                   and lines[0][-1] not in "をにはがでのと、も。")
        if awkward and size - 4 >= minimum:
            continue
        if len(lines) <= max_lines and all(_width(draw, l, f) <= max_w for l in lines):
            return f, lines
    f = font(path, minimum)
    return f, split(draw, text, f, max_w)


def base(label: str | None = None) -> Image.Image:
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W, 14), fill=INDIGO)
    if label:
        f = font(JP_BOLD, 40)
        tw = d.textlength(label, font=f)
        d.rounded_rectangle(((W - tw) / 2 - 32, SAFE_TOP, (W + tw) / 2 + 32, SAFE_TOP + 80), 40, fill=INDIGO)
        d.text(((W - tw) / 2, SAFE_TOP + 16), label, font=f, fill=PAPER)
    return img


def card_hook(hook: str, label: str) -> Image.Image:
    img = base(label)
    d = ImageDraw.Draw(img)
    f, lines = fit(d, hook, JP_BOLD, 96, 64, SAFE_W)
    if len(lines) > 1:
        f, lines = fit(d, hook, JP_BOLD, 96, 64, SAFE_W, max_lines=2)
    lh = f.size * 1.35
    y = CENTER_Y - len(lines) * lh / 2
    for line in lines:
        draw_line(img, y, line, f, INDIGO)
        y += lh
    d.rectangle((W / 2 - 80, y + 40, W / 2 + 80, y + 50), fill=GOLD)
    return img


def card_text(label: str, text: str) -> Image.Image:
    img = base(label)
    d = ImageDraw.Draw(img)
    if "\n" in text:
        # 台本で改行を指定した行はそのまま使い、全部が幅に収まる大きさにする。
        lines = text.split("\n")
        for size in range(84, 51, -4):
            f = font(JP_BOLD, size)
            if all(_width(d, l, f) <= SAFE_W for l in lines):
                break
    else:
        f, lines = fit(d, text, JP_BOLD, 76, 52, SAFE_W, max_lines=4, sentences=True)
    lh = f.size * 1.5
    y = CENTER_Y - len(lines) * lh / 2
    for line in lines:
        draw_line(img, y, line, f, INDIGO)
        y += lh
    return img


def card_end(shot: Path | None, caption: str | None) -> Image.Image:
    img = base()
    d = ImageDraw.Draw(img)
    if shot is None:
        draw_line(img, CENTER_Y - 120, STR["app"], font(JP_BOLD, 110), INDIGO)
        d.rectangle((W / 2 - 80, CENTER_Y + 40, W / 2 + 80, CENTER_Y + 50), fill=GOLD)
        draw_line(img, CENTER_Y + 100, STR["link"], font(JP_REG, 54), MUTED)
        return img
    s = Image.open(shot).convert("RGB")
    s.thumbnail((W - 300, 1000))
    img.paste(s, ((W - s.width) // 2, SAFE_TOP - 60))
    y = SAFE_TOP - 60 + s.height + 50
    if caption:
        draw_line(img, y, caption, font(JP_BOLD, 56), INDIGO)
        y += 100
    draw_line(img, y, STR["app"], font(JP_BOLD, 96), INDIGO)
    draw_line(img, y + 140, STR["link"], font(JP_REG, 48), MUTED)
    return img


def run(cmd: list[str]) -> None:
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        print(r.stderr[-3000:], file=sys.stderr)
        raise SystemExit(1)


def duration(path: Path) -> float:
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True,
    )
    return float(r.stdout.strip())


def synth(text: str, out: Path, lang: str | None = None, voice: str | None = None) -> Path:
    """Cloud TTS で読み上げを作る。この Python は証明書の束を持たないので curl に任せる。"""
    lang, voice = lang or VOICE_LANG, voice or JA_VOICE
    token = subprocess.run(["gcloud", "auth", "print-access-token"], capture_output=True, text=True).stdout.strip()
    body = json.dumps({"input": {"text": text}, "voice": {"languageCode": lang, "name": voice},
                       "audioConfig": {"audioEncoding": "MP3"}}).encode()
    r = subprocess.run(
        ["curl", "-s", "-X", "POST", "https://texttospeech.googleapis.com/v1/text:synthesize",
         "-H", f"Authorization: Bearer {token}", "-H", "x-goog-user-project: thai-memo-prod",
         "-H", "Content-Type: application/json", "--data-binary", "@-"],
        input=body, capture_output=True)
    out.write_bytes(base64.b64decode(json.loads(r.stdout)["audioContent"]))
    return out


def join_audio(parts: list[Path], out: Path, gap: float = 0.35) -> Path:
    """読み上げを間を空けてつなぐ。"""
    inputs, chain = [], ""
    for i, part in enumerate(parts):
        inputs += ["-i", str(part)]
        chain += f"[{i}:a]aresample=44100,aformat=channel_layouts=stereo,apad=pad_dur={gap}[a{i}];"
    chain += "".join(f"[a{i}]" for i in range(len(parts))) + f"concat=n={len(parts)}:v=0:a=1[o]"
    run(["ffmpeg", "-y", *inputs, "-filter_complex", chain, "-map", "[o]", str(out)])
    return out


ENC = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", str(FPS),
       "-c:a", "aac", "-ar", "44100", "-ac", "2", "-b:a", "160k"]


def still(png: Path, seconds: float, out: Path, audio: Path | None = None, fade_in=True) -> Path:
    vf = f"scale={W}:{H},format=yuv420p" + (",fade=t=in:st=0:d=0.25" if fade_in else "")
    cmd = ["ffmpeg", "-y", "-loop", "1", "-framerate", str(FPS), "-t", f"{seconds:.3f}", "-i", str(png)]
    if audio:
        cmd += ["-i", str(audio), "-filter_complex",
                f"[0:v]{vf}[v];[1:a]aresample=44100,aformat=channel_layouts=stereo,apad,atrim=0:{seconds:.3f}[a]",
                "-map", "[v]", "-map", "[a]"]
    else:
        cmd += ["-f", "lavfi", "-t", f"{seconds:.3f}", "-i", "anullsrc=r=44100:cl=stereo",
                "-vf", vf, "-map", "0:v", "-map", "1:a"]
    run(cmd + ["-t", f"{seconds:.3f}"] + ENC + [str(out)])
    return out


def concat(segs: list[Path], out: Path) -> Path:
    lst = out.with_suffix(".txt")
    lst.write_text("".join(f"file '{s.resolve()}'\n" for s in segs))
    run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", "-movflags", "+faststart", str(out)])
    print(out, f"{duration(out):.1f}s")
    return out


def data_file(name: str) -> Path:
    """台本ファイル。日本語は <name>.json、ほかは <name>_<lang>.json。"""
    return TIKTOK_DIR / (f"{name}.json" if LANG == "ja" else f"{name}_{LANG}.json")


def load_script(post_id: str) -> dict:
    """動画の台本（scripts.json、Codex が書いたもの）。"""
    scripts = json.loads(data_file("scripts").read_text())
    return next(x for x in scripts if x["id"] == post_id)


def load_post(post_id: str) -> dict:
    posts = json.loads((ROOT / "tools/x_post/study_posts.json").read_text())
    return next(x for x in posts if x["id"] == post_id)
