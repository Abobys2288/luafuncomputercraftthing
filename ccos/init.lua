--[[
    CCOS — Boot Entry Point v3
    ==========================
    Real module loading + progress bar + verbose mode on Space.
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
-- Boot screen rendering
-- ============================================================
local R
local pbw, pbx, pby, cx, cy, ly

local function drawBootFrame(progress)
    R.beginDraw()
    -- Background
    R.fillRect(0, 0, R.w, R.h, R.PAL.W95_DESKTOP)

    -- Logo
    local sq = 18; local gap = 3
    local lx = cx - sq - math.floor(gap / 2)
    R.fillRect(lx, ly, sq, sq, R.PAL.RED)
    R.fillRect(lx + sq + gap, ly, sq, sq, R.PAL.GREEN)
    R.fillRect(lx, ly + sq + gap, sq, sq, R.PAL.BLUE)
    R.fillRect(lx + sq + gap, ly + sq + gap, sq, sq, R.PAL.YELLOW)

    -- Title
    R.drawText(cx - 24, ly + sq * 2 + gap + 10, "CCOS", R.PAL.WHITE, R.PAL.W95_DESKTOP)
    R.drawText(cx - 48, ly + sq * 2 + gap + 22, "Version 3.0", R.PAL.LIGHT_GRAY, R.PAL.W95_DESKTOP)

    -- Progress bar
    R.drawW95Sunken(pbx, pby, pbw, 16)
    if progress > 0 then
        local fillW = math.floor((pbw - 4) * progress)
        R.fillRect(pbx + 2, pby + 2, fillW, 12, R.PAL.W95_TITLE_BLUE)
    end

    R.drawText(cx - 54, pby + 26, "Starting CCOS...", R.PAL.LIGHT_GRAY, R.PAL.W95_DESKTOP)

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
    cy = math.floor(R.h / 2) - 35
    ly = cy
    pbw = math.min(200, R.w - 40)
    pbx = cx - math.floor(pbw / 2)
    pby = ly + 18 * 2 + 3 + 40

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
