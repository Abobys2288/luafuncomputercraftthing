--[[
    CCOS — Boot Entry Point v4
    ==========================
    Real module loading + custom boot logo + progress bar + verbose mode on Space.
]]

local logs = {}
local showLogs = false

local function addLog(msg)
    table.insert(logs, msg)
    if #logs > 10 then table.remove(logs, 1) end
end

local function loadModule(name)
    local path = "/ccos/" .. name .. ".lua"
    if not fs.exists(path) then error("Module not found: " .. path) end
    local fn, err = loadfile(path)
    if not fn then error("Failed to load " .. name .. ": " .. tostring(err)) end
    return fn()
end

-- ============================================================
-- Boot Logo Loader
-- ============================================================
local function loadLogoPixels(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local pixels = {}
    local w = 0
    local ext = path:match("%.([^%.]+)$") or ""
    local nfp32 = {
        ['0']=0,['1']=1,['2']=2,['3']=3,['4']=4,['5']=5,['6']=6,['7']=7,
        ['8']=8,['9']=9,['a']=10,['b']=11,['c']=12,['d']=13,['e']=14,['f']=15,
        ['g']=16,['h']=17,['i']=18,['j']=19,['k']=20,['l']=21,['m']=22,['n']=23,
        ['o']=24,['p']=25,['q']=26,['r']=27,['s']=28,['t']=29,['u']=30,['v']=31,
    }
    local b64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local b64 = {}
    for i = 1, #b64Chars do b64[b64Chars:sub(i, i)] = i - 1 end

    local function base64Bytes(text)
        local out, i = {}, 1
        while i <= #text do
            local c1 = b64[text:sub(i, i)] or 0
            local c2 = b64[text:sub(i + 1, i + 1)] or 0
            local c3s, c4s = text:sub(i + 2, i + 2), text:sub(i + 3, i + 3)
            local c3, c4 = b64[c3s] or 0, b64[c4s] or 0
            local n = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
            out[#out + 1] = math.floor(n / 65536) % 256
            if c3s ~= "=" and c3s ~= "" then out[#out + 1] = math.floor(n / 256) % 256 end
            if c4s ~= "=" and c4s ~= "" then out[#out + 1] = n % 256 end
            i = i + 4
        end
        return out
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

    local function decodeLegacyLine(line, mode)
        local pixelLen = (mode == 256) and 2 or 1
        local row, i = {}, 1
        local decode = mode == 256
            and function(s) return tonumber(s, 16) or 0 end
            or function(s) return nfp32[s] or 0 end
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

    local function unpackC2Row(payload, mode, width)
        local bytes = base64Bytes(payload)
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
        return fitRow(row, width)
    end

    local function decodeC2Row(line, mode, width, prevRow)
        if line == "=" then return prevRow or blankRow(width) end
        if line:sub(1, 1) == "!" then return unpackC2Row(line:sub(2), mode, width) end
        return fitRow(decodeLegacyLine(line, mode), width)
    end

    local function readC3Blob()
        local marker = f.readLine() or ""
        if marker:sub(1, 1) == "@" then
            local count = tonumber(marker:sub(2)) or 0
            local parts = {}
            for i = 1, count do parts[i] = f.readLine() or "" end
            return table.concat(parts)
        end
        return marker
    end

    local function decodeC3Frame(payload, mode, width, height)
        local bytes = base64Bytes(payload)
        local total = width * height
        local flat, pos, i = {}, 1, 1
        while pos <= total and i <= #bytes do
            local cmd = bytes[i] or 0
            i = i + 1
            local op = math.floor(cmd / 64)
            local len = (cmd % 64) + 1
            if op == 1 then
                local src = pos - width
                for _ = 1, len do flat[pos] = flat[src] or 0; pos = pos + 1; src = src + 1; if pos > total then break end end
            elseif op == 2 then
                local color = bytes[i] or 0
                i = i + 1
                for _ = 1, len do flat[pos] = color; pos = pos + 1; if pos > total then break end end
            elseif op == 3 then
                for _ = 1, len do flat[pos] = bytes[i] or 0; i = i + 1; pos = pos + 1; if pos > total then break end end
            else
                for _ = 1, len do flat[pos] = 0; pos = pos + 1; if pos > total then break end end
            end
        end
        for p = 1, total do
            if flat[p] == nil then flat[p] = 0 end
            if mode ~= 256 then flat[p] = flat[p] % 32 end
        end
        local rows, p = {}, 1
        for y = 1, height do
            local row = {}
            for x = 1, width do row[x] = flat[p] or 0; p = p + 1 end
            rows[y] = row
        end
        return rows
    end

    if ext == "nfpc" then
        local header = f.readLine()
        if not header or not header:match("^!NFPC") then f.close(); return nil end
        local _, _, wStr, hStr, modeStr, codec = header:find("^!NFPC%s+(%d+)%s+(%d+)%s+(%d+)%s*(%S*)")
        local imgH = tonumber(hStr) or 0
        w = tonumber(wStr) or 0
        local mode = tonumber(modeStr) or 32
        if codec == "C3" then
            pixels = decodeC3Frame(readC3Blob(), mode, w, imgH)
        elseif codec == "C2" then
            local prevRow = nil
            for y = 1, imgH do
                local row = decodeC2Row(f.readLine() or "", mode, w, prevRow)
                pixels[y] = row
                prevRow = row
            end
        else
            while true do
                local line = f.readLine()
                if not line then break end
                local row = decodeLegacyLine(line, mode)
                table.insert(pixels, row)
                w = math.max(w, #row)
            end
        end
    else
        while true do
            local line = f.readLine()
            if not line then break end
            local row = {}
            if ext == "nfp256" then
                for i = 1, #line, 2 do
                    local hex = line:sub(i, i+1)
                    local val = tonumber(hex, 16) or 0
                    table.insert(row, val)
                end
            else
                for i = 1, #line do
                    table.insert(row, nfp32[line:sub(i,i)] or 0)
                end
            end
            table.insert(pixels, row)
            w = math.max(w, #row)
        end
    end
    f.close()
    return pixels, w, #pixels
end

-- ============================================================
-- Boot screen rendering
-- ============================================================
local R
local pbw, pbx, pby, cx, cy, ly

local function drawLogo(R, cx, cy, maxSize)
    -- Try to load custom boot logo
    local logoPaths = {"/ccos/bootlogo.nfpc", "/ccos/bootlogo.nfp256", "/ccos/bootlogo.nfp", "/disk/bootlogo.nfpc", "/disk/bootlogo.nfp256", "/disk/bootlogo.nfp"}
    local pixels, imgW, imgH
    for _, path in ipairs(logoPaths) do
        pixels, imgW, imgH = loadLogoPixels(path)
        if pixels then addLog("Logo: " .. path); break end
    end

    if pixels and imgW > 0 and imgH > 0 then
        -- Scale to fit maxSize
        local scale = math.min(maxSize / imgW, maxSize / imgH)
        if scale < 1 then scale = 1 end
        local drawW = math.floor(imgW * scale)
        local drawH = math.floor(imgH * scale)
        local dx = cx - math.floor(drawW / 2)
        local dy = cy - math.floor(drawH / 2)
        for y = 1, imgH do
            local row = pixels[y]
            if row then
                for x = 1, imgW do
                    local color = row[x] or 0
                    if scale == 1 then
                        R.setPixel(dx + x, dy + y, color)
                    else
                        R.fillRect(dx + (x-1)*scale, dy + (y-1)*scale, scale, scale, color)
                    end
                end
            end
        end
        return drawH
    end

    -- Fallback: simple CCOS circle logo
    local r = math.min(maxSize / 2, 24)
    for y = -r, r do
        for x = -r, r do
            local d = math.sqrt(x*x + y*y)
            if d <= r then
                local color = R.PAL.W95_TITLE_BLUE
                if d > r - 2 then color = R.PAL.LIGHT_BLUE
                elseif d < r * 0.3 then color = R.PAL.WHITE end
                R.setPixel(math.floor(cx + x), math.floor(cy + y), color)
            end
        end
    end
    R.drawText(cx - 12, cy - 4, "CC", R.PAL.WHITE, R.PAL.W95_TITLE_BLUE)
    return r * 2
end

local function drawBootFrame(progress)
    R.beginDraw()
    -- Background
    R.fillRect(0, 0, R.w, R.h, R.PAL.W95_DESKTOP)

    -- Logo (adaptive size)
    local logoSize = math.min(64, math.floor(math.min(R.w, R.h) * 0.25))
    local logoH = drawLogo(R, cx, ly + math.floor(logoSize/2), logoSize)

    -- Title under logo
    local titleY = ly + logoH + 6
    R.drawText(cx - 24, titleY, "CCOS", R.PAL.WHITE, R.PAL.W95_DESKTOP)
    R.drawText(cx - 36, titleY + 10, "Version 3.0", R.PAL.LIGHT_GRAY, R.PAL.W95_DESKTOP)

    -- Progress bar
    local pbTop = titleY + 26
    pbw = math.min(200, R.w - 40)
    pbx = cx - math.floor(pbw / 2)
    pby = pbTop
    R.drawW95Sunken(pbx, pby, pbw, 14)
    if progress > 0 then
        local fillW = math.floor((pbw - 4) * progress)
        R.fillRect(pbx + 2, pby + 2, fillW, 10, R.PAL.W95_TITLE_BLUE)
    end

    R.drawText(cx - 54, pby + 20, "Starting CCOS...", R.PAL.LIGHT_GRAY, R.PAL.W95_DESKTOP)

    -- Logs (if Space held)
    if showLogs then
        R.fillRect(2, 2, R.w - 4, 90, R.PAL.NEAR_BLACK)
        R.drawRect(2, 2, R.w - 4, 90, R.PAL.LIGHT_GRAY)
        for i, line in ipairs(logs) do
            R.drawText(6, 6 + (i-1)*8, line, R.PAL.WHITE, R.PAL.NEAR_BLACK)
        end
        R.drawText(6, 86, "[Space] toggle logs", R.PAL.LIGHT_GRAY, R.PAL.NEAR_BLACK)
    end

    R.endDraw()
end

-- ============================================================
-- Progressive module loading
-- ============================================================
local function bootSequence()
    R = loadModule("render")
    _G.ccos_render = R
    R.resetPalette()
    R.init()

    -- Layout constants
    cx = math.floor(R.w / 2)
    cy = math.floor(R.h / 2)
    ly = math.max(8, cy - 50)

    addLog("render.lua OK")

    local modules = {
        {"api", "ccos_api"},
        {"desktop", "desktop"},
    }
    local totalSteps = 20
    local stepPerMod = math.floor(totalSteps / #modules)

    drawBootFrame(0)

    for modIdx, pair in ipairs(modules) do
        local name, globalName = pair[1], pair[2]
        local modOk, modResult = pcall(loadModule, name)
        if modOk then
            _G[globalName] = modResult
            addLog(name .. ".lua OK")
        else
            addLog("ERR " .. name .. ": " .. tostring(modResult))
            drawBootFrame((modIdx - 1) / #modules)
            sleep(2)
            error(modResult)
        end

        for step = 1, stepPerMod do
            local progress = ((modIdx - 1) * stepPerMod + step) / totalSteps
            drawBootFrame(progress)

            -- Short event poll to detect Space
            local t = os.startTimer(0.04)
            while true do
                local ev, p1 = os.pullEvent()
                if ev == "timer" and p1 == t then
                    break
                elseif ev == "key" and p1 == keys.space then
                    showLogs = true
                elseif ev == "key_up" and p1 == keys.space then
                    showLogs = false
                end
            end
        end
    end

    -- Final frame
    drawBootFrame(1)
    sleep(0.2)

    -- Custom require() setup
    _G._ccos_require = function(name)
        if _G[name] then return _G[name] end
        local path = name:gsub("%.", "/")
        local candidates = {
            "/" .. path .. ".lua",
            "/" .. path .. "/init.lua",
            "/ccos/" .. path .. ".lua",
            "/ccos/" .. path .. "/init.lua",
        }
        for _, cpath in ipairs(candidates) do
            if fs.exists(cpath) then
                local fn = loadfile(cpath)
                if fn then
                    local ok2, mod = pcall(fn)
                    if ok2 then
                        _G[name] = mod
                        return mod
                    else
                        error("Module " .. name .. " failed: " .. tostring(mod))
                    end
                end
            end
        end
        error("Module not found: " .. name)
    end

    if type(_G.require) ~= "function" then
        _G.require = _G._ccos_require
    else
        local oldReq = _G.require
        _G.require = function(name)
            local ok2, mod = pcall(oldReq, name)
            if ok2 and mod then return mod end
            return _G._ccos_require(name)
        end
    end

    -- Run desktop
    _G.desktop.run()

    -- Shutdown
    R.shutdown()
end

-- ============================================================
-- Run boot
-- ============================================================
local ok, err = pcall(bootSequence)
if not ok then
    if R and R.bsod then
        R.bsod("0xBOOTFAIL", tostring(err))
    else
        print("CCOS boot failure:")
        print(tostring(err))
    end
    os.pullEvent("key")
    os.reboot()
end
