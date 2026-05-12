#!/usr/bin/env python3
"""
    CCOS NFP Converter
    ==================
    Converts any image (PNG/JPG/BMP/etc.) to NFP pixel format.

    Usage:
        python convert_to_nfp.py input.png --size 64 48 --output out.nfp
        python convert_to_nfp.py input.png --fit-cc --output out.nfp
        python convert_to_nfp.py input.png --ccos --output out.nfp

    Formats:
        --fit-cc     Standard 16-color ComputerCraft palette (default)
        --ccos       32-color CCOS extended palette (matches render.lua)

    The output .nfp file can be opened in CCOS Image Viewer.
"""

import sys
import argparse
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow not installed. Run: pip install Pillow")
    sys.exit(1)

# ============================================================
# Palettes
# ============================================================

# Standard CC 16-color palette (paintutils / NPaintPro standard)
# Each char -> (R, G, B)
CC16_PALETTE = {
    '0': (240, 240, 240),   # white
    '1': (242, 178,  51),   # orange
    '2': (229, 127, 216),   # magenta
    '3': (153, 217, 234),   # lightBlue
    '4': (222, 222, 108),   # yellow
    '5': (127, 204,  25),   # lime
    '6': (242, 178, 204),   # pink
    '7': ( 76,  76,  76),   # gray
    '8': (153, 153, 153),   # lightGray
    '9': ( 76, 153, 178),   # cyan
    'a': (127,  63, 178),   # purple
    'b': ( 51, 102, 204),   # blue
    'c': (127, 102,  76),   # brown
    'd': ( 87, 166,  78),   # green
    'e': (204,  76,  76),   # red
    'f': ( 25,  25,  25),   # black
}

# CCOS 32-color palette (matches render.lua PALETTE indices 0-31)
# We map each to a single character for our extended .nfp format
CCOS32_PALETTE = {
    '0': (  0,   0,   0),   # 0  BLACK
    '1': (255, 255, 255),   # 1  WHITE
    '2': (192, 192, 192),   # 2  GRAY
    '3': (223, 223, 223),   # 3  LIGHT_GRAY
    '4': (128, 128, 128),   # 4  DARK_GRAY
    '5': (  0,   0, 192),   # 5  BLUE
    '6': (  0,   0, 128),   # 6  DARK_BLUE
    '7': (  0, 192, 192),   # 7  CYAN
    '8': (128, 224, 255),   # 8  LIGHT_BLUE
    '9': (  0, 192,   0),   # 9  GREEN
    'a': (  0, 128,   0),   # 10 DARK_GREEN
    'b': (255,   0,   0),   # 11 RED
    'c': (128,   0,   0),   # 12 DARK_RED
    'd': (255, 255,   0),   # 13 YELLOW
    'e': (255, 192,   0),   # 14 ORANGE
    'f': (128,  64,   0),   # 15 BROWN
    'g': (128,   0, 128),   # 16 PURPLE
    'h': (255, 128, 255),   # 17 PINK
    'i': ( 64,  64,  64),   # 18 DARK_TITLE_INACTIVE
    'j': (  0,  84, 168),   # 19 W95_TITLE_BLUE
    'k': (128, 158, 200),   # 20 W95_TITLE_INACTIVE
    'l': (  0,   0, 255),   # 21 PURE_BLUE
    'm': (240, 240, 240),   # 22 ALMOST_WHITE
    'n': ( 32,  32,  32),   # 23 NEAR_BLACK
    'o': (160, 160, 160),   # 24 MID_GRAY
    'p': (200, 200, 200),   # 25 BUTTON_FACE
    'q': (248, 248, 248),   # 26 BUTTON_HIGHLIGHT
    'r': (  0,   0,  64),   # 27 DEEP_NAVY
    's': ( 48,  48,  48),   # 28 BTNFACE_DARK
    't': (  0, 128,   0),   # 29 DARK_GREEN_BG
    'u': (  0, 128, 128),   # 30 W95_DESKTOP
    'v': (192, 192, 192),   # 31 LIGHT_BG
}


def color_distance(c1, c2):
    """Euclidean distance in RGB space."""
    return sum((a - b) ** 2 for a, b in zip(c1, c2))


