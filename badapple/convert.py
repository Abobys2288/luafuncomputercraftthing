import cv2
import os
import sys
import math
import argparse

# === 16-цветная палитра CC:Tweaked (RGB для матчинга) ===
CC_PALETTE = [
    (1,     (255, 255, 255)),  # white
    (2,     (242, 242, 242)),  # lightGray
    (4,     (160, 160, 160)),  # gray
    (8,     (0, 0, 0)),        # black
    (16,    (242, 178, 54)),   # orange
    (32,    (229, 127, 216)),  # magenta
    (64,    (160, 196, 255)),  # lightBlue
    (128,   (222, 222, 128)),  # yellow
    (256,   (242, 178, 54)),   # orange2
    (512,   (164, 164, 164)),  # gray2
    (1024,  (229, 127, 216)),  # magenta2
    (2048,  (160, 196, 255)),  # lightBlue2
    (4096,  (222, 222, 128)),  # yellow2
    (8192,  (140, 192, 114)),  # lime
    (16384, (242, 131, 131)),  # pink
    (32768, (54, 118, 176)),   # blue
]


def color_distance(c1, c2):
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(c1, c2)))


def find_closest_cc_color(rgb):
    best_val = 8
    best_dist = float('inf')
    for val, color in CC_PALETTE:
        d = color_distance(rgb, color)
        if d < best_dist:
            best_dist = d
            best_val = val
    return best_val


def extract_frames(video_path, target_w, target_h, threshold=128, invert=False, skip=1):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"ERROR: Cannot open video: {video_path}")
        sys.exit(1)

    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    orig_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    orig_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    print(f"Video: {orig_w}x{orig_h}, {total} frames, {fps:.2f} FPS")
    print(f"Target: {target_w}x{target_h}, skip={skip}")

    frames = []
    idx = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        idx += 1
        if (idx - 1) % skip != 0:
            continue

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        resized = cv2.resize(gray, (target_w, target_h), interpolation=cv2.INTER_AREA)

        if invert:
            _, binary = cv2.threshold(resized, threshold, 255, cv2.THRESH_BINARY_INV)
        else:
            _, binary = cv2.threshold(resized, threshold, 255, cv2.THRESH_BINARY)

        # Упаковываем строку в байты: 2 пикселя в 1 символ (hex nibble)
        # Для 2-цветного: каждый пиксель = 1 бит
        frame_bytes = []
        for y in range(target_h):
            row_bytes = []
            for x_byte in range(0, target_w, 8):
                byte_val = 0
                for bit in range(8):
                    px = x_byte + bit
                    if px < target_w and binary[y, px] > 0:
                        byte_val |= (1 << (7 - bit))
                row_bytes.append(byte_val)
            frame_bytes.append(row_bytes)

        frames.append(frame_bytes)

        if len(frames) % 200 == 0:
            print(f"  {len(frames)} frames done...")

    cap.release()
    print(f"Extracted {len(frames)} frames.")
    return frames, fps


