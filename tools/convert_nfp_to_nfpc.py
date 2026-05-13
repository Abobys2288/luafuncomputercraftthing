#!/usr/bin/env python3
"""
    Convert existing .nfp / .nfp256 files to .nfpc (compressed)
    Usage:
        python convert_nfp_to_nfpc.py smile.nfp256 smile.nfpc
"""
import sys
from pathlib import Path

NFP32_KEYS = "0123456789abcdefghijklmnopqrstuv"
NFP32_MAP = {c: i for i, c in enumerate(NFP32_KEYS)}


def encode_nfpc32_line(row):
    chars = [NFP32_KEYS[v] for v in row]
    return _encode_rle(chars, 1)


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


def convert(path_in, path_out):
    ext = Path(path_in).suffix.lower()
    text = Path(path_in).read_text(encoding="utf-8")
    lines = text.strip().splitlines()

    if ext == ".nfp256":
        pixels = []
        for line in lines:
            row = []
            for i in range(0, len(line), 2):
                row.append(int(line[i:i + 2], 16))
            pixels.append(row)
        mode = 256
    elif ext == ".nfp":
        pixels = []
        for line in lines:
            row = []
            for ch in line:
                row.append(NFP32_MAP.get(ch, 0))
            pixels.append(row)
        mode = 32
    else:
        print(f"Unknown extension: {ext}")
        sys.exit(1)

    h = len(pixels)
    w = max(len(r) for r in pixels) if pixels else 0

    out_lines = [f"!NFPC {w} {h} {mode}"]
    for row in pixels:
        if mode == 256:
            out_lines.append(encode_nfpc256_line(row))
        else:
            out_lines.append(encode_nfpc32_line(row))

    Path(path_out).write_text("\n".join(out_lines), encoding="utf-8")
    original = len(text)
    compressed = len(out_lines) + sum(len(l) for l in out_lines)
    print(f"Saved: {path_out} ({w}x{h}, NFPC {mode}-color)")
    print(f"Size: {original} -> {compressed} bytes ({compressed/original*100:.1f}%)")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python convert_nfp_to_nfpc.py input.nfp|input.nfp256 output.nfpc")
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
