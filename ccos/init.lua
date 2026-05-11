--[[
    CCOS — Boot Entry Point
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
R.clear()
R.fillRect(10, 10, R.w-20, R.h-20, R.PAL.GRAY)
R.drawW95Raised(10, 10, R.w-20, R.h-20)
R.drawText(14, 14, "CCOS v3.0 — Loading...", R.PAL.DARK_BLUE)
sleep(0.3)

-- Run desktop
_G.desktop.run()

-- Shutdown
R.clear(); R.fillRect(0, 0, R.w, R.h, R.PAL.BLACK)
R.drawText(10, 10, "CCOS shutdown.", R.PAL.WHITE)
