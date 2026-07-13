--[[
    CCOS Kernel — OS core services v5
    ==================================
    Working, non-duplicate core. Provides:
      * Module registry & require() system
      * Crash supervisor — logs + notifies, NEVER reboots on its own
      * Watchdog — auto-closes windows that error repeatedly (rogue apps)
      * Cooperative interrupt flag + force-quit hotkey (Ctrl+Q)
      * Timer registry for cooperative timeouts
      * try() wrapper routing errors to the supervisor

    This module does NOT duplicate render.lua's graphics primitives.
    It is loaded first (before render/desktop) so every later module
    can use kernel.try / kernel.crash / kernel.require.
]]

local kernel = {}

-- ============================================================
-- State
-- ============================================================
kernel.crashLogPath = "/ccos/logs/crashes.log"
kernel.crashCount = 0
kernel._modules = {}
kernel._timers = {}
kernel._interrupted = false
kernel._watchdog = {}      -- [winId] = {errors=, lastAt=, killed=}
kernel.WATCHDOG_THRESHOLD = 8   -- errors before auto-close
kernel.WATCHDOG_WINDOW = 6      -- seconds within which errors accumulate

-- ============================================================
-- Module registry / require
-- ============================================================
local function resolvePath(name)
    local path = name:gsub("%.", "/")
    return {
        "/" .. path .. ".lua",
        "/" .. path .. "/init.lua",
        "/ccos/" .. path .. ".lua",
        "/ccos/" .. path .. "/init.lua",
    }
end

function kernel.require(name)
    if kernel._modules[name] then return kernel._modules[name] end
    for _, cpath in ipairs(resolvePath(name)) do
        if fs.exists(cpath) then
            local fn = loadfile(cpath)
            if fn then
                local ok, mod = pcall(fn)
                if ok then
                    kernel._modules[name] = mod
                    return mod
                end
                error("Module " .. name .. " failed: " .. tostring(mod), 0)
            end
        end
    end
    error("Module not found: " .. name, 0)
end

function kernel.setModule(name, mod)
    kernel._modules[name] = mod
end

function kernel.getModule(name)
    return kernel._modules[name]
end

-- Install kernel.require as global require (kernel registry takes priority,
-- then falls back to the previously installed require for non-CCOS paths).
function kernel.installRequire()
    if type(_G.require) ~= "function" then
        _G.require = kernel.require
    else
        local oldReq = _G.require
        _G.require = function(n)
            if kernel._modules[n] then return kernel._modules[n] end
            local ok, mod = pcall(oldReq, n)
            if ok and mod then
                kernel._modules[n] = mod
                return mod
            end
            return kernel.require(n)
        end
    end
end

-- ============================================================
-- Crash supervisor
-- ============================================================
local function ensureLogDir()
    local dir = kernel.crashLogPath:match("(.+)/[^/]+")
    if not dir or dir == "" or fs.isDir(dir) then return end
    local build = ""
    for part in dir:gmatch("[^/]+") do
        build = build .. "/" .. part
        if not fs.exists(build) then pcall(fs.makeDir, build) end
    end
end

function kernel.logCrash(source, err)
    kernel.crashCount = kernel.crashCount + 1
    pcall(function()
        ensureLogDir()
        local f = fs.open(kernel.crashLogPath, "a")
        if f then
            local stamp = "day " .. tostring(os.day and os.day() or "?") ..
                          " " .. tostring(os.time and os.time() or "?")
            f.writeLine(stamp .. " | " .. tostring(source or "unknown") ..
                        " | " .. tostring(err or "unknown error"))
            f.close()
        end
    end)
end

-- Central crash handler. NEVER reboots. Logs + notifies + optionally
-- shows an error dialog via the desktop (if available).
function kernel.crash(source, err, opts)
    opts = opts or {}
    kernel.logCrash(source, err)
    local title = tostring(opts.title or source or "Application Error")
    local message = tostring(err or "Unknown error")
    local desktop = _G.desktop or _G._desktop
    if desktop then
        local foreground = opts.foreground
        if foreground == nil then
            foreground = desktop.isForegroundWindow and desktop.isForegroundWindow(opts.window)
        end
        if foreground and desktop.showError then
            if desktop._drawing and desktop.queueErrorDialog then
                desktop.queueErrorDialog(title, message)
            else
                desktop.showError(title, message, true)
            end
        elseif desktop.notify then
            desktop.notify("Crash Reporter", tostring(source or "Application") .. " failed", "error", 6)
        end
    end
    return false, err
