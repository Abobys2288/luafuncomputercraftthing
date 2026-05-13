-- CCOS Program: Image Viewer
-- Views CCOS .nfp (32-color), .nfp256 (256-color hex), .nfpc (compressed), and .nfpa (animation) images.
local API = _G.ccos_api
local D = _G._desktop
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local P = R.PAL

local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,DBLUE=19,RED=11,CYAN=7}
local NFP32_KEYS = "0123456789abcdefghijklmnopqrstuv"
local NFP32_MAP = {}
for i = 1, #NFP32_KEYS do
    NFP32_MAP[NFP32_KEYS:sub(i, i)] = i - 1
end

local function clip(text, w)
    if API and API.clipText then return API.clipText(text, w) end
    if R.clipText then return R.clipText(text, w) end
    return tostring(text or "")
end

local function drawText(x, y, text, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, text, fg, bg, w)
    else R.drawText(x, y, w and clip(text, w) or text, fg, bg) end
end

local function button(x, y, w, text)
    if w <= 0 then return end
    if R.drawButtonText then R.drawButtonText(x, y, w, 14, text, false, K.BLACK, K.GRAY)
    else R.drawButton(x, y, w, 14, false); drawText(x + 4, y + 3, text, K.BLACK, K.GRAY, w - 8) end
end

local function readLines(path)
    local f, err = fs.open(path, "r")
    if not f then return nil, "Cannot open: " .. tostring(err) end
    local lines = {}
    while true do
        local line = f.readLine()
        if not line then break end
        table.insert(lines, line)
    end
    f.close()
    return lines
end

local function looksNfp256(line)
    if not line or #line < 2 or #line % 2 ~= 0 then return false end
    return line:match("^[0-9a-fA-F]+$") ~= nil
end

