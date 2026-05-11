--[[
    CCOS — Boot Entry Point
    ========================
    Run this file to start the OS:
      lua ccos/init.lua
    Or from shell:
      ccos/init
]]

-- Set up package path
local ccosPath = shell.resolve("/ccos")
if not shell.path():find("ccos") then
    shell.setPath(shell.path() .. ":/ccos")
end

-- Load modules
local ok, err = pcall(function()
    _G.kernel = require("ccos.kernel")
    _G.gui = require("ccos.gui")
    _G.desktop = require("ccos.desktop")
    _G.fm = require("ccos.files")
end)

if not ok then
    print("CCOS boot error:")
    print(err)
    print("")
    print("Make sure all CCOS files are in /ccos/")
    return
end

-- Initialize
kernel.initDisplay()
kernel.detectModems()
gui.setDisplay(kernel.display, kernel.w, kernel.h)

-- Boot screen
kernel.clear()
kernel.setColors(kernel.C.CYAN, kernel.C.BLACK)
kernel.writeAt(1, 1, "CCOS v1.0 — Booting...")
kernel.resetColors()
sleep(0.5)

-- Main loop
local running = true
while running do
    local result = desktop.show()

    if result == "quit" or result == "shutdown" then
        running = false
    elseif result == "reboot" then
        kernel.clear()
        kernel.writeAt(1, 1, "Rebooting...")
        sleep(0.5)
        os.reboot()
    elseif result == "files" then
        fm.currentPath = "/"
        fm.open()
    elseif result == "edit" then
        desktop.runEditor()
    elseif result == "settings" then
        desktop.showSettings()
    elseif result == "shell" then
        desktop.runShell()
    else
        running = false
    end
end

-- Shutdown
kernel.clear()
kernel.resetColors()
print("CCOS shutdown. Goodbye!")
