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
            local nfp32 = {
                ['0']=1,['1']=2,['2']=3,['3']=4,['4']=5,['5']=6,['6']=7,['7']=8,
                ['8']=9,['9']=10,['a']=11,['b']=12,['c']=13,['d']=14,['e']=15,['f']=16,
                ['g']=17,['h']=18,['i']=19,['j']=20,['k']=21,['l']=22,['m']=23,['n']=24,
                ['o']=25,['p']=26,['q']=27,['r']=28,['s']=29,['t']=30,['u']=31,['v']=32,
            }
            for i = 1, #line do
                table.insert(row, nfp32[line:sub(i,i)] or 0)
            end
        end
        table.insert(pixels, row)
        w = math.max(w, #row)
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
    local logoPaths = {"/ccos/bootlogo.nfp256", "/ccos/bootlogo.nfp", "/disk/bootlogo.nfp256", "/disk/bootlogo.nfp"}
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
