#!/usr/bin/env python3
"""Generate crisp 2048x2732 opaque RGB iPad Pro 13-inch (APP_IPAD_PRO_3GEN_129)
screenshots for WaitCam (en-US & zh-Hans) reusing existing phone mockup frames.
"""

from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

APPSTORE_DIR = Path("/Users/wang/OPC/media/20261118-waitcam/appstore")
IPAD_DIR = APPSTORE_DIR / "ipad"
FONT_PATH = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def load_font(size: int, index: int = 0) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(FONT_PATH, size, index=index)
    except Exception:
        return ImageFont.truetype(FONT_PATH, size)


def fit_font(draw: ImageDraw.ImageDraw, text: str, max_width: int, start_size: int, index: int = 0) -> ImageFont.FreeTypeFont:
    size = start_size
    while size > 28:
        font = load_font(size, index=index)
        box = draw.textbbox((0, 0), text, font=font)
        if (box[2] - box[0]) <= max_width:
            return font
        size -= 4
    return load_font(28, index=index)


def extract_phone_frame(board_path: Path) -> Image.Image:
    im = Image.open(board_path).convert("RGB")
    # Verified bezel bbox across iphone65_01..05: (112, 640, 1172, 2580)
    return im.crop((104, 632, 1180, 2588))


def make_darkroom_bg(w: int, h: int, accent: tuple[int, int, int]) -> Image.Image:
    base = Image.new("RGB", (w, h), (7, 7, 11))
    draw = ImageDraw.Draw(base, "RGBA")
    # Subtle warm darkroom halo behind dual showcase card
    ar, ag, ab = accent
    for step in range(8, 0, -1):
        alpha = int(14 * (9 - step) / 8)
        pad = step * 80
        draw.ellipse(
            (w // 2 - 700 - pad // 2, 420 - pad // 3, w // 2 + 700 + pad // 2, 2200 + pad // 2),
            fill=(ar, ag, ab, min(alpha, 18)),
        )
    return base


def round_corners(im: Image.Image, radius: int) -> Image.Image:
    rgba = im.convert("RGBA")
    mask = Image.new("L", rgba.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, rgba.width, rgba.height), radius=radius, fill=255)
    rgba.putalpha(mask)
    return rgba


