"""note 記事の見出し画像（1280×670）を作る。

アプリの青を背景に、代表のタイ語を大きく、その下に記事タイトル、右下にアプリ名を置く。
トップ画面では左右が切れるので、文字は中央の幅 900px に収める。
フォントは macOS のヒラギノと google_fonts/ のタイ語フォントを使う（手元で回す前提）。

  python3 tools/note/make_header.py --thai "สวัสดี" --reading "サワッディー" \\
    --title "タイ旅行のひとこと10選|カタカナ読み付き" --out header.png

タイトルの「|」で改行する。無ければ幅に合わせて折り返す。
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
W, H = 1280, 670
SAFE_W = 900
BG = (1, 44, 224)  # アプリアイコンの青（#012CE0）
ACCENT = (240, 64, 64)
WHITE = (255, 255, 255)
SUB = (200, 212, 255)
JA_BOLD = "/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc"
JA_MID = "/System/Library/Fonts/ヒラギノ角ゴシック W5.ttc"
THAI = ROOT / "google_fonts" / "NotoSansThai-SemiBold.ttf"
ICON = ROOT / "assets" / "appicon.png"


def wrap(draw: ImageDraw.ImageDraw, text: str, font, width: int) -> list[str]:
    if "|" in text:
        return text.split("|")
    lines, line = [], ""
    for ch in text:
        if draw.textlength(line + ch, font=font) > width:
            lines.append(line)
            line = ch
        else:
            line += ch
    return lines + [line] if line else lines


def fit_font(draw, text: str, path, size: int, width: int):
    """幅に収まるまで文字を小さくする。"""
    while size > 24:
        font = ImageFont.truetype(str(path), size)
        if draw.textlength(text, font=font) <= width:
            return font
        size -= 4
    return ImageFont.truetype(str(path), size)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--thai", required=True)
    parser.add_argument("--reading", default="", help="タイ語のカタカナ読み")
    parser.add_argument("--title", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)

    # 代表のタイ語。下に赤い線を引いて目を引く。
    thai_font = fit_font(draw, args.thai, THAI, 150, SAFE_W)
    title_font = ImageFont.truetype(JA_BOLD, 54)
    title_lines = wrap(draw, args.title, title_font, SAFE_W)
    line_h = 74

    reading_font = ImageFont.truetype(JA_MID, 34)
    thai_box = draw.textbbox((0, 0), args.thai, font=thai_font)
    thai_h = thai_box[3] - thai_box[1]
    reading_h = 50 if args.reading else 0
    gap = 64
    block_h = thai_h + reading_h + gap + line_h * len(title_lines)
    top = (H - block_h) // 2 - 24

    draw.text(((W - (thai_box[2] - thai_box[0])) // 2 - thai_box[0], top - thai_box[1]),
              args.thai, font=thai_font, fill=WHITE)
    y = top + thai_h
    if args.reading:
        draw.text((W // 2, y + 18), args.reading, font=reading_font, fill=SUB, anchor="mt")
        y += reading_h
    bar_y = y + gap // 2
    draw.rounded_rectangle((W // 2 - 40, bar_y - 4, W // 2 + 40, bar_y + 4),
                           radius=4, fill=ACCENT)

    y += gap
    for line in title_lines:
        draw.text((W // 2, y), line, font=title_font, fill=WHITE, anchor="mt")
        y += line_h

    # 右下にアイコンとアプリ名（中央 900px の内側）。
    brand_font = ImageFont.truetype(JA_MID, 30)
    icon = Image.open(ICON).convert("RGBA").resize((48, 48))
    mask = Image.new("L", icon.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 47, 47), radius=11, fill=255)
    brand = "まいにちタイ語"
    text_w = draw.textlength(brand, font=brand_font)
    right = (W + SAFE_W) // 2
    x = int(right - text_w - 60)
    img.paste(icon, (x, H - 88), mask)
    draw.text((x + 60, H - 64), brand, font=brand_font, fill=SUB, anchor="lm")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    img.save(args.out, optimize=True)
    print(args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
