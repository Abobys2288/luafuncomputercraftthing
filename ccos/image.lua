--[[
    CCOS Image Library — Unified decoder
    ====================================
    Decodes .nfp (32-color), .nfp256 (256-color), .nfpc (compressed),
    .nfpa (animation) image formats.
    Codecs: legacy RLE, C2, C3, C4, C5 (LZSS+C3), C6 (region+LZW),
            C7 (PRED+LZW+LZSS / 4x4 block), C8 (composite per-frame).

    Single source of truth — used by init.lua (boot logo), desktop.lua
    (icons) and programs/imgview (viewer). No dependency on globals.
]]

local image = {}

-- ============================================================
-- Lookup tables
-- ============================================================
local NFP32_KEYS = "0123456789abcdefghijklmnopqrstuv"
local NFP32_MAP = {}
for i = 1, #NFP32_KEYS do NFP32_MAP[NFP32_KEYS:sub(i, i)] = i - 1 end

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_MAP = {}
for i = 1, #B64_CHARS do B64_MAP[B64_CHARS:sub(i, i)] = i - 1 end

-- ============================================================
-- Base64 decode
-- ============================================================
function image.base64Bytes(text)
    local out, i = {}, 1
    while i <= #text do
        local c1 = B64_MAP[text:sub(i, i)] or 0
        local c2 = B64_MAP[text:sub(i + 1, i + 1)] or 0
        local c3s = text:sub(i + 2, i + 2)
        local c4s = text:sub(i + 3, i + 3)
        local c3 = B64_MAP[c3s] or 0
        local c4 = B64_MAP[c4s] or 0
        local n = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
        out[#out + 1] = math.floor(n / 65536) % 256
        if c3s ~= "=" and c3s ~= "" then out[#out + 1] = math.floor(n / 256) % 256 end
        if c4s ~= "=" and c4s ~= "" then out[#out + 1] = n % 256 end
        i = i + 4
    end
    return out
end

-- ============================================================
-- Raw row parsers
-- ============================================================
function image.parseNfp256Line(line, stats)
    local row = {}
    for i = 1, #line, 2 do
        local val = tonumber(line:sub(i, i + 1), 16)
        if val then row[#row + 1] = val
        elseif stats then stats.bad = stats.bad + 1; row[#row + 1] = 0
        else row[#row + 1] = 0 end
    end
    return row
end

function image.parseNfp32Line(line, stats)
    local row = {}
    for i = 1, #line do
        local ch = line:sub(i, i):lower()
        local val = NFP32_MAP[ch]
        if val ~= nil then
            row[#row + 1] = val
        else
            row[#row + 1] = 0
            if stats then stats.bad = stats.bad + 1 end
        end
    end
    return row
end

-- ============================================================
-- Helpers
-- ============================================================
local function fitRow(row, width)
    for i = #row + 1, width do row[i] = 0 end
    for i = width + 1, #row do row[i] = nil end
    return row
end

local function blankRow(width)
    local row = {}
    for i = 1, width do row[i] = 0 end
    return row
end

local function flatToRows(flat, w, h)
    local rows, p = {}, 1
    for y = 1, h do
        local row = {}
        for x = 1, w do row[x] = flat[p] or 0; p = p + 1 end
        rows[y] = row
    end
    return rows
end

local function copyFlat(prevFlat, total)
    local flat = {}
    for i = 1, total do flat[i] = prevFlat and prevFlat[i] or 0 end
    return flat
end

-- ============================================================
-- Legacy NFPC line decoder (RLE with ~ marker)
-- ============================================================
local function decodeLegacyLine(line, mode, stats)
    local pixelLen = (mode == 256) and 2 or 1
    local row = {}
    local decode
    if mode == 256 then
        decode = function(s)
            local v = tonumber(s, 16)
            if v == nil then if stats then stats.bad = stats.bad + 1 end; return 0 end
            return v
        end
    else
        decode = function(s)
            local v = NFP32_MAP[s:lower()]
            if v == nil then if stats then stats.bad = stats.bad + 1 end; return 0 end
            return v
        end
    end
    local i = 1
    while i <= #line do
        if line:sub(i, i) == "~" then
            i = i + 1
            local ps = line:sub(i, i + pixelLen - 1)
            i = i + pixelLen
            local cnt = tonumber(line:sub(i, i + 1), 16) or 1
            i = i + 2
            local v = decode(ps)
            for _ = 1, cnt do row[#row + 1] = v end
        else
            row[#row + 1] = decode(line:sub(i, i + pixelLen - 1))
            i = i + pixelLen
        end
    end
    return row
end
image.decodeLegacyLine = decodeLegacyLine

-- ============================================================
-- C2 row codec (row-level delta)
-- ============================================================
local function unpackC2Row(payload, mode, width, stats)
    local bytes = image.base64Bytes(payload)
    local row = {}
    if mode == 256 then
        for i = 1, math.min(width, #bytes) do row[i] = bytes[i] end
    else
        local x = 1
        for i = 1, #bytes do
            local b = bytes[i]
            row[x] = math.floor(b / 16) % 16
            x = x + 1
            if x <= width then row[x] = b % 16; x = x + 1 end
            if x > width then break end
        end
    end
    if #row < width and stats then stats.bad = stats.bad + 1 end
    return fitRow(row, width)
end

local function decodeC2Row(line, mode, width, prevRow, prevFrameRow, stats)
    if line == "=" then return prevRow or blankRow(width)
    elseif line == "^" then return prevFrameRow or blankRow(width)
    elseif line:sub(1, 1) == "!" then return unpackC2Row(line:sub(2), mode, width, stats) end
    return fitRow(decodeLegacyLine(line, mode, stats), width)
end

-- ============================================================
-- C3 / C4 frame codecs (flat delta)
-- ============================================================
local function readBlobFromLines(lines, idx)
    local line = lines[idx] or ""
    if line:sub(1, 1) == "@" then
        local count = tonumber(line:sub(2)) or 0
        local parts = {}
        for i = 1, count do parts[i] = lines[idx + i] or "" end
        return table.concat(parts), idx + count + 1
    end
    return line, idx + 1
end
image.readBlobFromLines = readBlobFromLines

local function decodeRleFrame(bytes, mode, w, h, prevFlat, stats, extended)
    local total = w * h
    local flat = {}
    local pos, i = 1, 1
    while pos <= total and i <= #bytes do
        local cmd = bytes[i] or 0
        i = i + 1
        local op = math.floor(cmd / 64)
        local len = (cmd % 64) + 1
        if extended and cmd == 0xFF then
            local ext = bytes[i] or 0
            i = i + 1
            op = math.floor(ext / 64)
            len = (ext % 64) * 256 + (bytes[i] or 0) + 1
            i = i + 1
        end
        if op == 0 then
            for _ = 1, len do
                flat[pos] = prevFlat and prevFlat[pos] or 0
                pos = pos + 1
                if pos > total then break end
            end
        elseif op == 1 then
            local src = pos - w
            for _ = 1, len do
                flat[pos] = flat[src] or 0
                pos = pos + 1; src = src + 1
                if pos > total then break end
            end
        elseif op == 2 then
            local color = bytes[i] or 0
            i = i + 1
            for _ = 1, len do flat[pos] = color; pos = pos + 1; if pos > total then break end end
        else
            for _ = 1, len do
                flat[pos] = bytes[i] or 0
                i = i + 1; pos = pos + 1
                if pos > total then break end
            end
        end
    end
    if pos <= total and stats then stats.bad = stats.bad + 1 end
    for p = 1, total do
        if flat[p] == nil then flat[p] = 0 end
        if mode ~= 256 then flat[p] = flat[p] % 32 end
    end
    return flatToRows(flat, w, h), flat
end

local function decodeC3FrameBytes(bytes, mode, w, h, prevFlat, stats)
    return decodeRleFrame(bytes, mode, w, h, prevFlat, stats, false)
end

local function decodeC3Frame(payload, mode, w, h, prevFlat, stats)
    return decodeC3FrameBytes(image.base64Bytes(payload), mode, w, h, prevFlat, stats)
end

local function decodeC4FrameFromBytes(bytes, mode, w, h, prevFlat, stats)
    return decodeRleFrame(bytes, mode, w, h, prevFlat, stats, true)
end

local function decodeC4Frame(payload, mode, w, h, prevFlat, stats)
    return decodeC4FrameFromBytes(image.base64Bytes(payload), mode, w, h, prevFlat, stats)
end

-- ============================================================
-- LZSS decompression (for C5/C6)
-- ============================================================
local function lzssDecompress(bytes)
    local out, i = {}, 1
    while i <= #bytes do
        local flags = bytes[i] or 0
        i = i + 1
        local mask = 1
        for _ = 1, 8 do
            if i > #bytes then break end
            if math.floor(flags / mask) % 2 == 1 then
                local b1, b2 = bytes[i] or 0, bytes[i + 1] or 0
                i = i + 2
                local len = math.floor(b1 / 16) + 3
                local dist = ((b1 % 16) * 256 + b2) + 1
                local src = #out - dist + 1
                for _ = 1, len do
                    out[#out + 1] = out[src] or 0
                    src = src + 1
                end
            else
                out[#out + 1] = bytes[i] or 0
                i = i + 1
            end
            mask = mask * 2
        end
    end
    return out
end

local function readVarUint(bytes, idx)
    local value, mul = 0, 1
    while idx <= #bytes do
        local b = bytes[idx] or 0
        idx = idx + 1
        value = value + (b % 128) * mul
        if b < 128 then break end
        mul = mul * 128
    end
    return value, idx
end

local function bytesSlice(bytes, idx, len)
    local out = {}
    for i = 1, len do out[i] = bytes[idx + i - 1] or 0 end
    return out
end

-- ============================================================
-- LZW index decompression (for C6)
-- ============================================================
local function lzwDecompressIndices(bytes, mode, expected, stats)
    local minCodeSize = (mode == 256) and 8 or 5
    local clearCode = 2 ^ minCodeSize
    local eoiCode = clearCode + 1
    local nextCode = eoiCode + 1
    local prefixes, suffixes = {}, {}
    local idx, bitBuffer, bitCount = 1, 0, 0
    local out = {}

    local function reset()
        prefixes, suffixes = {}, {}
        nextCode = eoiCode + 1
    end

    local function readCode()
        while bitCount < 12 and idx <= #bytes do
            bitBuffer = bitBuffer + (bytes[idx] or 0) * (2 ^ bitCount)
            bitCount = bitCount + 8
            idx = idx + 1
        end
        if bitCount < 12 then return nil end
        local code = bitBuffer % 4096
        bitBuffer = math.floor(bitBuffer / 4096)
        bitCount = bitCount - 12
        return code
    end

    local function outputCode(code, extra)
        local stack = {}
        local cur = code
        while cur >= clearCode and prefixes[cur] ~= nil do
            stack[#stack + 1] = suffixes[cur]
            cur = prefixes[cur]
        end
        if cur == nil or cur >= clearCode then
            if stats then stats.bad = stats.bad + 1 end
            cur = 0
        end
        local first = cur % (mode == 256 and 256 or 32)
        out[#out + 1] = first
        for i = #stack, 1, -1 do out[#out + 1] = stack[i] end
        if extra ~= nil then out[#out + 1] = extra end
        return first
    end

    local oldCode, firstChar = nil, nil
    while #out < expected do
        local code = readCode()
        if code == nil then break end
        if code == clearCode then
            reset(); oldCode, firstChar = nil, nil
        elseif code == eoiCode then
            break
        elseif oldCode == nil then
            firstChar = outputCode(code); oldCode = code
        elseif code < nextCode then
            local curFirst = outputCode(code)
            prefixes[nextCode] = oldCode; suffixes[nextCode] = curFirst
            nextCode = nextCode + 1
            oldCode, firstChar = code, curFirst
        elseif code == nextCode then
            local curFirst = outputCode(oldCode, firstChar)
            prefixes[nextCode] = oldCode; suffixes[nextCode] = firstChar or 0
            nextCode = nextCode + 1
            oldCode, firstChar = code, curFirst
        else
            if stats then stats.bad = stats.bad + 1 end
            break
        end
    end
    for i = #out + 1, expected do out[i] = 0 end
    for i = expected + 1, #out do out[i] = nil end
    return out
end

-- ============================================================
-- C5 frames (LZSS stream of C3 frames)
-- ============================================================
local function decodeC5FramesFromBytes(bytes, mode, w, h, frameCount, stats)
    local stream = lzssDecompress(bytes)
    local frames, idx, prevFlat = {}, 1, nil
    for f = 1, frameCount do
        local len
        len, idx = readVarUint(stream, idx)
        local frameBytes = {}
        for i = 1, len do frameBytes[i] = stream[idx] or 0; idx = idx + 1 end
        local rows, flat = decodeC3FrameBytes(frameBytes, mode, w, h, prevFlat, stats)
        frames[f] = rows
        prevFlat = flat
    end
    return frames
end

local function decodeC5Frames(payload, mode, w, h, frameCount, stats)
    return decodeC5FramesFromBytes(image.base64Bytes(payload), mode, w, h, frameCount, stats)
end

-- ============================================================
-- C6 frames (region + LZW, optional LZSS wrapping)
-- ============================================================
local function decodeC6FramesFromBytes(bytes, mode, w, h, frameCount, stats)
    local method = bytes[1] or 0
    local body = {}
    for i = 2, #bytes do body[#body + 1] = bytes[i] end
    local stream = method == 1 and lzssDecompress(body) or body
    local total = w * h
    local frames, idx, prevFlat, prevRows = {}, 1, nil, nil

    for f = 1, frameCount do
        local kind = stream[idx] or 0
        idx = idx + 1
        local flat, rows
        if kind == 0 then
            if prevFlat then flat = prevFlat; rows = prevRows
            else flat = copyFlat(nil, total); rows = flatToRows(flat, w, h) end
        else
            local x, y, rw, rh = 0, 0, w, h
            if kind == 2 or kind == 4 then
                x, idx = readVarUint(stream, idx)
                y, idx = readVarUint(stream, idx)
                rw, idx = readVarUint(stream, idx)
                rh, idx = readVarUint(stream, idx)
            end
            local payloadLen
            payloadLen, idx = readVarUint(stream, idx)
            local frameBytes = bytesSlice(stream, idx, payloadLen)
            idx = idx + payloadLen
            local expected = math.max(0, rw * rh)
            local values = (kind == 1 or kind == 2) and lzwDecompressIndices(frameBytes, mode, expected, stats) or frameBytes
            if kind == 1 or kind == 3 then
                flat = {}
                for i = 1, total do
                    local v = values[i] or 0
                    flat[i] = mode == 256 and v or (v % 32)
                end
            else
                flat = copyFlat(prevFlat, total)
                local p = 1
                for yy = 0, rh - 1 do
                    local base = (y + yy) * w + x + 1
                    for xx = 0, rw - 1 do
                        local at = base + xx
                        if at >= 1 and at <= total then
                            local v = values[p] or 0
                            flat[at] = mode == 256 and v or (v % 32)
                        end
                        p = p + 1
                    end
                end
            end
            rows = flatToRows(flat, w, h)
        end
        frames[f] = rows
        prevFlat, prevRows = flat, rows
    end
    return frames
end

local function decodeC6Frames(payload, mode, w, h, frameCount, stats)
    return decodeC6FramesFromBytes(image.base64Bytes(payload), mode, w, h, frameCount, stats)
end

-- ============================================================
-- C7 codec — high-ratio compression
--   submethod 0: lossless (predictor delta + LZW + LZSS)
--   submethod 1: lossy v1 4x4 block (2 palette colors + 2-bit index) + LZW + LZSS
--   submethod 2: lossless + inter-frame delta (for animations)
--   submethod 3: lossy v2 4x4 block (4 palette colors + 2-bit index, better quality)
-- ============================================================
local function lzwDecompress(bytes, mode, expected, stats)
    return lzwDecompressIndices(bytes, mode, expected, stats)
end

local function decodeC7Frame(bytes, mode, w, h, prevFlat, stats)
    local total = w * h
    -- First byte is the submethod
    local submethod = bytes[1] or 0
    local stream = {}
    for i = 2, #bytes do stream[#stream + 1] = bytes[i] end

    local flat = {}

    if submethod == 0 or submethod == 2 then
        -- Lossless: LZW decompress to get delta indices, then reverse predictor
        local deltas = lzwDecompress(stream, 256, total, stats)
        if submethod == 2 and prevFlat then
            -- Inter-frame delta: add to previous frame
            for i = 1, total do
                local d = deltas[i] or 0
                -- delta is stored as signed (0-127 = positive, 128-255 = negative)
                if d >= 128 then d = d - 256 end
                local v = (prevFlat[i] or 0) + d
                if mode == 256 then
                    v = v % 256
                else
                    v = v % 32
                end
                flat[i] = v
            end
        else
            -- Intra-frame: predictor (delta from left pixel)
            local prev = 0
            for i = 1, total do
                local d = deltas[i] or 0
                if d >= 128 then d = d - 256 end
                local v = prev + d
                if mode == 256 then v = v % 256 else v = v % 32 end
                flat[i] = v
                prev = v
            end
        end
    elseif submethod == 1 then
        -- Lossy 4x4 block (v1): 2 colors (2 bytes) + 16 × 2-bit indices (4 bytes) = 6 bytes/block
        local idx = 1
        local blockW = math.ceil(w / 4)
        local blockH = math.ceil(h / 4)
        for by = 0, blockH - 1 do
            for bx = 0, blockW - 1 do
                if idx + 5 > #stream then break end
                local c0 = stream[idx] or 0
                local c1 = stream[idx + 1] or 0
                idx = idx + 2
                local i0 = stream[idx] or 0
                local i1 = stream[idx + 1] or 0
                local i2 = stream[idx + 2] or 0
                local i3 = stream[idx + 3] or 0
                idx = idx + 4
                local blk = {i0, i1, i2, i3}
                for py = 0, 3 do
                    for px = 0, 3 do
                        local bitIdx = py * 4 + px
                        local byteIdx = math.floor(bitIdx / 4)
                        local bitOff = (3 - (bitIdx % 4)) * 2
                        local code = math.floor((blk[byteIdx + 1] or 0) / (2 ^ bitOff)) % 4
                        local color = code == 0 and c0 or (code == 1 and c1 or
                            (code == 2 and math.floor((c0 + c1) / 2) or 0))
                        local fx = bx * 4 + px
                        local fy = by * 4 + py
                        if fx < w and fy < h then
                            flat[fy * w + fx + 1] = color
                        end
                    end
                end
            end
        end
        for p = 1, total do
            if flat[p] == nil then flat[p] = 0 end
            if mode ~= 256 then flat[p] = flat[p] % 32 end
        end
    elseif submethod == 3 then
        -- Lossy 4x4 block (v2): 4 colors (4 bytes) + 16 × 2-bit indices (4 bytes) = 8 bytes/block
        -- Better quality: 4 exact colors per block instead of 2 + average
        local idx = 1
        local blockW = math.ceil(w / 4)
        local blockH = math.ceil(h / 4)
        for by = 0, blockH - 1 do
            for bx = 0, blockW - 1 do
                if idx + 7 > #stream then break end
                local c0 = stream[idx] or 0
                local c1 = stream[idx + 1] or 0
                local c2 = stream[idx + 2] or 0
                local c3 = stream[idx + 3] or 0
                idx = idx + 4
                local i0 = stream[idx] or 0
                local i1 = stream[idx + 1] or 0
                local i2 = stream[idx + 2] or 0
                local i3 = stream[idx + 3] or 0
                idx = idx + 4
                local blk = {i0, i1, i2, i3}
                local colors = {c0, c1, c2, c3}
                for py = 0, 3 do
                    for px = 0, 3 do
                        local bitIdx = py * 4 + px
                        local byteIdx = math.floor(bitIdx / 4)
                        local bitOff = (3 - (bitIdx % 4)) * 2
                        local code = math.floor((blk[byteIdx + 1] or 0) / (2 ^ bitOff)) % 4
                        local color = colors[code + 1] or 0
                        local fx = bx * 4 + px
                        local fy = by * 4 + py
                        if fx < w and fy < h then
                            flat[fy * w + fx + 1] = color
                        end
                    end
                end
            end
        end
        for p = 1, total do
            if flat[p] == nil then flat[p] = 0 end
            if mode ~= 256 then flat[p] = flat[p] % 32 end
        end
    else
        -- Unknown submethod — fill black
        for p = 1, total do flat[p] = 0 end
    end

    return flatToRows(flat, w, h), flat
end

local function decodeC7FramesFromBytes(bytes, mode, w, h, frameCount, stats)
    local stream = lzssDecompress(bytes)
    local frames, idx, prevFlat = {}, 1, nil
    for f = 1, frameCount do
        local len
        len, idx = readVarUint(stream, idx)
        local frameBytes = {}
        for i = 1, len do frameBytes[i] = stream[idx] or 0; idx = idx + 1 end
        local rows, flat = decodeC7Frame(frameBytes, mode, w, h, prevFlat, stats)
        frames[f] = rows
        prevFlat = flat
    end
    return frames
end

local function decodeC7Frames(payload, mode, w, h, frameCount, stats)
    return decodeC7FramesFromBytes(image.base64Bytes(payload), mode, w, h, frameCount, stats)
end

-- ============================================================
-- C8 codec — composite (per-frame method selection)
--   Envelope: !NFPC w h mode C8 | !NFPA w h mode delay loop frames C8
--   Binary payload (LZSS-wrapped base64):
--     [version:1][flags:1][transIdx:1 if flags&1]
--     per frame: [method:1][varUint len][payload len bytes]
--   Methods:
--     0 SKIP 1 RAW 2 RLE 3 RLE-EXT 4 LZSS 5 LZW 6 LZW+LZSS
--     7 PRED+LZW+LZSS(lossless) 8 4x4-BLOCK(lossy)
--     9 REGION(x,y,rw,rh,innerMethod,varUint innerLen,innerPayload)
--    10 TRANSPARENCY(innerMethod,varUint innerLen,innerPayload; replace transIdx with prev)
-- ============================================================
local function decodeC8Frame(method, payload, mode, w, h, prevFlat, transIdx, stats)
    local total = w * h
    local flat, rows

    if method == 0 then
        flat = copyFlat(prevFlat, total)
        rows = flatToRows(flat, w, h)
    elseif method == 1 then
        flat = {}
        for i = 1, total do
            flat[i] = payload[i] or 0
            if mode ~= 256 then flat[i] = flat[i] % 32 end
        end
        rows = flatToRows(flat, w, h)
    elseif method == 2 then
        rows, flat = decodeRleFrame(payload, mode, w, h, prevFlat, stats, false)
    elseif method == 3 then
        rows, flat = decodeRleFrame(payload, mode, w, h, prevFlat, stats, true)
    elseif method == 4 then
        local stream = lzssDecompress(payload)
        flat = {}
        for i = 1, total do
            flat[i] = stream[i] or 0
            if mode ~= 256 then flat[i] = flat[i] % 32 end
        end
        rows = flatToRows(flat, w, h)
    elseif method == 5 then
        flat = lzwDecompressIndices(payload, mode, total, stats)
        for i = 1, total do
            if mode ~= 256 then flat[i] = flat[i] % 32 end
        end
        rows = flatToRows(flat, w, h)
    elseif method == 6 then
        local stream = lzssDecompress(payload)
        flat = lzwDecompressIndices(stream, mode, total, stats)
        for i = 1, total do
            if mode ~= 256 then flat[i] = flat[i] % 32 end
        end
        rows = flatToRows(flat, w, h)
    elseif method == 7 then
        rows, flat = decodeC7Frame(payload, mode, w, h, nil, stats)
    elseif method == 8 then
        rows, flat = decodeC7Frame(payload, mode, w, h, nil, stats)
    elseif method == 9 then
        local idx = 1
        local rx, ry, rw, rh
        rx, idx = readVarUint(payload, idx)
        ry, idx = readVarUint(payload, idx)
        rw, idx = readVarUint(payload, idx)
        rh, idx = readVarUint(payload, idx)
        local innerMethod = payload[idx] or 1; idx = idx + 1
        local innerLen; innerLen, idx = readVarUint(payload, idx)
        local innerPayload = {}
        for i = 1, innerLen do innerPayload[i] = payload[idx] or 0; idx = idx + 1 end
        local _, regionFlat = decodeC8Frame(innerMethod, innerPayload, mode, rw, rh, nil, transIdx, stats)
        flat = copyFlat(prevFlat, total)
        for yy = 0, rh - 1 do
            local base = (ry + yy) * w + rx + 1
            for xx = 0, rw - 1 do
                local at = base + xx
                if at >= 1 and at <= total then
                    flat[at] = regionFlat[yy * rw + xx + 1] or 0
                end
            end
        end
        rows = flatToRows(flat, w, h)
    elseif method == 10 then
        local idx = 1
        local innerMethod = payload[idx] or 1; idx = idx + 1
        local innerLen; innerLen, idx = readVarUint(payload, idx)
        local innerPayload = {}
        for i = 1, innerLen do innerPayload[i] = payload[idx] or 0; idx = idx + 1 end
        local _, innerFlat = decodeC8Frame(innerMethod, innerPayload, mode, w, h, nil, transIdx, stats)
        flat = innerFlat
        if prevFlat and transIdx then
            for i = 1, total do
                if flat[i] == transIdx then flat[i] = prevFlat[i] or 0 end
            end
        end
        rows = flatToRows(flat, w, h)
    else
        flat = {}
        for i = 1, total do flat[i] = 0 end
        rows = flatToRows(flat, w, h)
    end
    return rows, flat
end

local function decodeC8FramesFromBytes(bytes, mode, w, h, frameCount, stats)
    local stream = lzssDecompress(bytes)
    local idx = 1
    local version = stream[idx] or 1; idx = idx + 1
    local flags = stream[idx] or 0; idx = idx + 1
    local transIdx = nil
    if (flags % 2) == 1 then
        transIdx = stream[idx] or 255; idx = idx + 1
    end
    local frames = {}
    local prevFlat = nil
    for f = 1, frameCount do
        local method = stream[idx] or 0; idx = idx + 1
        local payloadLen; payloadLen, idx = readVarUint(stream, idx)
        local framePayload = {}
        for i = 1, payloadLen do framePayload[i] = stream[idx] or 0; idx = idx + 1 end
        local rows, flat = decodeC8Frame(method, framePayload, mode, w, h, prevFlat, transIdx, stats)
        frames[f] = rows
        prevFlat = flat
    end
    return frames
end

local function decodeC8Frames(payload, mode, w, h, frameCount, stats)
    return decodeC8FramesFromBytes(image.base64Bytes(payload), mode, w, h, frameCount, stats)
end

-- ============================================================
-- Binary format (.nfpc / .nfpa binary)
--   Magic: 0x89 'N' 'F' 'C' (static)  /  0x89 'N' 'F' 'A' (animation)
--   Header: version(1) w(2 LE) h(2 LE) mode(1) codec(1) flags(1)
--           [transIdx(1) if flags&1]
--           NFPA only: frameCount(2 LE) delay(2 LE) loop(1)
--           payloadLen(4 LE)
--   Body: raw LZSS-compressed bytes (no base64, ~33% smaller)
-- ============================================================
local BIN_MAGIC_STATIC  = string.char(0x89, 0x4E, 0x46, 0x43)  -- \x89NFC
local BIN_MAGIC_ANIM    = string.char(0x89, 0x4E, 0x46, 0x41)  -- \x89NFA

local function strToBytes(s)
    local t = {}
    for i = 1, #s do t[i] = s:byte(i) end
    return t
end

local function decodeBinaryStatic(bytes, codecByte, mode, w, h, stats)
    if codecByte == 8 then return decodeC8FramesFromBytes(bytes, mode, w, h, 1, stats)[1] or {}
    elseif codecByte == 7 then return decodeC7FramesFromBytes(bytes, mode, w, h, 1, stats)[1] or {}
    elseif codecByte == 6 then return decodeC6FramesFromBytes(bytes, mode, w, h, 1, stats)[1] or {}
    elseif codecByte == 5 then return decodeC5FramesFromBytes(bytes, mode, w, h, 1, stats)[1] or {}
    elseif codecByte == 4 then return decodeC4FrameFromBytes(bytes, mode, w, h, nil, stats)
    elseif codecByte == 3 then return decodeC3FrameBytes(bytes, mode, w, h, nil, stats)
    end
    return {}
end

local function decodeBinaryAnim(bytes, codecByte, mode, w, h, frameCount, stats)
    if codecByte == 8 then return decodeC8FramesFromBytes(bytes, mode, w, h, frameCount, stats)
    elseif codecByte == 7 then return decodeC7FramesFromBytes(bytes, mode, w, h, frameCount, stats)
    elseif codecByte == 6 then return decodeC6FramesFromBytes(bytes, mode, w, h, frameCount, stats)
    elseif codecByte == 5 then return decodeC5FramesFromBytes(bytes, mode, w, h, frameCount, stats)
    end
    return {}
end

local function readBinaryHeader(data)
    if #data < 11 then return nil end
    local magic = data:sub(1, 4)
    local isAnim, isStatic = magic == BIN_MAGIC_ANIM, magic == BIN_MAGIC_STATIC
    if not isAnim and not isStatic then return nil end
    local pos = 5
    local version = data:byte(pos); pos = pos + 1
    local w = data:byte(pos) + data:byte(pos + 1) * 256; pos = pos + 2
    local h = data:byte(pos) + data:byte(pos + 1) * 256; pos = pos + 2
    local mode = data:byte(pos); pos = pos + 1
    if mode == 0 then mode = 256 end
    local codecByte = data:byte(pos); pos = pos + 1
    local flags = data:byte(pos); pos = pos + 1
    local transIdx = nil
    if (flags % 2) == 1 then transIdx = data:byte(pos); pos = pos + 1 end
    local frameCount, delay, loop = 1, 100, 0
    if isAnim then
        frameCount = data:byte(pos) + data:byte(pos + 1) * 256; pos = pos + 2
        delay = data:byte(pos) + data:byte(pos + 1) * 256; pos = pos + 2
        loop = data:byte(pos); pos = pos + 1
    end
    if pos + 4 > #data then return nil end
    local payloadLen = data:byte(pos) + data:byte(pos + 1) * 256 + data:byte(pos + 2) * 65536 + data:byte(pos + 3) * 16777216
    pos = pos + 4
    local payload = data:sub(pos, pos + payloadLen - 1)
    if #payload < payloadLen then return nil end
    return {
        isAnim = isAnim, w = w, h = h, mode = mode, codec = codecByte,
        flags = flags, transIdx = transIdx,
        frameCount = frameCount, delay = delay, loop = loop,
        bytes = strToBytes(payload),
    }
end

function image.isBinary(path)
    if not path or not fs.exists(path) or fs.isDir(path) then return false end
    local f = fs.open(path, "rb")
    if not f then return false end
    local magic = f.read(4)
    f.close()
    return magic == BIN_MAGIC_STATIC or magic == BIN_MAGIC_ANIM
end

function image.loadBinaryFile(path)
    local f = fs.open(path, "rb")
    if not f then return nil, "Cannot open" end
    local data = f.readAll()
    f.close()
    local hdr = readBinaryHeader(data)
    if not hdr or hdr.isAnim then return nil, "Not a binary NFPC" end
    local stats = {bad = 0}
    local pixels = decodeBinaryStatic(hdr.bytes, hdr.codec, hdr.mode, hdr.w, hdr.h, stats)
    return pixels, hdr.w, hdr.h
end

function image.loadBinaryAnimation(path)
    local f = fs.open(path, "rb")
    if not f then return nil, "Cannot open" end
    local data = f.readAll()
    f.close()
    local hdr = readBinaryHeader(data)
    if not hdr or not hdr.isAnim then return nil, "Not a binary NFPA" end
    local stats = {bad = 0}
    local frames = decodeBinaryAnim(hdr.bytes, hdr.codec, hdr.mode, hdr.w, hdr.h, hdr.frameCount, stats)
    return frames, hdr.w, hdr.h, hdr.delay, hdr.loop
end

function image.parseHeader(line)
    line = tostring(line or "")
    if line:match("^!NFPA") then
        local _, _, w, h, mode, delay, loop, frames, codec = line:find("^!NFPA%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s*(%S*)")
        if w then
            return {kind="NFPA", w=tonumber(w) or 0, h=tonumber(h) or 0, mode=tonumber(mode) or 32,
                    delay=tonumber(delay) or 100, loop=tonumber(loop) or 0, frames=tonumber(frames) or 0, codec=codec or ""}
        end
    elseif line:match("^!NFPC") then
        local _, _, w, h, mode, codec = line:find("^!NFPC%s+(%d+)%s+(%d+)%s+(%d+)%s*(%S*)")
        if w then
            return {kind="NFPC", w=tonumber(w) or 0, h=tonumber(h) or 0, mode=tonumber(mode) or 32, frames=1, codec=codec or ""}
        end
    end
    return nil
end

function image.detect(path)
    if not path or not fs.exists(path) or fs.isDir(path) then return nil end
    -- Try binary first
    local bf = fs.open(path, "rb")
    if bf then
        local magic = bf.read(4)
        bf.close()
        if magic == BIN_MAGIC_STATIC or magic == BIN_MAGIC_ANIM then
            local f2 = fs.open(path, "rb")
            local data = f2.readAll()
            f2.close()
            local hdr = readBinaryHeader(data)
            if hdr then
                return {kind = hdr.isAnim and "NFPA" or "NFPC", w = hdr.w, h = hdr.h,
                        mode = hdr.mode, frames = hdr.frameCount, codec = "C" .. hdr.codec,
                        binary = true}
            end
        end
    end
    -- Text format
    local f = fs.open(path, "r")
    if not f then return nil end
    local first = f.readLine()
    f.close()
    if not first then return nil end
    local header = image.parseHeader(first)
    if header then return header end
    local ext = (path:match("%.([^%.]+)$") or ""):lower()
    if ext == "nfp256" then return {kind="NFP256", w=0, h=0, mode=256, frames=1, codec=""} end
    if ext == "nfp" then return {kind="NFP", w=0, h=0, mode=32, frames=1, codec=""} end
    return {kind="NFP", w=0, h=0, mode=32, frames=1, codec=""}
end

-- ============================================================
-- File reading
-- ============================================================
function image.readLines(path)
    local f = fs.open(path, "r")
    if not f then return nil, "Cannot open: " .. tostring(path) end
    local lines = {}
    while true do
        local line = f.readLine()
        if not line then break end
        lines[#lines + 1] = line
    end
    f.close()
    return lines
end

-- ============================================================
-- Dispatch: parse static NFPC from lines
-- ============================================================
local function parseNfpc(lines, stats)
    local header = lines[1] or ""
    local info = image.parseHeader(header) or {}
    local mode = info.mode or 32
    local w = info.w or 0
    local h = info.h or 0
    local codec = info.codec or ""
    local pixels = {}
    if codec == "C7" then
        local payload = readBlobFromLines(lines, 2)
        pixels = decodeC7Frames(payload, mode, w, h, 1, stats)[1] or {}
    elseif codec == "C8" then
        pixels = decodeC8Frames(readBlobFromLines(lines, 2), mode, w, h, 1, stats)[1] or {}
    elseif codec == "C6" then
        local payload = readBlobFromLines(lines, 2)
        pixels = decodeC6Frames(payload, mode, w, h, 1, stats)[1] or {}
    elseif codec == "C5" then
        local payload = readBlobFromLines(lines, 2)
        pixels = decodeC5Frames(payload, mode, w, h, 1, stats)[1] or {}
    elseif codec == "C4" then
        local payload = readBlobFromLines(lines, 2)
        pixels = decodeC4Frame(payload, mode, w, h, nil, stats)
    elseif codec == "C3" then
        local payload = readBlobFromLines(lines, 2)
        pixels = decodeC3Frame(payload, mode, w, h, nil, stats)
    elseif codec == "C2" then
        local prevRow = nil
        for y = 1, h do
            local row = decodeC2Row(lines[y + 1] or "", mode, w, prevRow, nil, stats)
            pixels[y] = row
            prevRow = row
        end
    else
        for lineIdx = 2, #lines do
            local line = lines[lineIdx]
            if line ~= "" then pixels[#pixels + 1] = decodeLegacyLine(line, mode, stats) end
        end
    end
    return pixels, w, h ~= 0 and h or #pixels
end

-- ============================================================
-- Dispatch: parse animation NFPA from lines
-- ============================================================
local function parseNfpa(lines, stats)
    local header = lines[1] or ""
    local info = image.parseHeader(header) or {}
    local mode = info.mode or 32
    local w = info.w or 0
    local h = info.h or 0
    local frameCount = info.frames or 0
    local codec = info.codec or ""
    local frames = {}
    local idx = 2
    if codec == "C7" then
        local payload; payload, idx = readBlobFromLines(lines, idx)
        frames = decodeC7Frames(payload, mode, w, h, frameCount, stats)
    elseif codec == "C8" then
        local payload; payload, idx = readBlobFromLines(lines, idx)
        frames = decodeC8Frames(payload, mode, w, h, frameCount, stats)
    elseif codec == "C6" then
        local payload; payload, idx = readBlobFromLines(lines, idx)
        frames = decodeC6Frames(payload, mode, w, h, frameCount, stats)
    elseif codec == "C5" then
        local payload; payload, idx = readBlobFromLines(lines, idx)
        frames = decodeC5Frames(payload, mode, w, h, frameCount, stats)
    elseif codec == "C4" then
        local prevFlat = nil
        for f = 1, frameCount do
            local payload; payload, idx = readBlobFromLines(lines, idx)
            local rows, flat = decodeC4Frame(payload, mode, w, h, prevFlat, stats)
            frames[f] = rows; prevFlat = flat
        end
    elseif codec == "C3" then
        local prevFlat = nil
        for f = 1, frameCount do
            local payload; payload, idx = readBlobFromLines(lines, idx)
            local rows, flat = decodeC3Frame(payload, mode, w, h, prevFlat, stats)
            frames[f] = rows; prevFlat = flat
        end
    elseif codec == "C2" then
        local prevFrame = nil
        for f = 1, frameCount do
            local frame = {}
            local prevRow = nil
            for y = 1, h do
                local row = decodeC2Row(lines[idx] or "", mode, w, prevRow, prevFrame and prevFrame[y], stats)
                idx = idx + 1
                frame[y] = row; prevRow = row
            end
            frames[f] = frame; prevFrame = frame
        end
    else
        for f = 1, frameCount do
            local frame = {}
            for y = 1, h do
                local line = lines[idx]; idx = idx + 1
                if line and line ~= "" then frame[y] = decodeLegacyLine(line, mode, stats)
                else frame[y] = {} end
                if w > 0 then fitRow(frame[y], w) end
            end
            frames[f] = frame
        end
    end
    return frames, w, h, info.delay or 100, info.loop or 0
end

-- ============================================================
-- Public API
-- ============================================================

-- Load a static image (.nfp/.nfp256/.nfpc). Returns pixels, w, h.
function image.loadFile(path)
    if not path or not fs.exists(path) then return nil, "File not found" end
    if fs.isDir(path) then return nil, "Path is a directory" end
    -- Try binary format first
    if image.isBinary(path) then
        local ok, px, w, h = pcall(image.loadBinaryFile, path)
        if ok and px then return px, w, h end
        return nil, "Invalid binary NFPC: " .. tostring(w)
    end
    -- Text format
    local lines = image.readLines(path)
    if not lines then return nil, "Cannot read file" end
    local first = lines[1] or ""
    local stats = {bad = 0}
    if first:match("^!NFPC") then
        local ok, px, w, h = pcall(parseNfpc, lines, stats)
        if ok and px then return px, w, h end
        return nil, "Invalid NFPC: " .. tostring(w)
    end
    local ext = (path:match("%.([^%.]+)$") or ""):lower()
    local is256 = ext == "nfp256"
    if ext ~= "nfp256" and ext ~= "nfp" then
        for _, line in ipairs(lines) do
            if line ~= "" then
                if #line % 2 == 0 and line:match("^[0-9a-fA-F]+$") then is256 = true end
                break
            end
        end
    end
    local pixels, maxW = {}, 0
    for _, line in ipairs(lines) do
        if line ~= "" then
            local row = is256 and image.parseNfp256Line(line, stats) or image.parseNfp32Line(line, stats)
            if #row > 0 then pixels[#pixels + 1] = row; maxW = math.max(maxW, #row) end
        end
    end
    if #pixels == 0 then return nil, "Empty image" end
    return pixels, maxW, #pixels
end

-- Load an animation (.nfpa). Returns frames, w, h, delay, loop.
function image.loadAnimation(path)
    if not path or not fs.exists(path) then return nil, "File not found" end
    if fs.isDir(path) then return nil, "Path is a directory" end
    -- Try binary format first
    if image.isBinary(path) then
        local ok, frames, w, h, delay, loop = pcall(image.loadBinaryAnimation, path)
        if ok and frames and #frames > 0 then return frames, w, h, delay or 100, loop or 0 end
        return nil, "Invalid binary NFPA: " .. tostring(frames)
    end
    -- Text format
    local lines = image.readLines(path)
    if not lines then return nil, "Cannot read file" end
    if not (lines[1] or ""):match("^!NFPA") then return nil, "Not an animation" end
    local stats = {bad = 0}
    local ok, frames, w, h, delay, loop = pcall(parseNfpa, lines, stats)
    if ok and frames and #frames > 0 then return frames, w, h, delay or 100, loop or 0 end
    return nil, "Invalid NFPA: " .. tostring(frames)
end

return image
