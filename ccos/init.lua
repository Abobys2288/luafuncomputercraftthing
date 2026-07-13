--[[
    CCOS — Boot Entry Point v5
    ==========================
    Loads kernel (module system + crash supervisor) first, then render,
    api, desktop. Boot logo decoded via the shared image library.
    On boot failure: shows BSOD and waits — does NOT auto-reboot.
]]

local showLogs = false
local logs = {}

local function addLog(msg)
    logs[#logs + 1] = tostring(msg)
    if #logs > 12 then table.remove(logs, 1) end
end

-- Load kernel very first (it owns require + crash supervisor)
local function loadKernel()
    local fn, err = loadfile("/ccos/kernel.lua")
    if not fn then error("Failed to load kernel: " .. tostring(err)) end
    local kernel = fn()
    kernel.init()
    _G.ccos_kernel = kernel
    addLog("kernel.lua OK")
    return kernel
end

local function loadModule(name)
    local path = "/ccos/" .. name .. ".lua"
    if not fs.exists(path) then error("Module not found: " .. path) end
    local fn, err = loadfile(path)
    if not fn then error("Failed to load " .. name .. ": " .. tostring(err)) end
    return fn()
end

local kernel
local R

-- ============================================================
-- Boot screen rendering
-- ============================================================
local cx, cy, ly, pbw, pbx, pby

local function drawLogo(cx, cy, maxSize)
    local image = _G.ccos_kernel and _G.ccos_kernel.getModule("ccos.image")
    local logoPaths = {
        "/ccos/bootlogo.nfpc", "/ccos/bootlogo.nfp256", "/ccos/bootlogo.nfp",
        "/disk/bootlogo.nfpc", "/disk/bootlogo.nfp256", "/disk/bootlogo.nfp",
    }
    local pixels, imgW, imgH
    if image then
        for _, path in ipairs(logoPaths) do
            if fs.exists(path) then
                pixels, imgW, imgH = image.loadFile(path)
                if pixels then addLog("Logo: " .. path); break end
            end
        end
    end

    if pixels and imgW and imgH and imgW > 0 and imgH > 0 then
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
    R.fillRect(0, 0, R.w, R.h, R.PAL.W95_DESKTOP)

    local logoSize = math.min(64, math.floor(math.min(R.w, R.h) * 0.25))
    local logoH = drawLogo(cx, ly + math.floor(logoSize/2), logoSize)

    local titleY = ly + logoH + 6
    R.drawText(cx - 24, titleY, "CCOS", R.PAL.WHITE, R.PAL.W95_DESKTOP)
    R.drawText(cx - 36, titleY + 10, "Version 5.0", R.PAL.LIGHT_GRAY, R.PAL.W95_DESKTOP)

    local pbTop = titleY + 26
    pbw = math.min(200, R.w - 40)
    pbx = cx - math.floor(pbw / 2)
    pby = pbTop
    R.drawW95Sunken(pbx, pby, pbw, 14)
    if progress > 0 then
        R.fillRect(pbx + 2, pby + 2, math.floor((pbw - 4) * progress), 10, R.PAL.W95_TITLE_BLUE)
    end
    R.drawText(cx - 54, pby + 20, "Starting CCOS...", R.PAL.LIGHT_GRAY, R.PAL.W95_DESKTOP)

    if showLogs then
        R.fillRect(2, 2, R.w - 4, 96, R.PAL.NEAR_BLACK)
        R.drawRect(2, 2, R.w - 4, 96, R.PAL.LIGHT_GRAY)
        for i, line in ipairs(logs) do
            R.drawText(6, 6 + (i-1)*8, line, R.PAL.WHITE, R.PAL.NEAR_BLACK)
        end
        R.drawText(6, 92, "[Space] toggle logs", R.PAL.LIGHT_GRAY, R.PAL.NEAR_BLACK)
    end
    R.endDraw()
end

-- ============================================================
-- Progressive module loading
-- ============================================================
local function bootSequence()
    kernel = loadKernel()

    -- Load shared image library into the registry
    local okImg, image = pcall(loadfile, "/ccos/image.lua")
    if okImg and image then
        local okLoad, imgMod = pcall(image)
        if okLoad then kernel.setModule("ccos.image", imgMod); addLog("image.lua OK") end
    end

    R = loadModule("render")
    _G.ccos_render = R
    kernel.setModule("ccos.render", R)
    R.resetPalette()
    R.init()

    cx = math.floor(R.w / 2)
    cy = math.floor(R.h / 2)
    ly = math.max(8, cy - 50)

    local modules = {
        {"api", "ccos_api", "ccos.api"},
        {"desktop", "desktop", "ccos.desktop"},
    }
    local totalSteps = 20
    local stepPerMod = math.floor(totalSteps / #modules)

    drawBootFrame(0)

    for modIdx, pair in ipairs(modules) do
        local name, globalName, regName = pair[1], pair[2], pair[3]
        local modOk, modResult = pcall(loadModule, name)
        if modOk then
            _G[globalName] = modResult
            kernel.setModule(regName, modResult)
            addLog(name .. ".lua OK")
        else
            addLog("ERR " .. name .. ": " .. tostring(modResult))
            drawBootFrame((modIdx - 1) / #modules)
            sleep(1)
            error(modResult)
        end
        for step = 1, stepPerMod do
            local progress = ((modIdx - 1) * stepPerMod + step) / totalSteps
            drawBootFrame(progress)
            local t = os.startTimer(0.04)
            while true do
                local ev, p1 = os.pullEvent()
                if ev == "timer" and p1 == t then break
                elseif ev == "key" and p1 == keys.space then showLogs = true
                elseif ev == "key_up" and p1 == keys.space then showLogs = false end
            end
        end
    end

    drawBootFrame(1)
    sleep(0.2)

    -- Run desktop (kernel handles crashes inside the main loop)
    _G.desktop.run()

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
        term.clear()
        term.setCursorPos(1, 1)
        print("CCOS boot failure:")
        print(tostring(err))
    end
    -- Wait for user instead of auto-rebooting so they can read the error.
    os.pullEvent("key")
    os.reboot()
end
