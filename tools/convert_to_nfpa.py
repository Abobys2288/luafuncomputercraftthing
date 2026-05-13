#!/usr/bin/env python3
"""
    CCOS NFPA Converter v1
    ======================
    Converts images, GIFs and videos to NFPA (NFP Animation) format.

    Usage:
        python convert_to_nfpa.py input.gif --mode 256 --size 64 48 --fps 10 -o out.nfpa
        python convert_to_nfpa.py input.png --mode 32 --size 64 48 -o out.nfpa
        python convert_to_nfpa.py input.mp4 --mode 256 --size 64 48 --fps 10 -o out.nfpa
        python convert_to_nfpa.py input.mp4 --mode 256 --size 64 48 --fps 10 --dither -o out.nfpa
"""

import sys
import argparse
import tempfile
import subprocess
import os
import glob
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow not installed. Run: pip install Pillow")
    sys.exit(1)

# ============================================================
# Palettes (same as convert_to_nfp.py)
# ============================================================
NFP32_KEYS = "0123456789abcdefghijklmnopqrstuv"
NFP32_PALETTE = {}
w95 = [
    (0, 0, 0), (255, 255, 255), (192, 192, 192), (223, 223, 223),
    (128, 128, 128), (0, 0, 192), (0, 0, 128), (0, 192, 192),
    (128, 224, 255), (0, 192, 0), (0, 128, 0), (255, 0, 0),
    (128, 0, 0), (255, 255, 0), (255, 192, 0), (128, 64, 0),
    (128, 0, 128), (255, 128, 255), (64, 64, 64), (0, 84, 168),
    (128, 158, 200), (0, 0, 255), (240, 240, 240), (32, 32, 32),
    (160, 160, 160), (200, 200, 200), (248, 248, 248), (0, 0, 64),
    (48, 48, 48), (0, 128, 0), (0, 128, 128), (192, 192, 192),
]
for i, c in enumerate(w95):
    NFP32_PALETTE[NFP32_KEYS[i]] = c

PALETTE256 = {}
for i, c in enumerate(w95):
    PALETTE256[i] = c
idx = 32
for r in range(6):
    for g in range(6):
        for b in range(6):
            PALETTE256[idx] = (r * 51, g * 51, b * 51)
            idx += 1
for i in range(40):
    v = int(i * 255 / 39)
    PALETTE256[216 + i] = (v, v, v)


# ============================================================
# Quantization & Dithering
# ============================================================
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


# ============================================================
# NFPC RLE Encoding
# ============================================================
def encode_nfpc32_line(row):
    return _encode_rle(row, 1)


def encode_nfpc256_line(row):
    hexes = [f"{v:02x}" for v in row]
    return _encode_rle(hexes, 2)


def _encode_rle(items, item_len):
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


# ============================================================
# Frame loading from different sources
# ============================================================
def load_frames(path, target_size, fps, max_duration=None):
    ext = Path(path).suffix.lower()
    frames = []

    if ext in ('.png', '.jpg', '.jpeg', '.bmp', '.webp'):
        img = Image.open(path).convert('RGB')
        if target_size and img.size != tuple(target_size):
            img = img.resize(target_size, Image.LANCZOS)
        frames.append(img)

    elif ext == '.gif':
        img = Image.open(path)
        try:
            while True:
                frame = img.copy().convert('RGB')
                if target_size and frame.size != tuple(target_size):
                    frame = frame.resize(target_size, Image.LANCZOS)
                frames.append(frame)
                img.seek(img.tell() + 1)
        except EOFError:
            pass

    elif ext in ('.mp4', '.avi', '.mkv', '.webm', '.mov', '.flv'):
        temp_dir = tempfile.mkdtemp(prefix="nfpa_")
        w, h = target_size or (64, 48)
        vf = f"fps={fps},scale={w}:{h}:flags=lanczos"
        frame_pattern = os.path.join(temp_dir, "frame_%04d.png")
        cmd = ["ffmpeg", "-y", "-i", str(path), "-vf", vf, "-pix_fmt", "rgb24"]
        if max_duration:
            cmd += ["-t", str(max_duration)]
        cmd.append(frame_pattern)
        try:
            subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except subprocess.CalledProcessError as e:
            print(f"FFmpeg error: {e.stderr.decode()}")
            sys.exit(1)

        frame_files = sorted(glob.glob(frame_pattern.replace("%04d", "*")))
        for f in frame_files:
            frames.append(Image.open(f).convert('RGB'))
        # cleanup
        for f in frame_files:
            os.remove(f)
        os.rmdir(temp_dir)
    else:
        print(f"Unsupported extension: {ext}")
        sys.exit(1)

    return frames


# ============================================================
# Main conversion
# ============================================================
def convert(input_path, output_path, size=None, mode=256, fps=10, loop=0, dither=False, max_duration=None):
    target_w, target_h = size or (64, 48)
    frames = load_frames(input_path, (target_w, target_h), fps, max_duration)
    if not frames:
        print("No frames loaded")
        sys.exit(1)

    palette = PALETTE256 if mode == 256 else NFP32_PALETTE
    delay_ms = max(1, int(1000 / fps))

    out_lines = [f"!NFPA {target_w} {target_h} {mode} {delay_ms} {loop} {len(frames)}"]

    for frame_idx, frame in enumerate(frames):
        if dither:
            pixels = floyd_steinberg_dither(frame, palette)
        else:
            pixels = nearest_neighbor(frame, palette)

        for row in pixels:
            if mode == 256:
                out_lines.append(encode_nfpc256_line(row))
            else:
                out_lines.append(encode_nfpc32_line(row))

        if (frame_idx + 1) % 10 == 0 or frame_idx == len(frames) - 1:
            print(f"Encoded {frame_idx + 1}/{len(frames)} frames...")

    Path(output_path).write_text("\n".join(out_lines), encoding="utf-8")
    original_size = Path(input_path).stat().st_size
    compressed_size = len("\n".join(out_lines))
    print(f"Saved: {output_path}")
    print(f"Frames: {len(frames)}, Size: {original_size} -> {compressed_size} bytes ({compressed_size/original_size*100:.1f}%)")


def main():
    parser = argparse.ArgumentParser(description="Convert images/video to NFPA for CCOS")
    parser.add_argument("input", help="Input file (png, jpg, gif, mp4, ...)")
    parser.add_argument("-o", "--output", default="out.nfpa", help="Output .nfpa file")
    parser.add_argument("-s", "--size", nargs=2, type=int, metavar=("W", "H"), help="Target size (default 64 48)")
    parser.add_argument("-m", "--mode", type=int, choices=[32, 256], default=256, help="Color mode (default 256)")
    parser.add_argument("--fps", type=int, default=10, help="Frames per second (default 10)")
    parser.add_argument("--loop", type=int, default=0, help="Loop count, 0 = infinite (default 0)")
    parser.add_argument("--duration", type=float, default=None, help="Max duration in seconds (for video)")
    parser.add_argument("--dither", action="store_true", help="Apply Floyd-Steinberg dithering")
    args = parser.parse_args()

    if not Path(args.input).exists():
        print(f"ERROR: File not found: {args.input}")
        sys.exit(1)

    convert(args.input, args.output, size=args.size, mode=args.mode, fps=args.fps, loop=args.loop, dither=args.dither, max_duration=args.duration)


if __name__ == "__main__":
    main()
