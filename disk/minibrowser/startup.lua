-- Mini Browser — Diskette Package
-- Place this folder on a diskette (/disk/minibrowser/) and run startup.lua
-- from the CCOS Shell or it auto-installs when inserted.

local program = ...

-- If CCOS API is available, register as a CCOS program
local API = _G.ccos_api
local D = _G._desktop

if API and D then
    -- Running inside CCOS — return program descriptor
    local mod = dofile and loadfile and loadfile("/disk/minibrowser/program.lua")
    if not mod then
        mod = loadfile("program.lua")
    end
    if not mod then return nil, "Cannot load program.lua" end
    return mod()
end

-- Standalone: minimal stubs so program.lua can run without CCOS
if not API then
    _G.ccos_api = {
        window = function(title, x, y, w, h)
            local win = {title=title, x=x, y=y, w=w, h=h, cw=w-6, ch=h-21, onClose=function()end}
            return win
        end,
        close = function(win) if win and win.onClose then win.onClose(win) end end,
        fitWindow = function(w, h) local sw, sh = term.getSize() return math.floor((sw-w)/2), math.floor((sh-h)/2), w, h end,
        getRenderer = function() return _G.ccos_render end,
        getScreenSize = function() return term.getSize() end,
        drawText = function(x, y, text, fg, bg, maxW)
            if maxW then text = text:sub(1, maxW) end
            term.setTextColor(fg or 1)
            if bg then term.setBackgroundColor(bg) end
            term.setCursorPos(x, y)
            term.write(text)
        end,
        clipText = function(text, w) return tostring(text):sub(1, w) end,
        redrawContent = function(win) end,
        notify = function() end,
        readFile = function(path) local f = fs.open(path, "r") if not f then return nil end local c = f.readAll() f.close() return c end,
        writeFile = function(path, content) local f = fs.open(path, "w") if not f then return false end f.write(content) f.close() return true end,
        ensureDir = function(path) local dir = path:match("^(.*)/") if dir and not fs.exists(dir) then fs.makeDir(dir) end end,
        loadImage = function(path) return nil end,
        setTimeout = function() return 0 end,
        clearTimeout = function() end,
        chooseFile = function() end,
    }
end

if not _G.ccos_render then
    _G.ccos_render = {
        w = term.getSize(),
        h = select(2, term.getSize()),
        PAL = {},
        fillRect = function(x, y, w, h, color)
            if color then term.setBackgroundColor(color) end
            for dy = 0, h - 1 do
                term.setCursorPos(x, y + dy)
                term.write(string.rep(" ", w))
            end
        end,
        drawText = function(x, y, text, fg, bg)
            term.setTextColor(fg or 1)
            if bg then term.setBackgroundColor(bg) end
            term.setCursorPos(x, y)
            term.write(text)
        end,
        drawLine = function(x1, y1, x2, y2, color)
            if y1 == y2 then
                term.setBackgroundColor(color)
                term.setCursorPos(x1, y1)
                term.write(string.rep(" ", x2 - x1 + 1))
            end
        end,
        drawButton = function() end,
        drawButtonText = function() end,
        drawW95Raised = function() end,
        drawW95Sunken = function() end,
        setPixel = function() end,
        clipText = function(text, w) return tostring(text):sub(1, w) end,
        textWidth = function(text) return #tostring(text) end,
    }
end

-- Load and run the browser
local ok, mod = pcall(function()
    if fs.exists("/disk/minibrowser/program.lua") then
        return dofile("/disk/minibrowser/program.lua")
    elseif fs.exists("program.lua") then
        return dofile("program.lua")
    end
    error("program.lua not found")
end)

if not ok then
    print("Mini Browser error: " .. tostring(mod))
    return
end

if type(mod) == "table" and mod.run then
    mod.run()
end
