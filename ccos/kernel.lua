--[[
    CCOS — Operating System for CC:Tweaked
    ======================================
    Modular OS with GUI, windows, file manager, text editor, settings.
    
    Architecture:
      kernel.lua    — core: event loop, process management, display
      gui.lua       — GUI framework: windows, buttons, labels, lists
      desktop.lua   — home screen with app launcher
      files.lua     — file manager
      edit.lua      — text editor
      settings.lua  — system settings
      init.lua      — boot entry point
]]

-- ============================================================
-- KERNEL
-- ============================================================
local kernel = {}

kernel.C = {
    WHITE = 1, BLACK = 8, GRAY = 256, LIGHT_GRAY = 2,
    RED = 16384, YELLOW = 32, GREEN = 8192, CYAN = 512,
    BLUE = 2048, ORANGE = 4, PINK = 128, PURPLE = 1024,
    BROWN = 4096, MAGENTA = 32, LIME = 64,
}

kernel.running = false
kernel.processes = {}
kernel.currentPID = 0
kernel.display = term
kernel.w, kernel.h = term.getSize()
kernel.isColor = term.isColor and term.isColor() or false
kernel.modemSides = {}

-- Peripheral / display detection
function kernel.initDisplay()
    local best = term
    local bw, bh = term.getSize()
    local sides = {"top","bottom","left","right","front","back"}
    for _, s in ipairs(sides) do
        local ok, m = pcall(peripheral.wrap, s)
        if ok and m and m.getSize then
            pcall(function() m.setTextScale(1) end)
            local w, h = m.getSize()
            if w * h > bw * bh then
                best = m; bw = w; bh = h
            end
        end
    end
    kernel.display = best
    kernel.w = bw
    kernel.h = bh
    kernel.isColor = best.isColor and best.isColor() or (term.isColor and term.isColor() or false)
end

function kernel.detectModems()
    kernel.modemSides = {}
    local sides = {"top","bottom","left","right","front","back"}
    for _, s in ipairs(sides) do
        local ok, p = pcall(peripheral.wrap, s)
        if ok and p then
            if p.open then
                table.insert(kernel.modemSides, s)
            end
        end
    end
end

-- Color helpers
function kernel.setColors(fg, bg)
    if not kernel.isColor then return end
    local d = kernel.display
    if d.setTextColor then d.setTextColor(fg) end
    if d.setBackgroundColor then d.setBackgroundColor(bg) end
end

function kernel.resetColors()
    kernel.setColors(kernel.C.WHITE, kernel.C.BLACK)
end

function kernel.clear()
    if kernel.isColor then
        kernel.display.setBackgroundColor(kernel.C.BLACK)
    end
    kernel.display.clear()
    kernel.display.setCursorPos(1, 1)
end

function kernel.writeAt(x, y, text, fg, bg)
    kernel.display.setCursorPos(x, y)
    if fg and bg then
        kernel.setColors(fg, bg)
    elseif fg then
        kernel.setColors(fg, kernel.C.BLACK)
    end
    local w = kernel.w
    if #text > w - x + 1 then
        text = text:sub(1, w - x + 1)
    end
    kernel.display.write(text)
    kernel.resetColors()
end

function kernel.clearLine(y)
    kernel.display.setCursorPos(1, y)
    kernel.display.clearLine()
end

function kernel.fillRect(x, y, w, h, color)
    if not kernel.isColor then return end
    kernel.display.setBackgroundColor(color)
    for row = 0, h - 1 do
        kernel.display.setCursorPos(x, y + row)
        kernel.display.write(string.rep(" ", w))
    end
    kernel.resetColors()
end

function kernel.drawBox(x, y, w, h, fg, bg)
    kernel.setColors(fg, bg)
    -- Top border
    kernel.display.setCursorPos(x, y)
    kernel.display.write("+" .. string.rep("-", w - 2) .. "+")
    -- Sides
    for row = 1, h - 2 do
        kernel.display.setCursorPos(x, y + row)
        kernel.display.write("|" .. string.rep(" ", w - 2) .. "|")
    end
    -- Bottom border
    kernel.display.setCursorPos(x, y + h - 1)
    kernel.display.write("+" .. string.rep("-", w - 2) .. "+")
    kernel.resetColors()
end

-- Process management
function kernel.createProcess(name, fn)
    kernel.currentPID = kernel.currentPID + 1
    local pid = kernel.currentPID
    kernel.processes[pid] = {
        name = name,
        fn = fn,
        pid = pid,
        active = true,
        filter = nil,
    }
    return pid
end

function kernel.killProcess(pid)
    if kernel.processes[pid] then
        kernel.processes[pid].active = false
        kernel.processes[pid] = nil
    end
end

-- Main event loop
function kernel.run()
    kernel.running = true
    while kernel.running do
        local event = {os.pullEventRaw()}
        local eventType = event[1]

        if eventType == "terminate" then
            kernel.running = false
            break
        end

        -- Dispatch to active processes
        for pid, proc in pairs(kernel.processes) do
            if proc.active then
                if proc.filter == nil or proc.filter == eventType then
                    local ok, err = pcall(proc.fn, event)
                    if not ok then
                        -- Process crashed, kill it
                        kernel.processes[pid] = nil
                    end
                end
            end
        end

        -- If no processes, show desktop
        if not next(kernel.processes) then
            kernel.clear()
            kernel.writeAt(1, 1, "CCOS — No programs running. Press any key to open menu.")
            local ev = os.pullEvent("key")
            -- Will be handled by desktop launcher
            break
        end
    end
end

function kernel.shutdown()
    kernel.running = false
    kernel.clear()
    kernel.resetColors()
    print("CCOS shutdown.")
end

-- FS helpers
function kernel.listFiles(path)
    path = path or "/"
    local ok, list = pcall(fs.list, path)
    if ok then return list end
    return {}
end

function kernel.fileExists(path)
    return fs.exists(path)
end

function kernel.isDir(path)
    return fs.isDir(path)
end

function kernel.readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local content = f.readAll()
    f.close()
    return content
end

function kernel.writeFile(path, content)
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(content)
    f.close()
    return true
end

function kernel.deleteFile(path)
    if fs.exists(path) then
        fs.delete(path)
        return true
    end
    return false
end

function kernel.makeDir(path)
    if not fs.exists(path) then
        fs.makeDir(path)
        return true
    end
    return false
end

-- Path helpers
function kernel.getDir(path)
    if not path or path == "/" then return "/" end
    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    if #parts <= 1 then return "/" end
    table.remove(parts)
    return "/" .. table.concat(parts, "/")
end

function kernel.getFileName(path)
    if not path or path == "/" then return "" end
    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    return parts[#parts] or ""
end

function kernel.joinPath(base, name)
    if base == "/" then return "/" .. name end
    return base .. "/" .. name
end

return kernel
