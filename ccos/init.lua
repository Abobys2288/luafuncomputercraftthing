--[[
    CCOS — Boot Entry Point
    ========================
    Run: ccos/init
]]

local function loadModule(name)
    local path = "/ccos/" .. name .. ".lua"
    if not fs.exists(path) then
        error("Module not found: " .. path)
    end
    local fn, err = loadfile(path)
    if not fn then
        error("Failed to load " .. name .. ": " .. tostring(err))
    end
    return fn()
end

local ok, err = pcall(function()
    _G.kernel = loadModule("kernel")
    _G.desktop = loadModule("desktop")
end)

if not ok then
    print("CCOS boot error:")
    print(err)
    print("")
    print("Make sure all CCOS files are in /ccos/")
    return
end

-- Initialize display
kernel.initDisplay()

-- Boot screen
kernel.clear()
kernel.fillRect(10, 10, kernel.w - 20, kernel.h - 20, kernel.PAL.GRAY)
kernel.drawW95Raised(10, 10, kernel.w - 20, kernel.h - 20)
kernel.drawPixelText(14, 14, "CCOS v2.0 — Loading...", kernel.PAL.DARK_BLUE)
sleep(0.5)

-- Run desktop
desktop.run()

-- Shutdown
kernel.clear()
kernel.fillRect(0, 0, kernel.w, kernel.h, kernel.PAL.BLACK)
kernel.drawPixelText(10, 10, "CCOS shutdown. Goodbye!", kernel.PAL.WHITE)