def render_ipad_board(
    left_path: Path,
    right_path: Path,
    badge: str,
    headline: str,
    sub: str,
    accent: tuple[int, int, int],
    out_path: Path,
) -> None:
    W, H = 2048, 2732
    bg = make_darkroom_bg(W, H, accent).convert("RGBA")
    draw = ImageDraw.Draw(bg)

    f_badge = fit_font(draw, badge, 1400, 44, index=1)
    f_h1 = fit_font(draw, headline, 1820, 88, index=1)
    f_sub = fit_font(draw, sub, 1800, 44, index=0)

    bbox = draw.textbbox((0, 0), badge, font=f_badge)
    bw = (bbox[2] - bbox[0]) + 92
    bx = (W - bw) // 2
    ar, ag, ab = accent
    draw.rounded_rectangle(
        (bx, 118, bx + bw, 206),
        radius=44,
        fill=(24, 22, 30, 255),
        outline=(ar, ag, ab, 235),
        width=4,
    )
    draw.text((W // 2, 162), badge, font=f_badge, fill=(ar, ag, ab), anchor="mm")

    draw.text((W // 2, 318), headline, font=f_h1, fill=(255, 255, 255), anchor="mm")
    draw.text((W // 2, 430), sub, font=f_sub, fill=(192, 198, 212), anchor="mm")

    # Outer darkroom container card
    card_w, card_h = 1820, 2040
    cx0, cy0 = (W - card_w) // 2, 548
    draw.rounded_rectangle(
        (cx0, cy0, cx0 + card_w, cy0 + card_h),
        radius=74,
        fill=(14, 15, 22, 255),
        outline=(ar, ag, ab, 115),
        width=5,
    )

    ui_left = extract_phone_frame(left_path)
    ui_right = extract_phone_frame(right_path)

    pane_w = 810
    pane_h = int(ui_left.height * (pane_w / ui_left.width))
    max_pane_h = card_h - 140
    if pane_h > max_pane_h:
        pane_h = max_pane_h
        pane_w = int(ui_left.width * (pane_h / ui_left.height))

    l_res = round_corners(ui_left.resize((pane_w, pane_h), Image.Resampling.LANCZOS), 58)
    r_res = round_corners(ui_right.resize((pane_w, pane_h), Image.Resampling.LANCZOS), 58)

    gap = 72
    total_w = pane_w * 2 + gap
    lx = (W - total_w) // 2
    rx = lx + pane_w + gap
    py = cy0 + (card_h - pane_h) // 2

    bg.alpha_composite(l_res, (lx, py))
    bg.alpha_composite(r_res, (rx, py))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    bg.convert("RGB").save(out_path, format="PNG")


def main() -> None:
    en = APPSTORE_DIR / "en-US"
    zh = APPSTORE_DIR / "zh-Hans"

    # en-US 3 dual showcase iPad boards
    render_ipad_board(
        en / "iphone65_01.png",
        en / "iphone65_02.png",
        "WAITCAM 35MM · ZERO WATERMARKS",
        "Shoot Tonight, Reveal in 12 Hours",
        "No peeking darkroom lock with 2AM Xenon Flash & 4 signature cinema LUTs",
        (255, 122, 47),
        IPAD_DIR / "en-US" / "ipad13_01.png",
    )
    render_ipad_board(
        en / "iphone65_03.png",
        en / "iphone65_04.png",
        "LIVE DARKROOM · 1-TAP 35MM REELS",
        "Lock Screen Timer & Sprocket-Hole MP4s",
        "Follow roll development live and export crisp 35mm Reels or contact sheets offline",
        (56, 189, 248),
        IPAD_DIR / "en-US" / "ipad13_02.png",
    )
    render_ipad_board(
        en / "iphone65_05.png",
        en / "iphone65_01.png",
        "100% OFFLINE · TRANSPARENT TRIAL",
        "Try 3 Days Free with Day-2 Reminder",
        "Local encrypted AES-256 vault, Family Sharing, or One-Time Lifetime unlock",
        (168, 85, 247),
        IPAD_DIR / "en-US" / "ipad13_03.png",
    )

    # zh-Hans 3 dual showcase iPad boards
    render_ipad_board(
        zh / "iphone65_01.png",
        zh / "iphone65_02.png",
        "WAITCAM 35MM · 基础永久无水印",
        "今晚按下快门 · 12 小时后次日开封",
        "不可偷看的真实暗房锁 · 内置 2AM 氙气派对闪光与 4 款胶片影调",
        (255, 122, 47),
        IPAD_DIR / "zh-Hans" / "ipad13_01.png",
    )
    render_ipad_board(
        zh / "iphone65_03.png",
        zh / "iphone65_04.png",
        "锁屏实时倒计时 · 一键 35mm 晒片短片",
        "实时暗房显影 · 带齿孔 MP4 与接触印相单",
        "显影完成后一键导出 35mm 竖屏短片或整卷印相单，直发朋友圈与小红书",
        (56, 189, 248),
        IPAD_DIR / "zh-Hans" / "ipad13_02.png",
    )
    render_ipad_board(
        zh / "iphone65_05.png",
        zh / "iphone65_01.png",
        "100% 纯本地离线 · 第 2 天到期贴心提醒",
        "3 天 ¥0 免费试用 · 也支持黑五终身买断",
        "AES-256 本地暗房加密保存 · 到期前 1 天推送本地通知提醒，绝不偷扣费",
        (168, 85, 247),
        IPAD_DIR / "zh-Hans" / "ipad13_03.png",
    )
    print(f"Generated 6 iPad 13-inch screenshots in {IPAD_DIR}")


if __name__ == "__main__":
    main()
