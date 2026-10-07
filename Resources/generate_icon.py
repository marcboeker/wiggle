#!/usr/bin/env python3
"""Generate Wiggle's app icon.

Draws a flat, two-tone squircle icon: two concentric stroked rings, evoking
the wheel overlay that opens around the pointer. Matches resticker's icon
style and scale (flat rounded-square background, single accent line-art
glyph at the same stroke weight and canvas fraction as resticker's drive
glyph, no gradients) with a different, Wiggle-specific colour pair.

Usage:
    python3 Resources/generate_icon.py

Produces:
    assets/app-icon.png        (1024x1024, for the README)
    Resources/AppIcon.iconset/icon_*.png
    Resources/AppIcon.icns   (via iconutil)
"""

import subprocess
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
DOCS = HERE.parent / "assets"

# Supersample factor for smooth anti-aliased edges when downscaling.
SUPERSAMPLE = 4
SIZE = 1024
CANVAS = SIZE * SUPERSAMPLE

# Colours: deep plum background with a warm coral glyph. Distinct from
# resticker's navy/blue pair, tuned to stay legible on both light and dark
# Dock/Finder backgrounds.
BG_COLOR = (35, 25, 51, 255)       # #231933
FG_COLOR = (255, 133, 82, 255)     # #FF8552

CORNER_RADIUS_FRACTION = 0.207     # matches resticker's squircle proportion


def draw_icon() -> Image.Image:
    img = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Rounded-square (squircle) background.
    radius = int(CANVAS * CORNER_RADIUS_FRACTION)
    draw.rounded_rectangle([0, 0, CANVAS - 1, CANVAS - 1], radius=radius, fill=BG_COLOR)

    cx = cy = CANVAS / 2

    # Stroke weight matches resticker's glyph outline: ~8-9px at a 256px
    # render, i.e. ~3.3% of canvas.
    stroke = CANVAS * 0.033

    # Outer ring. Sized so the glyph's overall footprint (outer edge of this
    # ring, including its own stroke) spans ~47% of the canvas width, the
    # same fraction resticker's drive glyph occupies, with matching generous
    # padding on all sides.
    outer_r = CANVAS * 0.228

    # Inner ring: concentric, at ~0.45x the outer ring's radius. That ratio
    # keeps a clear gap between the two rings so both read distinctly at
    # 32px, instead of merging into one thick band.
    inner_r = outer_r * 0.45

    for r in (outer_r, inner_r):
        draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            outline=FG_COLOR,
            width=int(stroke),
        )

    return img.resize((SIZE, SIZE), Image.LANCZOS)


def build_iconset(png_1024: Path, iconset_dir: Path) -> None:
    iconset_dir.mkdir(exist_ok=True)
    sizes = [16, 32, 128, 256, 512]
    img = Image.open(png_1024).convert("RGBA")
    for size in sizes:
        img.resize((size, size), Image.LANCZOS).save(iconset_dir / f"icon_{size}x{size}.png")
        img.resize((size * 2, size * 2), Image.LANCZOS).save(
            iconset_dir / f"icon_{size}x{size}@2x.png"
        )
    # 512@2x == 1024x1024, reuse the master render directly.
    img.save(iconset_dir / "icon_512x512@2x.png")


def main() -> None:
    DOCS.mkdir(exist_ok=True)
    png_path = DOCS / "app-icon.png"
    iconset_dir = HERE / "AppIcon.iconset"
    icns_path = HERE / "AppIcon.icns"

    icon = draw_icon()
    icon.save(png_path)
    print(f"wrote {png_path}")

    build_iconset(png_path, iconset_dir)
    print(f"wrote {iconset_dir}")

    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset_dir), "-o", str(icns_path)],
        check=True,
    )
    print(f"wrote {icns_path}")


if __name__ == "__main__":
    main()