def generate_lua_bitpacked(frames, output_path, fps, target_w, target_h):
    """
    Генерирует Lua с побитовой упаковкой кадров.
    Каждый пиксель = 1 бит (0=black, 1=white).
    Каждый кадр = target_h строк, каждая строка = target_w//8 байт.
    Байты кодируются как десятичные числа в таблице.
    """
    print(f"Generating Lua: {output_path}")

    lines = []
    lines.append("--[[")
    lines.append("    Bad Apple!! for CC:Tweaked")
    lines.append(f"    {target_w}x{target_h}, {len(frames)} frames, {fps} FPS")
    lines.append("    Bit-packed: 1 bit per pixel, 8 pixels per byte")
    lines.append("]]")
    lines.append("")
    lines.append("local W, H = {}, {}".format(target_w, target_h))
    lines.append("local FPS = {}".format(fps))
    lines.append("local BYES_PER_ROW = {}".format(math.ceil(target_w / 8)))
    lines.append("")

    # Автоопределение дисплея
    lines.append("local function getDisplay()")
    lines.append("    local best = term")
    lines.append("    local bW, bH = term.getSize()")
    lines.append("    for _, s in ipairs({\"top\",\"bottom\",\"left\",\"right\",\"front\",\"back\"}) do")
    lines.append("        local ok, m = pcall(peripheral.wrap, s)")
    lines.append("        if ok and m and m.getSize then")
    lines.append("            pcall(function() m.setTextScale(1) end)")
    lines.append("            local w, h = m.getSize()")
    lines.append("            if w*h > bW*bH then best = m; bW = w; bH = h end")
    lines.append("        end")
    lines.append("    end")
    lines.append("    return best, bW, bH")
    lines.append("end")
    lines.append("")

    # Отрисовка кадра через blit
    lines.append("local function drawFrame(d, frame)")
    lines.append("    for y = 1, H do")
    lines.append("        local row = frame[y]")
    lines.append("        local text = {}")
    lines.append("        local fg  = {}")
    lines.append("        local bg  = {}")
    lines.append("        local x = 1")
    lines.append("        for i = 1, #row do")
    lines.append("            local byte = row[i]")
    lines.append("            for bit = 7, 0, -1 do")
    lines.append("                if x > W then break end")
    lines.append("                local white = (byte >> bit) & 1")
    lines.append("                if white == 1 then")
    lines.append("                    text[#text+1] = \" \"")
    lines.append("                    fg[#fg+1] = \"f\"")
    lines.append("                    bg[#bg+1] = \"0\"")
    lines.append("                else")
    lines.append("                    text[#text+1] = \" \"")
    lines.append("                    fg[#fg+1] = \"0\"")
    lines.append("                    bg[#bg+1] = \"f\"")
    lines.append("                end")
    lines.append("                x = x + 1")
    lines.append("            end")
    lines.append("        end")
    lines.append("        d.setCursorPos(1, y)")
    lines.append("        d.blit(table.concat(text), table.concat(fg), table.concat(bg))")
    lines.append("    end")
    lines.append("end")
    lines.append("")

    # Данные кадров
    lines.append("local frames = {")
    for fi, frame in enumerate(frames):
        lines.append("    {")
        for row in frame:
            row_str = ",".join(str(b) for b in row)
            lines.append(f"        {{{row_str}}},")
        if fi < len(frames) - 1:
            lines.append("    },")
        else:
            lines.append("    }")
    lines.append("}")
    lines.append("")

    # Main
    lines.append("local function main()")
    lines.append("    local d, w, h = getDisplay()")
    lines.append("    d.clear()")
    lines.append("    print(\"Bad Apple!! CC:Tweaked\")")
    lines.append("    print(\"Display: \"..w..\"x\"..h)")
    lines.append("    print(\"Frames: \"..#frames)")
    lines.append("    print(\"Press any key...\")")
    lines.append("    os.pullEvent(\"key\")")
    lines.append("    d.clear()")
    lines.append("    local i = 1")
    lines.append("    local t = os.startTimer(1/FPS)")
    lines.append("    while i <= #frames do")
    lines.append("        local ev, p = os.pullEvent()")
    lines.append("        if ev == \"timer\" then")
    lines.append("            drawFrame(d, frames[i])")
    lines.append("            i = i + 1")
    lines.append("            if i <= #frames then t = os.startTimer(1/FPS) end")
    lines.append("        elseif ev == \"key\" then break end")
    lines.append("    end")
    lines.append("    d.clear()")
    lines.append("    d.setCursorPos(1,1)")
    lines.append("    print(\"Done!\")")
    lines.append("end")
    lines.append("")
    lines.append("main()")

    with open(output_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))

    size = os.path.getsize(output_path)
    print(f"Done: {output_path} ({size/1024/1024:.2f} MB)")


