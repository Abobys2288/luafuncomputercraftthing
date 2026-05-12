--[[
    CCOS — Boot Entry Point v2
    ==========================
    Beautiful boot screen + optimized init.
]]

local function loadModule(name)
    local path = "/ccos/" .. name .. ".lua"
    if not fs.exists(path) then error("Module not found: " .. path) end
    local fn, err = loadfile(path)
    if not fn then error("Failed to load " .. name .. ": " .. tostring(err)) end
    return fn()
end

local ok, err = pcall(function()
    _G.ccos_render = loadModule("render")
    _G.ccos_api = loadModule("api")
    _G.desktop = loadModule("desktop")
end)

if not ok then
    print("CCOS boot error:")
    print(err)
    return
end

-- Boot screen
local R = _G.ccos_render
R.init()

-- Draw static boot screen elements (with freeze to avoid flicker)
R.beginDraw()
R.clear()

-- Background
R.fillRect(0, 0, R.w, R.h, R.PAL.W95_DESKTOP)

-- Center coordinates
local cx = math.floor(R.w / 2)
local cy = math.floor(R.h / 2) - 35

-- Windows-style logo (4 colored squares)
local sq = 18
local gap = 3
local lx = cx - sq - math.floor(gap / 2)
local ly = cy

-- Red (top-left)
R.fillRect(lx, ly, sq, sq, R.PAL.RED)
-- Green (top-right)
R.fillRect(lx + sq + gap, ly, sq, sq, R.PAL.GREEN)
-- Blue (bottom-left)
R.fillRect(lx, ly + sq + gap, sq, sq, R.PAL.BLUE)
-- Yellow (bottom-right)
R.fillRect(lx + sq + gap, ly + sq + gap, sq, sq, R.PAL.YELLOW)

-- Title text
R.drawText(cx - 24, ly + sq * 2 + gap + 10, "CCOS", R.PAL.WHITE, R.PAL.W95_DESKTOP)
R.drawText(cx - 48, ly + sq * 2 + gap + 22, "Version 3.0", R.PAL.LIGHT_GRAY, R.PAL.W95_DESKTOP)

-- Progress bar frame
local pbw = math.min(200, R.w - 40)
local pbx = cx - math.floor(pbw / 2)
local pby = ly + sq * 2 + gap + 40
R.drawW95Sunken(pbx, pby, pbw, 16)

-- Copyright / loading text
R.drawText(cx - 54, pby + 26, "Starting CCOS...", R.PAL.LIGHT_GRAY, R.PAL.W95_DESKTOP)

R.endDraw()

-- Animate progress bar
local barSteps = math.max(1, math.floor((pbw - 6) / 2))
for i = 1, barSteps do
    R.fillRect(pbx + 2 + (i - 1) * 2, pby + 2, 2, 12, R.PAL.W95_TITLE_BLUE)
    sleep(0.015)
end

sleep(0.3)

-- Run desktop
_G.desktop.run()

-- Shutdown
R.shutdown()
