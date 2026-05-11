--[[
    CCOS API — Application Interface
    ================================
    Apps use this to create windows, request redraws, etc.
    
    Usage in app:
      local api = require("ccos.api")
      local win = api.window("My App", 30, 20, 200, 120)
      win.onDraw = function(w, x, y, w, h) ... end
      win.onKey = function(w, key, char) ... end
      win.onClick = function(w, x, y) ... end
      api.redraw(win)  -- request redraw
      api.redrawRect(win, x, y, w, h)  -- partial redraw
]]

local api = {}
local desktop = _G._desktop

function api.window(title, cx, cy, cw, ch)
    return desktop.createWindow(title, cx, cy, cw, ch)
end

function api.close(win)
    desktop.destroyWindow(win)
end

function api.redraw(win)
    desktop.dirty = true
end

function api.redrawRect(win, x, y, w, h)
    -- Mark specific region dirty (for future optimization)
    desktop.dirty = true
end

function api.getScreenSize()
    return desktop.R.w, desktop.R.h
end

function api.getWindow(win)
    return win
end

function api.readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local c = f.readAll(); f.close(); return c
end

function api.writeFile(path, content)
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(content); f.close(); return true
end

function api.listFiles(path)
    local ok, list = pcall(fs.list, path or "/")
    return ok and list or {}
end

function api.isDir(path)
    return fs.isDir(path)
end

function api.getDir(path)
    if not path or path == "/" then return "/" end
    local parts = {}
    for p in path:gmatch("[^/]+") do table.insert(parts, p) end
    if #parts <= 1 then return "/" end
    table.remove(parts)
    return "/" .. table.concat(parts, "/")
end

function api.getFileName(path)
    if not path or path == "/" then return "" end
    local parts = {}
    for p in path:gmatch("[^/]+") do table.insert(parts, p) end
    return parts[#parts] or ""
end

function api.joinPath(base, name)
    if base == "/" then return "/" .. name end
    return base .. "/" .. name
end

return api