def generate_lua_string_encoded(frames, output_path, fps, target_w, target_h):
    """
    Максимально компактный формат: все кадры упакованы в одну бинарную строку.
    Каждый пиксель = 1 бит. Строки идут подряд, кадры подряд.
    Биты -> байты -> символы через string.char (latin-1 / binary string).
    Lua декодирует строку обратно в биты при отрисовке.
    """
    print(f"Generating string-encoded Lua: {output_path}")

    bpr = math.ceil(target_w / 8)  # bytes per row

    # Собираем все байты
    all_bytes = bytearray()
    for frame in frames:
        for row in frame:
            all_bytes.extend(row)

    # Кодируем байты в строку Lua через long string [[]]
    # В long strings все байты 0-255 проходят напрямую
    # Проблема: последовательность ]] ломает синтаксис
    # Решение: используем [=[...]=] — тогда только ]=] ломает
    # Но ]=] тоже может встретиться. Используем больше =: [==[...]==]
    # В бинарных данных ]===] крайне маловероятно, но на всякий случай проверим

    raw_bytes = bytes(all_bytes)

    # Проверяем наличие ]===] в данных
    delimiter = b"]===]"
    if delimiter in raw_bytes:
        # Редко, но если есть — используем string.char метод
        CHUNK = 8000
        parts = []
        for i in range(0, len(all_bytes), CHUNK):
            chunk = all_bytes[i:i+CHUNK]
            nums = ",".join(str(b) for b in chunk)
            parts.append("string.char(" + nums + ")")
        data_lua = "..".join(parts)
    else:
        data_lua = '[==[' + raw_bytes.decode('latin-1') + ']==]'

    lines = []
    lines.append("--[[")
    lines.append("    Bad Apple!! for CC:Tweaked")
    lines.append(f"    {target_w}x{target_h}, {len(frames)} frames, {fps} FPS")
    lines.append("]]")
    lines.append("")
    lines.append("local W,H={},{}".format(target_w, target_h))
    lines.append("local FPS={}".format(fps))
    lines.append("local BPR={}".format(bpr))
    lines.append("local N={}".format(len(frames)))
    lines.append("")

    lines.append("local function getDisplay()")
    lines.append("    local best=term")
    lines.append("    local bW,bH=term.getSize()")
    lines.append("    for _,s in ipairs({\"top\",\"bottom\",\"left\",\"right\",\"front\",\"back\"})do")
    lines.append("        local ok,m=pcall(peripheral.wrap,s)")
    lines.append("        if ok and m and m.getSize then")
    lines.append("            pcall(function()m.setTextScale(1)end)")
    lines.append("            local w,h=m.getSize()")
    lines.append("            if w*h>bW*bH then best=m;bW=w;bH=h end")
    lines.append("        end")
    lines.append("    end")
    lines.append("    return best,bW,bH")
    lines.append("end")
    lines.append("")

    lines.append("local function draw(d,f)")
    lines.append("    local off=(f-1)*BPR*H+1")
    lines.append("    for y=1,H do")
    lines.append("        local t,f,g={},{},{}")
    lines.append("        local x=1")
    lines.append("        for i=1,BPR do")
    lines.append("            local b=string.byte(DATA,off)")
    lines.append("            off=off+1")
    lines.append("            for bit=7,0,-1 do")
    lines.append("                if x>W then break end")
    lines.append("                if(b>>bit)&1==1 then")
    lines.append("                    t[#t+1]=\" \"f[#f+1]=\"f\"g[#g+1]=\"0\"")
    lines.append("                else")
    lines.append("                    t[#t+1]=\" \"f[#f+1]=\"0\"g[#g+1]=\"f\"")
    lines.append("                end")
    lines.append("                x=x+1")
    lines.append("            end")
    lines.append("        end")
    lines.append("        d.setCursorPos(1,y)")
    lines.append("        d.blit(table.concat(t),table.concat(f),table.concat(g))")
    lines.append("    end")
    lines.append("end")
    lines.append("")

    lines.append("local DATA=" + data_lua)
    lines.append("")
    lines.append("local function main()")
    lines.append("    local d,w,h=getDisplay()")
    lines.append("    d.clear()")
    lines.append("    print(\"Bad Apple!! CC:Tweaked\")")
    lines.append("    print(\"Display: \"..w..\"x\"..h)")
    lines.append("    print(\"Press any key...\")")
    lines.append("    os.pullEvent(\"key\")")
    lines.append("    d.clear()")
    lines.append("    local i=1")
    lines.append("    local t=os.startTimer(1/FPS)")
    lines.append("    while i<=N do")
    lines.append("        local e,p=os.pullEvent()")
    lines.append("        if e==\"timer\"then")
    lines.append("            draw(d,i)")
    lines.append("            i=i+1")
    lines.append("            if i<=N then t=os.startTimer(1/FPS)end")
    lines.append("        elseif e==\"key\"then break end")
    lines.append("    end")
    lines.append("    d.clear()d.setCursorPos(1,1)print(\"Done!\")")
    lines.append("end")
    lines.append("")
    lines.append("main()")

    with open(output_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))

    size = os.path.getsize(output_path)
    print(f"Done: {output_path} ({size/1024/1024:.2f} MB)")


