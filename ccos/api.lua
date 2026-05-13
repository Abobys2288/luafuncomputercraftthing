--[[
    CCOS API — Application Interface v2
    =====================================
    Apps use this to create windows, request redraws, etc.
]]

local R = _G.ccos_render
local api = {}

local function getDesktop()
    return _G.desktop or _G._desktop
end

function api.window(title, cx, cy, cw, ch)
    local desktop = getDesktop()
    if not desktop or not desktop.createWindow then return nil end
    return desktop.createWindow(title, cx, cy, cw, ch)
end

function api.close(win)
    local desktop = getDesktop()
    if desktop and desktop.destroyWindow then desktop.destroyWindow(win) end
end

function api.redraw(win)
    local desktop = getDesktop()
    if desktop and desktop.markDirty then desktop.markDirty() end
end

function api.redrawRect(win, x, y, w, h)
    api.redraw(win)
end

function api.redrawContent(win)
    local desktop = getDesktop()
    if desktop and desktop.markContentDirty then desktop.markContentDirty(win) end
end

function api.getRenderer()
    return _G.ccos_render or R
end

function api.getScreenSize()
    local renderer = api.getRenderer()
    if not renderer then return 0, 0 end
    return renderer.w, renderer.h
end

function api.fitWindow(ww, wh)
    local desktop = getDesktop()
    if desktop and desktop.fitWin then return desktop.fitWin(ww, wh) end
    local sw, sh = api.getScreenSize()
    ww = math.min(ww or 200, math.max(1, sw - 4))
    wh = math.min(wh or 120, math.max(1, sh - 24))
    local x = math.max(1, math.floor((sw - ww) / 2))
    local y = math.max(1, math.floor((sh - 20 - wh) / 2))
    return x, y, ww, wh
end

function api.getWindow(win)
    return win
end

function api.clipText(text, maxW)
    local renderer = api.getRenderer()
    if renderer and renderer.clipText then return renderer.clipText(text, maxW) end
    text = tostring(text or "")
    local maxChars = math.max(0, math.floor((maxW or 0) / 6))
    if #text <= maxChars then return text end
    if maxChars <= 0 then return "" end
    if maxChars <= 2 then return string.rep(".", maxChars) end
    return text:sub(1, maxChars - 2) .. ".."
end

function api.drawText(x, y, text, fg, bg, maxW)
    local renderer = api.getRenderer()
    if not renderer or not renderer.drawText then return end
    if maxW then text = api.clipText(text, maxW) end
    renderer.drawText(x, y, text, fg, bg)
end

function api.drawButton(x, y, w, h, text, pressed)
    local renderer = api.getRenderer()
    if not renderer then return end
    if renderer.drawButtonText then
        renderer.drawButtonText(x, y, w, h, text or "", pressed)
    elseif renderer.drawButton then
        renderer.drawButton(x, y, w, h, pressed)
    end
end

function api.ensureDir(path)
    local dir = path and path:match("(.+)/[^/]+")
    if not dir or dir == "" then return true end
    local build = ""
    for part in dir:gmatch("[^/]+") do
        build = build .. "/" .. part
        if not fs.exists(build) then fs.makeDir(build) end
    end
    return true
end

function api.readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local c = f.readAll(); f.close(); return c
end

function api.writeFile(path, content)
    api.ensureDir(path)
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

function api.showError(title, message)
    local desktop = getDesktop()
    if desktop and desktop.showError then
        desktop.showError(title or "Error", message or "Unknown error")
    end
end

return api