def find_closest(rgb, palette):
    """Find the palette key with minimum color distance."""
    best_key = '0'
    best_dist = float('inf')
    for key, color in palette.items():
        d = color_distance(rgb, color)
        if d < best_dist:
            best_dist = d
            best_key = key
    return best_key


def floyd_steinberg_dither(img, palette):
    """
    Apply Floyd-Steinberg dithering to reduce color banding.
    img: PIL Image (RGB)
    Returns a 2D list of palette keys.
    """
    width, height = img.size
    # Convert to mutable list of [R, G, B] floats
    pixels = [[list(img.getpixel((x, y))) for x in range(width)] for y in range(height)]
    out = [[' ' for _ in range(width)] for _ in range(height)]

    for y in range(height):
        for x in range(width):
            old = pixels[y][x]
            key = find_closest(tuple(old), palette)
            new = palette[key]
            out[y][x] = key
            error = [old[i] - new[i] for i in range(3)]

            # Diffuse error
            if x + 1 < width:
                for i in range(3):
                    pixels[y][x + 1][i] += error[i] * 7 / 16
            if y + 1 < height:
                if x > 0:
                    for i in range(3):
                        pixels[y + 1][x - 1][i] += error[i] * 3 / 16
                for i in range(3):
                    pixels[y + 1][x][i] += error[i] * 5 / 16
                if x + 1 < width:
                    for i in range(3):
                        pixels[y + 1][x + 1][i] += error[i] * 1 / 16
    return out


def nearest_neighbor(img, palette):
    """Simple nearest-neighbor conversion (no dithering)."""
    width, height = img.size
    out = []
    for y in range(height):
        row = []
        for x in range(width):
            rgb = img.getpixel((x, y))
            row.append(find_closest(rgb, palette))
        out.append(row)
    return out


def convert_image(image_path, output_path, size=None, fit_cc=True, dither=False):
    """Main conversion function."""
    img = Image.open(image_path).convert('RGB')
    orig_w, orig_h = img.size

    # Pick palette
    if fit_cc:
        palette = CC16_PALETTE
        print(f"Palette: CC 16-color (standard)")
    else:
        palette = CCOS32_PALETTE
        print(f"Palette: CCOS 32-color (extended)")

    # Resize
    if size:
        target_w, target_h = size
    else:
        # Default: clamp to typical CC monitor size
        target_w = min(orig_w, 128)
        target_h = min(orig_h, 96)
        # Keep aspect ratio
        ratio = min(target_w / orig_w, target_h / orig_h)
        target_w = int(orig_w * ratio)
        target_h = int(orig_h * ratio)

    if (target_w, target_h) != (orig_w, orig_h):
        img = img.resize((target_w, target_h), Image.LANCZOS)
        print(f"Resized: {orig_w}x{orig_h} -> {target_w}x{target_h}")
    else:
        print(f"Size: {orig_w}x{orig_h}")

    # Convert
    if dither:
        print("Dithering: Floyd-Steinberg")
        pixels = floyd_steinberg_dither(img, palette)
    else:
        print("Quantization: nearest neighbor")
        pixels = nearest_neighbor(img, palette)

    # Write NFP
    lines = [''.join(row) for row in pixels]
    Path(output_path).write_text('\n'.join(lines), encoding='utf-8')
    print(f"Saved: {output_path} ({target_w}x{target_h})")


def main():
    parser = argparse.ArgumentParser(description='Convert images to NFP format for CCOS')
    parser.add_argument('input', help='Input image file')
    parser.add_argument('-o', '--output', default='out.nfp', help='Output .nfp file')
    parser.add_argument('-s', '--size', nargs=2, type=int, metavar=('W', 'H'),
                        help='Target size in pixels')
    parser.add_argument('--ccos', action='store_true',
                        help='Use CCOS 32-color palette instead of CC 16-color')
    parser.add_argument('--dither', action='store_true',
                        help='Apply Floyd-Steinberg dithering')
    args = parser.parse_args()

    if not Path(args.input).exists():
        print(f"ERROR: File not found: {args.input}")
        sys.exit(1)

    convert_image(
        args.input,
        args.output,
        size=args.size,
        fit_cc=not args.ccos,
        dither=args.dither
    )


if __name__ == '__main__':
    main()
