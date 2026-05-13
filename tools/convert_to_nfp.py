#!/usr/bin/env python3
"""
    CCOS NFP Converter v3
    =====================
    Converts any image to NFP, NFP256, or NFPC (compressed) format.

    Usage:
        python convert_to_nfp.py input.png --size 64 48 -o out.nfp
        python convert_to_nfp.py input.png --256 --size 64 48 -o out.nfp256
        python convert_to_nfp.py input.png --nfpc --size 64 48 -o out.nfpc
        python convert_to_nfp.py input.png --dither -o out.nfp

    Formats:
        .nfp      32-color text (1 char/pixel, backward compatible)
        .nfp256   256-color hex (2 hex chars/pixel, uses full palette)
        .nfpc     RLE-compressed NFP/NFP256 (smaller for icons & UI)

    The 256-color palette in render.lua:
        0-31:   W95 colors
        32-215: 6x6x6 RGB cube (R,G,B each: 0,51,102,153,204,255)
        216-255: Grayscale
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

# 32-color text palette (single character per pixel)
NFP32_KEYS = "0123456789abcdefghijklmnopqrstuv"
NFP32_PALETTE = {}
# 0-31: original W95 colors
w95 = [
    (0,0,0), (255,255,255), (192,192,192), (223,223,223),
    (128,128,128), (0,0,192), (0,0,128), (0,192,192),
    (128,224,255), (0,192,0), (0,128,0), (255,0,0),
    (128,0,0), (255,255,0), (255,192,0), (128,64,0),
    (128,0,128), (255,128,255), (64,64,64), (0,84,168),
    (128,158,200), (0,0,255), (240,240,240), (32,32,32),
    (160,160,160), (200,200,200), (248,248,248), (0,0,64),
    (48,48,48), (0,128,0), (0,128,128), (192,192,192),
]
for i, c in enumerate(w95):
    NFP32_PALETTE[NFP32_KEYS[i]] = c

# 256-color palette for .nfp256 hex encoding
PALETTE256 = {}
# 0-31: W95 colors
for i, c in enumerate(w95):
    PALETTE256[i] = c
# 32-215: 6x6x6 RGB cube
idx = 32
for r in range(6):
    for g in range(6):
        for b in range(6):
            PALETTE256[idx] = (r*51, g*51, b*51)
            idx += 1
# 216-255: grayscale
for i in range(40):
    v = int(i * 255 / 39)
    PALETTE256[216 + i] = (v, v, v)


def color_distance(c1, c2):
    return sum((a - b) ** 2 for a, b in zip(c1, c2))


def find_closest(rgb, palette):
    best_key = 0
    best_dist = float('inf')
    for key, color in palette.items():
        d = color_distance(rgb, color)
        if d < best_dist:
            best_dist = d
            best_key = key
    return best_key


def floyd_steinberg_dither(img, palette):
    width, height = img.size
    pixels = [[list(img.getpixel((x, y))) for x in range(width)] for y in range(height)]
    out = [[0 for _ in range(width)] for _ in range(height)]
    for y in range(height):
        for x in range(width):
            old = pixels[y][x]
            key = find_closest(tuple(old), palette)
            new = palette[key]
            out[y][x] = key
            error = [old[i] - new[i] for i in range(3)]
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
    width, height = img.size
    out = []
    for y in range(height):
        row = []
        for x in range(width):
            rgb = img.getpixel((x, y))
            row.append(find_closest(rgb, palette))
        out.append(row)
    return out


def encode_nfpc32_line(row):
    """Compress a 32-color row into NFPC text.
    row is a list of palette key characters."""
    return _encode_rle(row, 1)


def encode_nfpc256_line(row):
    """Compress a 256-color row into NFPC text."""
    hexes = [f"{v:02x}" for v in row]
    return _encode_rle(hexes, 2)


def _encode_rle(items, item_len):
    """Generic RLE encoder for NFPC.
    count is always encoded as exactly 2 lower-case hex digits (02-ff).
    Runs longer than 255 are split into multiple chunks."""
    if not items:
        return ""
    result = []
    i = 0
    n = len(items)
    while i < n:
        val = items[i]
        j = i + 1
        while j < n and items[j] == val:
            j += 1
        count = j - i
        if count == 1:
            result.append(val)
        else:
            while count > 0:
                chunk = min(count, 255)
                count_hex = f"{chunk:02x}"
                rle = f"~{val}{count_hex}"
                raw = val * chunk
                if len(rle) < len(raw):
                    result.append(rle)
                else:
                    result.append(raw)
                count -= chunk
        i = j
    return "".join(result)


def convert_image(image_path, output_path, size=None, use256=False, dither=False, use_nfpc=False):
    img = Image.open(image_path).convert('RGB')
    orig_w, orig_h = img.size

    if size:
        target_w, target_h = size
    else:
        target_w = min(orig_w, 128)
        target_h = min(orig_h, 96)
        ratio = min(target_w / orig_w, target_h / orig_h)
        target_w = int(orig_w * ratio)
        target_h = int(orig_h * ratio)

    if (target_w, target_h) != (orig_w, orig_h):
        img = img.resize((target_w, target_h), Image.LANCZOS)
        print(f"Resized: {orig_w}x{orig_h} -> {target_w}x{target_h}")
    else:
        print(f"Size: {orig_w}x{orig_h}")

    ext = Path(output_path).suffix.lower()
    if use_nfpc or ext == '.nfpc':
        use_nfpc = True

    if use256 or ext == '.nfp256':
        palette = PALETTE256
        print("Palette: 256-color (full)")
    else:
        palette = NFP32_PALETTE
        print("Palette: 32-color")

    if dither:
        print("Dithering: Floyd-Steinberg")
        pixels = floyd_steinberg_dither(img, palette)
    else:
        print("Quantization: nearest neighbor")
        pixels = nearest_neighbor(img, palette)

    # Write output
    if use_nfpc or ext == '.nfpc':
        mode = 256 if (use256 or palette is PALETTE256) else 32
        lines = [f"!NFPC {target_w} {target_h} {mode}"]
        for row in pixels:
            if mode == 256:
                lines.append(encode_nfpc256_line(row))
            else:
                lines.append(encode_nfpc32_line(row))
        Path(output_path).write_text('\n'.join(lines), encoding='utf-8')
        print(f"Saved: {output_path} ({target_w}x{target_h}, NFPC {mode}-color)")
    elif use256 or ext == '.nfp256':
        # 2 hex chars per pixel
        lines = []
        for row in pixels:
            lines.append(''.join(f'{v:02x}' for v in row))
        Path(output_path).write_text('\n'.join(lines), encoding='utf-8')
        print(f"Saved: {output_path} ({target_w}x{target_h}, 256-color)")
    else:
        # Build reverse lookup for 32-color: index -> char
        idx_to_char = {v: k for k, v in enumerate(NFP32_KEYS)}
        lines = []
        for row in pixels:
            lines.append(''.join(idx_to_char.get(v, '0') for v in row))
        Path(output_path).write_text('\n'.join(lines), encoding='utf-8')
        print(f"Saved: {output_path} ({target_w}x{target_h}, 32-color)")


def main():
    parser = argparse.ArgumentParser(description='Convert images to NFP for CCOS')
    parser.add_argument('input', help='Input image file')
    parser.add_argument('-o', '--output', default='out.nfp', help='Output file')
    parser.add_argument('-s', '--size', nargs=2, type=int, metavar=('W', 'H'), help='Target size')
    parser.add_argument('--256', dest='use256', action='store_true', help='Use 256-color hex format (.nfp256)')
    parser.add_argument('--nfpc', action='store_true', help='Use compressed RLE format (.nfpc)')
    parser.add_argument('--dither', action='store_true', help='Apply Floyd-Steinberg dithering')
    args = parser.parse_args()

    if not Path(args.input).exists():
        print(f"ERROR: File not found: {args.input}")
        sys.exit(1)

    convert_image(args.input, args.output, size=args.size, use256=args.use256, dither=args.dither, use_nfpc=args.nfpc)


if __name__ == '__main__':
    main()