def main():
    parser = argparse.ArgumentParser(description="Bad Apple!! to CC:Tweaked converter")
    parser.add_argument("--video", type=str, default=None)
    parser.add_argument("--output", type=str, default="badapple.lua")
    parser.add_argument("--width", type=int, default=None)
    parser.add_argument("--height", type=int, default=None)
    parser.add_argument("--threshold", type=int, default=128)
    parser.add_argument("--fps", type=int, default=None)
    parser.add_argument("--skip", type=int, default=1)
    parser.add_argument("--format", choices=["rle", "bit", "str"], default="str")
    parser.add_argument("--invert", action="store_true")

    args = parser.parse_args()

    video_path = args.video
    if not video_path:
        for f in os.listdir("."):
            if f.lower().endswith((".mp4", ".avi", ".mkv", ".mov")):
                video_path = f
                break
        if not video_path:
            print("ERROR: No video found!")
            sys.exit(1)

    print(f"Input: {video_path}")

    cap = cv2.VideoCapture(video_path)
    orig_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    orig_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    video_fps = cap.get(cv2.CAP_PROP_FPS)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    cap.release()

    target_fps = args.fps or video_fps

    if args.width and args.height:
        tw, th = args.width, args.height
    elif args.width:
        tw = args.width
        th = int(tw * orig_h / orig_w)
    elif args.height:
        th = args.height
        tw = int(th * orig_w / orig_h)
    else:
        # Дефолт: монитор 3x3 = 39x15
        tw, th = 39, 15

    print(f"Output: {tw}x{th}, FPS={target_fps}, skip={args.skip}")

    frames, _ = extract_frames(video_path, tw, th, args.threshold, args.invert, args.skip)

    if args.skip > 1:
        target_fps = target_fps / args.skip

    output_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), args.output)

    if args.format == "bit":
        generate_lua_bitpacked(frames, output_path, round(target_fps, 2), tw, th)
    elif args.format == "str":
        generate_lua_string_encoded(frames, output_path, round(target_fps, 2), tw, th)
    else:
        # Конвертируем bit-packed frames в pixel arrays для RLE
        pixel_frames = []
        for frame in frames:
            pixel_frame = []
            for row_bytes in frame:
                row = []
                for byte_val in row_bytes:
                    for bit in range(7, -1, -1):
                        row.append((byte_val >> bit) & 1)
                row = row[:tw]  # trim to exact width
                pixel_frame.append(row)
            pixel_frames.append(pixel_frame)
        generate_lua_rle_compact(pixel_frames, output_path, round(target_fps, 2), tw, th)

    print(f"\nCopy {args.output} to CC:Tweaked and run!")


if __name__ == "__main__":
    main()
