#!/usr/bin/env python3
"""Generate crisp 24-bit RGB (no alpha) WaitCam iOS AppIcon asset."""

from __future__ import annotations

import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ASSETS_DIR = Path(__file__).resolve().parent.parent / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
ASSETS_DIR.mkdir(parents=True, exist_ok=True)


def render_master_icon(size: int = 1024) -> Image.Image:
    # Darkroom obsidian background with warm amber + tungsten party glow
    bg = Image.new("RGBA", (size, size), (10, 10, 14, 255))
    px = bg.load()
    for y in range(size):
        ty = y / (size - 1)
        for x in range(size):
            tx = x / (size - 1)
            d_flash = math.hypot(tx - 0.24, ty - 0.22)
            d_core = math.hypot(tx - 0.60, ty - 0.68)
            glow_amber = max(0.0, 1.0 - d_flash * 1.25) ** 2.1
            glow_crimson = max(0.0, 1.0 - d_core * 1.15) ** 1.9
            r = int(min(255, 11 + 140 * glow_amber + 64 * glow_crimson))
            g = int(min(255, 11 + 66 * glow_amber + 18 * glow_crimson))
            b = int(min(255, 16 + 22 * glow_amber + 34 * glow_crimson))
            px[x, y] = (r, g, b, 255)

    # Outer drop shadow behind disposable film body
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([136, 232, 888, 822], radius=108, fill=(0, 0, 0, 195))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=34))
    bg = Image.alpha_composite(bg, shadow)

    body = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)

    # Top winding wheel & shutter button
    bd.rounded_rectangle([674, 178, 796, 236], radius=24, fill=(255, 107, 44, 255))
    bd.rounded_rectangle([210, 192, 316, 236], radius=18, fill=(44, 46, 56, 255))

    # Disposable camera matte charcoal body
    bd.rounded_rectangle([136, 214, 888, 804], radius=106, fill=(24, 25, 31, 255), outline=(72, 74, 88, 220), width=8)
    # Grip accent stripe (iconic Kodak/Fuji disposable party vibe)
    bd.rounded_rectangle([136, 376, 330, 690], radius=34, fill=(36, 37, 45, 255))
    bd.rectangle([136, 392, 164, 674], fill=(255, 107, 44, 255))

    # Xenon flash window (top left) with radial warm highlight
    bd.rounded_rectangle([186, 268, 356, 344], radius=24, fill=(235, 240, 248, 255), outline=(120, 126, 140, 255), width=6)
    bd.rounded_rectangle([204, 284, 338, 328], radius=14, fill=(255, 242, 198, 255))
    for lx in range(218, 332, 18):
        bd.line([(lx, 286), (lx, 326)], fill=(210, 186, 120, 140), width=4)

    # Optical viewfinder window (top center-right)
    bd.rounded_rectangle([422, 266, 536, 346], radius=24, fill=(10, 12, 18, 255), outline=(92, 96, 112, 255), width=5)
    bd.ellipse([458, 286, 500, 328], fill=(38, 64, 96, 210))

    # 12h LED readout window (top right)
    bd.rounded_rectangle([676, 268, 832, 344], radius=22, fill=(12, 12, 16, 255), outline=(76, 78, 92, 255), width=4)
    # Minimal "12H" amber LED segments
    # '1'
    bd.rounded_rectangle([706, 286, 718, 326], radius=4, fill=(255, 107, 44, 255))
    # '2'
    bd.rounded_rectangle([734, 286, 766, 296], radius=4, fill=(255, 107, 44, 255))
    bd.rounded_rectangle([756, 286, 766, 309], radius=4, fill=(255, 107, 44, 255))
    bd.rounded_rectangle([734, 301, 766, 311], radius=4, fill=(255, 107, 44, 255))
    bd.rounded_rectangle([734, 301, 744, 326], radius=4, fill=(255, 107, 44, 255))
    bd.rounded_rectangle([734, 316, 766, 326], radius=4, fill=(255, 107, 44, 255))
    # 'H'
    bd.rounded_rectangle([780, 286, 790, 326], radius=4, fill=(255, 198, 92, 255))
    bd.rounded_rectangle([802, 286, 812, 326], radius=4, fill=(255, 198, 92, 255))
    bd.rounded_rectangle([780, 301, 812, 311], radius=4, fill=(255, 198, 92, 255))

    # Main central 35mm lens + 12h darkroom clock arc
    cx, cy = 532, 544
    bd.ellipse([cx - 178, cy - 178, cx + 178, cy + 178], fill=(14, 15, 20, 255), outline=(92, 95, 110, 255), width=10)
    # Amber developing countdown arc (270 degrees)
    bd.arc([cx - 156, cy - 156, cx + 156, cy + 156], start=-90, end=195, fill=(255, 107, 44, 255), width=16)
    bd.ellipse([cx - 126, cy - 126, cx + 126, cy + 126], fill=(20, 22, 30, 255), outline=(56, 58, 70, 255), width=6)
    # Multi-coated glass element
    bd.ellipse([cx - 86, cy - 86, cx + 86, cy + 86], fill=(10, 14, 24, 255), outline=(44, 72, 110, 180), width=4)
    bd.ellipse([cx - 46, cy - 46, cx + 46, cy + 46], fill=(6, 8, 14, 255))
    # Lens optical flare dots
    bd.ellipse([cx - 56, cy - 52, cx - 22, cy - 18], fill=(138, 210, 255, 155))
    bd.ellipse([cx + 22, cy + 26, cx + 42, cy + 46], fill=(255, 130, 64, 175))

    composed = Image.alpha_composite(bg, body)
    return composed.convert("RGB")


def main() -> None:
    master = render_master_icon(1024)
    filename = "icon-ios-1024.png"
    out_path = ASSETS_DIR / filename
    master.save(out_path, format="PNG", optimize=True)

    contents = {
        "images": [
            {
                "filename": filename,
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (ASSETS_DIR / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
    print(f"Generated 24-bit RGB iOS AppIcon: {out_path}")


if __name__ == "__main__":
    main()