end

-- pcall wrapper that routes failures to the supervisor.
function kernel.try(label, fn, ...)
    if type(fn) ~= "function" then return false, "not a function" end
    local ok, err = pcall(fn, ...)
    if not ok then
        kernel.crash(label or "unknown", err)
        return false, err
    end
    return true
end

-- ============================================================
-- Watchdog — track per-window errors, auto-close rogue windows
-- ============================================================
function kernel.watchdogTrack(window)
    if not window or not window.id then return false end
    local now = os.clock()
    local wd = kernel._watchdog[window.id]
    if not wd then
        wd = {errors = 0, lastAt = now, killed = false}
        kernel._watchdog[window.id] = wd
    end
    -- Reset counter if last error was long ago (recovered)
    if now - wd.lastAt > kernel.WATCHDOG_WINDOW then
        wd.errors = 0
    end
    wd.errors = wd.errors + 1
    wd.lastAt = now
    window.errors = (window.errors or 0) + 1
    if wd.errors >= kernel.WATCHDOG_THRESHOLD and not wd.killed then
        wd.killed = true
        kernel.logCrash("Watchdog", "Auto-killed window '" ..
            tostring(window.title or "?") .. "' after " .. wd.errors .. " errors")
        local desktop = _G.desktop or _G._desktop
        if desktop and desktop.destroyWindow then
            pcall(desktop.destroyWindow, window)
        end
        if desktop and desktop.notify then
            pcall(desktop.notify, "Watchdog",
                "Closed '" .. tostring(window.title or "?") .. "' (kept crashing)", "error", 6)
        end
        return true
    end
    return false
end

function kernel.watchdogReset(window)
    if window and window.id then kernel._watchdog[window.id] = nil end
end

function kernel.watchdogCleanup(activeIds)
    local seen = {}
    if activeIds then
        for _, id in ipairs(activeIds) do seen[id] = true end
    end
    for id, _ in pairs(kernel._watchdog) do
        if not seen[id] then kernel._watchdog[id] = nil end
    end
end

-- ============================================================
-- Cooperative interrupt
-- ============================================================
function kernel.setInterrupt(flag)
    kernel._interrupted = flag == true
end

function kernel.interrupted()
    return kernel._interrupted
end

-- Force-quit the active window (bound to Ctrl+Q by the desktop).
function kernel.forceQuit()
    local desktop = _G.desktop or _G._desktop
    if desktop and desktop.activeWin then
        local w = desktop.activeWin
        kernel.logCrash("ForceQuit", "User force-quit '" .. tostring(w.title or "?") .. "'")
        if desktop.destroyWindow then pcall(desktop.destroyWindow, w) end
        if desktop.markDirty then pcall(desktop.markDirty) end
        return true
    end
    return false
end

-- Recovery: close all windows, reload programs, keep the shell alive.
function kernel.rescue(reason)
    kernel.logCrash("Rescue", tostring(reason or "manual"))
    local desktop = _G.desktop or _G._desktop
    if not desktop then return false end
    if desktop.windows then
        for i = #desktop.windows, 1, -1 do
            pcall(function() desktop.destroyWindow(desktop.windows[i]) end)
        end
    end
    if desktop.loadPrograms then pcall(desktop.loadPrograms) end
    if desktop.markDirty then pcall(desktop.markDirty) end
    if desktop.notify then
        pcall(desktop.notify, "CCOS", "Recovered from error — all windows closed", "info", 5)
    end
    return true
end

-- ============================================================
-- Timer registry (cooperative timeouts)
-- ============================================================
function kernel.setTimeout(seconds, fn)
    local id = os.startTimer(seconds)
    kernel._timers[id] = fn
    return id
end

function kernel.clearTimeout(id)
    kernel._timers[id] = nil
    pcall(os.cancelTimer, id)
end

-- Called by the desktop main loop on every "timer" event. Returns
-- true if the timer was owned by the kernel.
function kernel.handleTimer(id)
    local fn = kernel._timers[id]
    if fn then
        kernel._timers[id] = nil
        kernel.try("Timer callback", fn)
        return true
    end
    return false
end

-- ============================================================
-- Initialization
-- ============================================================
function kernel.init()
    kernel.installRequire()
    kernel.setModule("ccos.kernel", kernel)
    return kernel
end

return kernel