local function parseNfp256(line, stats)
    local row = {}
    for i = 1, #line, 2 do
        local val = tonumber(line:sub(i, i + 1), 16)
        if val then row[#row + 1] = val else stats.bad = stats.bad + 1 end
    end
    return row
end

local function parseNfp32(line, stats)
    local row = {}
    for i = 1, #line do
        local ch = line:sub(i, i):lower()
        local val = NFP32_MAP[ch]
        if val ~= nil then
            row[#row + 1] = val
        elseif ch == " " then
            row[#row + 1] = 0
        else
            row[#row + 1] = 0
            stats.bad = stats.bad + 1
        end
    end
    return row
end

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_MAP = {}
for i = 1, #B64_CHARS do
    B64_MAP[B64_CHARS:sub(i, i)] = i - 1
end

local function base64Bytes(text)
    local out = {}
    local i = 1
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

local function decodeNfpcLegacyLine(line, mode, stats)
    local pixelLen = (mode == 256) and 2 or 1
    local row = {}
    local decode
    if mode == 256 then
        decode = function(s)
            local v = tonumber(s, 16)
            if v == nil then stats.bad = stats.bad + 1; return 0 end
            return v
        end
    else
        decode = function(s)
            local v = NFP32_MAP[s:lower()]
            if v == nil then stats.bad = stats.bad + 1; return 0 end
            return v
        end
    end

    local i = 1
    while i <= #line do
        local ch = line:sub(i, i)
        if ch == "~" then
            i = i + 1
            local pixelStr = line:sub(i, i + pixelLen - 1)
            i = i + pixelLen
            local countHex = line:sub(i, i + 1)
            i = i + 2
            local count = tonumber(countHex, 16) or 1
            local val = decode(pixelStr)
            for _ = 1, count do
                row[#row + 1] = val
            end
        else
            local pixelStr = line:sub(i, i + pixelLen - 1)
            row[#row + 1] = decode(pixelStr)
            i = i + pixelLen
        end
    end
    return row
end

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

local function unpackC2Row(payload, mode, width, stats)
    local bytes = base64Bytes(payload)
    local row = {}
    if mode == 256 then
        for i = 1, math.min(width, #bytes) do
            row[i] = bytes[i]
        end
    else
        local x = 1
        for i = 1, #bytes do
            local b = bytes[i]
            row[x] = math.floor(b / 16) % 16
            x = x + 1
            if x <= width then
                row[x] = b % 16
                x = x + 1
            end
            if x > width then break end
        end
    end
    if #row < width then stats.bad = stats.bad + 1 end
    return fitRow(row, width)
end

local function decodeC2Row(line, mode, width, prevRow, prevFrameRow, stats)
    if line == "=" then
        return prevRow or blankRow(width)
    elseif line == "^" then
        return prevFrameRow or blankRow(width)
    elseif line:sub(1, 1) == "!" then
        return unpackC2Row(line:sub(2), mode, width, stats)
    end
    return fitRow(decodeNfpcLegacyLine(line, mode, stats), width)
end

local function readC3Blob(lines, idx)
    local line = lines[idx] or ""
    if line:sub(1, 1) == "@" then
        local count = tonumber(line:sub(2)) or 0
        local parts = {}
        for i = 1, count do
            parts[i] = lines[idx + i] or ""
        end
        return table.concat(parts), idx + count + 1
    end
    return line, idx + 1
end

local function decodeC3Frame(payload, mode, w, h, prevFlat, stats)
    local bytes = base64Bytes(payload)
    local total = w * h
    local flat = {}
    local pos, i = 1, 1
    while pos <= total and i <= #bytes do
        local cmd = bytes[i] or 0
        i = i + 1
        local op = math.floor(cmd / 64)
        local len = (cmd % 64) + 1
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
                pos = pos + 1
                src = src + 1
                if pos > total then break end
            end
        elseif op == 2 then
            local color = bytes[i] or 0
            i = i + 1
            for _ = 1, len do
                flat[pos] = color
                pos = pos + 1
                if pos > total then break end
            end
        else
            for _ = 1, len do
                flat[pos] = bytes[i] or 0
                i = i + 1
                pos = pos + 1
                if pos > total then break end
            end
        end
    end
    if pos <= total then stats.bad = stats.bad + 1 end
    for p = 1, total do
        if flat[p] == nil then flat[p] = 0 end
        if mode ~= 256 then flat[p] = flat[p] % 32 end
    end

    local rows = {}
    local p = 1
    for y = 1, h do
        local row = {}
        for x = 1, w do
            row[x] = flat[p] or 0
            p = p + 1
        end
        rows[y] = row
    end
    return rows, flat
end

local function looksNfpc(line)
    return line and line:match("^!NFPC") ~= nil
end

local function looksNfpa(line)
    return line and line:match("^!NFPA") ~= nil
end

local function parseNfpc(lines, stats)
    local header = lines[1] or ""
    local _, _, wStr, hStr, modeStr, codec = header:find("^!NFPC%s+(%d+)%s+(%d+)%s+(%d+)%s*(%S*)")
    if not modeStr then error("Missing NFPC header") end
    local mode = tonumber(modeStr)
    local w = tonumber(wStr) or 0
    local h = tonumber(hStr) or 0

    local pixels = {}
    if codec == "C3" then
        local payload = readC3Blob(lines, 2)
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
            if line ~= "" then
                pixels[#pixels + 1] = decodeNfpcLegacyLine(line, mode, stats)
            end
        end
    end
    return pixels, w, h ~= 0 and h or #pixels
end

local function parseNfpa(lines, stats)
    local header = lines[1] or ""
    local _, _, wStr, hStr, modeStr, delayStr, loopStr, framesStr, codec = header:find("^!NFPA%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s*(%S*)")
    if not framesStr then error("Missing NFPA header") end
    local mode = tonumber(modeStr)
    local w = tonumber(wStr) or 0
    local h = tonumber(hStr)
    local frameCount = tonumber(framesStr)

    local frames = {}
    local idx = 2
    if codec == "C3" then
        local prevFlat = nil
        for f = 1, frameCount do
            local payload
            payload, idx = readC3Blob(lines, idx)
            local rows, flat = decodeC3Frame(payload, mode, w, h, prevFlat, stats)
            frames[f] = rows
            prevFlat = flat
        end
    elseif codec == "C2" then
        local prevFrame = nil
        for f = 1, frameCount do
            local frame = {}
            local prevRow = nil
            for y = 1, h do
                local row = decodeC2Row(lines[idx] or "", mode, w, prevRow, prevFrame and prevFrame[y], stats)
                idx = idx + 1
                frame[y] = row
                prevRow = row
            end
            frames[f] = frame
            prevFrame = frame
        end
    else
        for f = 1, frameCount do
            local frame = {}
            for y = 1, h do
                local line = lines[idx]
                idx = idx + 1
                if line and line ~= "" then
                    frame[y] = decodeNfpcLegacyLine(line, mode, stats)
                else
                    frame[y] = {}
                end
                if w > 0 then fitRow(frame[y], w) end
            end
            frames[f] = frame
        end
    end
    return frames, tonumber(wStr) or 0, tonumber(hStr) or 0, tonumber(delayStr) or 100, tonumber(loopStr) or 0
end

local function appImageViewer(initialPath)
    if not API or not R then return end

    local fp = initialPath
    local pixels, imgW, imgH = {}, 0, 0
    local status = "Open an image file"
    local formatName = ""
    local scale, ox, oy = 1, 0, 0

    -- Animation state
    local animFrames, animFrame, animDelay = {}, 1, 0
    local animTask, animTimer, isAnimation = nil, nil, false

    local function stopAnimation()
        if animTask then
            for i, t in ipairs(D.bgTasks or {}) do
                if t == animTask then
                    table.remove(D.bgTasks, i)
                    break
                end
            end
            animTask = nil
        end
        if animTimer then
            pcall(os.cancelTimer, animTimer)
            animTimer = nil
        end
    end

    local function startAnimation()
        if not isAnimation or #animFrames <= 1 then return end
        if animTask then return end
        animTask = function(e, a, b, c, d)
            if e == "timer" and a == animTimer then
                animFrame = animFrame + 1
                if animFrame > #animFrames then
                    animFrame = 1
                end
                pixels = animFrames[animFrame]
                status = imgW .. "x" .. imgH .. " " .. formatName .. " F" .. animFrame .. "/" .. #animFrames
                API.redrawContent(win)
                animTimer = os.startTimer(animDelay)
            end
        end
        D.bgTasks = D.bgTasks or {}
        table.insert(D.bgTasks, animTask)
        animTimer = os.startTimer(animDelay)
    end

    local function loadImage(path, quiet)
        stopAnimation()
        pixels, imgW, imgH = {}, 0, 0
        formatName = ""
        ox, oy = 0, 0
        animFrames, animFrame, animDelay = {}, 1, 0
        isAnimation = false

        if not path or path == "" then
            fp = nil
            status = "No image selected"
            return false
        end
        fp = path
        if not fs.exists(fp) then
            status = "Not found: " .. fp
            if not quiet then API.showError("Image Viewer", "File not found: " .. fp) end
            return false
        end
        if fs.isDir(fp) then
            status = "Path is a folder"
            if not quiet then API.showError("Image Viewer", "Folder selected: " .. fp) end
            return false
        end

        local lines, err = readLines(fp)
        if not lines then
            status = err
            if not quiet then API.showError("Image Viewer", err) end
            return false
        end

        local ext = (fp:match("%.([^%.]+)$") or ""):lower()
        local is256 = ext == "nfp256"
        local isNfpc = ext == "nfpc"
        local isNfpa = ext == "nfpa"
        if ext ~= "nfp" and ext ~= "nfp256" and ext ~= "nfpc" and ext ~= "nfpa" then
            for _, line in ipairs(lines) do
                if line ~= "" then
                    if looksNfpa(line) then isNfpa = true; break end
                    if looksNfpc(line) then isNfpc = true; break end
                    is256 = looksNfp256(line); break
                end
            end
        end

        local stats = {bad=0}
        if isNfpa then
            local ok, result, fw, fh, delay, loop = pcall(parseNfpa, lines, stats)
            if ok and result and #result > 0 then
                animFrames = result
                animFrame = 1
                pixels = animFrames[1]
                imgW = fw or 0
                imgH = fh or #pixels
                animDelay = (delay or 100) / 1000
                isAnimation = true
                formatName = ((lines[1] or ""):find("C3") and "NFPA C3") or ((lines[1] or ""):find("C2") and "NFPA C2" or "NFPA")
                startAnimation()
            else
                status = "Invalid NFPA: " .. tostring(result)
                if not quiet then API.showError("Image Viewer", status) end
                return false
            end
        elseif isNfpc then
            local ok, result, fw, fh = pcall(parseNfpc, lines, stats)
            if ok and result then
                pixels = result
                imgW = fw or 0
                imgH = fh or #pixels
                formatName = ((lines[1] or ""):find("C3") and "NFPC C3") or ((lines[1] or ""):find("C2") and "NFPC C2" or "NFPC")
            else
                status = "Invalid NFPC: " .. tostring(result)
                if not quiet then API.showError("Image Viewer", status) end
                return false
            end
        else
            formatName = is256 and "256-color" or "32-color"
            for _, line in ipairs(lines) do
                if line ~= "" then
                    local row = is256 and parseNfp256(line, stats) or parseNfp32(line, stats)
                    if #row > 0 then
                        pixels[#pixels + 1] = row
                        imgW = math.max(imgW, #row)
                    end
                end
            end
            imgH = #pixels
        end

        if imgH == 0 or imgW == 0 then
            status = "Empty or invalid image"
            if not quiet then API.showError("Image Viewer", "No pixels found in: " .. fp) end
            return false
        end

        status = imgW .. "x" .. imgH .. " " .. formatName
        if isAnimation then
            status = status .. " F" .. animFrame .. "/" .. #animFrames
        end
        if stats.bad > 0 then status = status .. " (" .. stats.bad .. " bad chars)" end
        return true
    end

    local wx, wy, ww, wh = API.fitWindow(260, 180)
    local win = API.window("Image Viewer", wx, wy, ww, wh)
    if not win then return end

    if fp then
        win.title = "Image: " .. API.getFileName(fp)
        loadImage(fp, true)
    end

    local function maxOffsets(cw, ch)
        local viewW = math.max(1, cw - 4)
        local viewH = math.max(1, ch - 42)
        return math.max(0, imgW - math.floor(viewW / scale)), math.max(0, imgH - math.floor(viewH / scale))
    end

    local function clampPan(cw, ch)
        local maxOX, maxOY = maxOffsets(cw, ch)
        ox = math.max(0, math.min(ox, maxOX))
        oy = math.max(0, math.min(oy, maxOY))
    end

    local function openDialog()
        stopAnimation()
        if API.chooseFile then
            API.chooseFile({title="Open Image", path="/", extensions={"nfp","nfp256","nfpc","nfpa"}}, function(path)
                if path and path ~= "" then
                    if loadImage(path, false) then win.title = "Image: " .. API.getFileName(path) end
                    API.redrawContent(win)
                end
            end)
        else
            D.inputDialog("Open Image", "Path:", fp or "/tools/smile.nfp", function(path)
                if path and path ~= "" then
                    if loadImage(path, false) then win.title = "Image: " .. API.getFileName(path) end
                    API.redrawContent(win)
                end
            end)
        end
    end

    local function drawImageViewport(viewX, viewY, viewW, viewH)
        local maxY = math.min(imgH - oy, math.floor(viewH / scale))
        local maxX = math.min(imgW - ox, math.floor(viewW / scale))
        for y = 1, maxY do
            local row = pixels[y + oy]
            if row then
                local screenY = viewY + (y - 1) * scale
                local x = 1
                while x <= maxX do
                    local color = row[x + ox]
                    if color == nil then
                        x = x + 1
                    else
                        local runEnd = x + 1
                        while runEnd <= maxX and row[runEnd + ox] == color do
                            runEnd = runEnd + 1
                        end
                        R.fillRect(viewX + (x - 1) * scale, screenY, (runEnd - x) * scale, scale, color)
                        x = runEnd
                    end
                end
            end
        end
    end

    win.onDraw = function(_, cx, cy, cw, ch)
        button(cx, cy, math.min(42, cw), "Open")
        if cw >= 78 then button(cx + 46, cy, 28, "+") end
        if cw >= 110 then button(cx + 78, cy, 28, "-") end

        if isAnimation then
            if cw >= 182 then button(cx + 112, cy, 28, "<") end
            if cw >= 214 then button(cx + 144, cy, 28, ">") end
            if cw >= 246 then button(cx + 176, cy, 28, animTask and "||" or "|>") end
            if cw >= 150 then drawText(cx + 210, cy + 3, status, K.DBLUE, K.GRAY, math.max(0, cw - 214)) end
        else
            if cw >= 150 then drawText(cx + 112, cy + 3, status, K.DBLUE, K.GRAY, cw - 116) end
        end

        local viewX, viewY = cx + 2, cy + 24
        local viewW, viewH = math.max(1, cw - 4), math.max(1, ch - 38)
        R.fillRect(viewX, viewY, viewW, viewH, K.BLACK)

        if #pixels == 0 then
            drawText(viewX + 4, viewY + 4, "No image loaded.", K.WHITE, K.BLACK, viewW - 8)
            drawText(viewX + 4, viewY + 16, "Open .nfp/.nfp256/.nfpc/.nfpa", K.LGRAY, K.BLACK, viewW - 8)
            drawText(cx + 4, cy + ch - 10, clip(status, cw - 8), K.DGRAY, K.GRAY)
            return
        end

        clampPan(cw, ch)
        drawImageViewport(viewX, viewY, viewW, viewH)
        drawText(cx + 4, cy + ch - 10, "Scale " .. scale .. "x  " .. status, K.DGRAY, K.GRAY, cw - 8)
    end

    win.onClick = function(_, mx, my)
        if my >= 0 and my < 14 then
            if mx >= 0 and mx < 42 then openDialog()
            elseif mx >= 46 and mx < 74 then scale = math.min(8, scale + 1); API.redrawContent(win)
            elseif mx >= 78 and mx < 106 then scale = math.max(1, scale - 1); API.redrawContent(win)
            elseif isAnimation then
                if mx >= 112 and mx < 140 then
                    animFrame = animFrame - 1
                    if animFrame < 1 then animFrame = #animFrames end
                    pixels = animFrames[animFrame]
                    status = imgW .. "x" .. imgH .. " " .. formatName .. " F" .. animFrame .. "/" .. #animFrames
                    API.redrawContent(win)
                elseif mx >= 144 and mx < 172 then
                    animFrame = animFrame + 1
                    if animFrame > #animFrames then animFrame = 1 end
                    pixels = animFrames[animFrame]
                    status = imgW .. "x" .. imgH .. " " .. formatName .. " F" .. animFrame .. "/" .. #animFrames
                    API.redrawContent(win)
                elseif mx >= 176 and mx < 204 then
                    if animTask then stopAnimation() else startAnimation() end
                    API.redrawContent(win)
                end
            end
        end
    end

    win.onDrag = function(_, dx, dy)
        if #pixels == 0 then return end
        local step = math.max(1, math.floor(3 / scale))
        if dx > 0 then ox = ox - step elseif dx < 0 then ox = ox + step end
        if dy > 0 then oy = oy - step elseif dy < 0 then oy = oy + step end
        API.redrawContent(win)
    end

    win.onScroll = function(_, dir)
        if #pixels == 0 then return end
        local step = math.max(1, math.floor(8 / scale))
        if dir < 0 then oy = oy - step else oy = oy + step end
        API.redrawContent(win)
    end

    win.onKey = function(_, k, ch)
        local step = math.max(1, math.floor(4 / scale))
        if ch == "o" or ch == "O" then openDialog()
        elseif k == keys.escape then API.close(win)
        elseif k == keys.left then ox = ox - step; API.redrawContent(win)
        elseif k == keys.right then ox = ox + step; API.redrawContent(win)
        elseif k == keys.up then oy = oy - step; API.redrawContent(win)
        elseif k == keys.down then oy = oy + step; API.redrawContent(win)
        elseif k == keys.home then ox, oy = 0, 0; API.redrawContent(win)
        elseif k == keys.pageUp then scale = math.min(8, scale + 1); API.redrawContent(win)
        elseif k == keys.pageDown then scale = math.max(1, scale - 1); API.redrawContent(win)
        end
    end

    win.onClose = function()
        stopAnimation()
    end
end

return {name = "Image View", icon = "img", run = appImageViewer}
