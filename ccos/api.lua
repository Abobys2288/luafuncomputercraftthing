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
    local len = api.utf8Len(text)
    if len <= maxChars then return text end
    if maxChars <= 0 then return "" end
    if maxChars <= 2 then return string.rep(".", maxChars) end
    return api.utf8Sub(text, 1, maxChars - 2) .. ".."
end

function api.utf8Chars(text)
    local renderer = api.getRenderer()
    if renderer and renderer.utf8Chars then return renderer.utf8Chars(text) end
    text = tostring(text or "")
    local chars = {}
    local i = 1
    while i <= #text do
        local b = text:byte(i) or 0
        local len = 1
        if b >= 240 then len = 4
        elseif b >= 224 then len = 3
        elseif b >= 192 then len = 2 end
        table.insert(chars, text:sub(i, i + len - 1))
        i = i + len
    end
    return chars
end

function api.utf8Len(text)
    local renderer = api.getRenderer()
    if renderer and renderer.utf8Len then return renderer.utf8Len(text) end
    return #api.utf8Chars(text)
end

function api.utf8Pop(text)
    local renderer = api.getRenderer()
    if renderer and renderer.utf8Pop then return renderer.utf8Pop(text) end
    local chars = api.utf8Chars(text)
    table.remove(chars)
    return table.concat(chars)
end

function api.utf8CharAt(text, pos)
    local renderer = api.getRenderer()
    if renderer and renderer.utf8CharAt then return renderer.utf8CharAt(text, pos) end
    local chars = api.utf8Chars(text)
    return chars[pos] or ""
end

function api.utf8Insert(text, pos, ch)
    local renderer = api.getRenderer()
    if renderer and renderer.utf8Insert then return renderer.utf8Insert(text, pos, ch) end
    local chars = api.utf8Chars(text)
    table.insert(chars, pos, tostring(ch or ""))
    return table.concat(chars)
end

function api.utf8Remove(text, pos)
    local renderer = api.getRenderer()
    if renderer and renderer.utf8Remove then return renderer.utf8Remove(text, pos) end
    local chars = api.utf8Chars(text)
    if pos < 1 or pos > #chars then return text end
    table.remove(chars, pos)
    return table.concat(chars)
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

function api.chooseFile(options, callback)
    if type(options) == "function" then callback = options; options = {} end
    options = options or {}
    local desktop = getDesktop()
    local R2 = api.getRenderer()
    if not desktop or not R2 then
        if callback then callback(nil) end
        return nil
    end

    local path = options.path or "/"
    local title = options.title or "Choose File"
    local extensions = options.extensions or options.ext
    local allowDirs = options.allowDirs == true
    local sel, scroll = 1, 0
    local items = {}
    local status = "Select file"

    local function allowed(name, isDir)
        if isDir then return true end
        if not extensions then return true end
        local ext = (name:match("%.([^%.]+)$") or ""):lower()
        for _, want in ipairs(extensions) do
            want = tostring(want):lower():gsub("^%.", "")
            if ext == want then return true end
        end
        return false
    end

    local function refresh()
        local ok, list = pcall(fs.list, path)
        if not ok or not list then path = "/"; list = fs.list("/") or {}; status = "Reset to /" end
        table.sort(list, function(a, b)
            local ap, bp = api.joinPath(path, a), api.joinPath(path, b)
            local ad, bd = fs.isDir(ap), fs.isDir(bp)
            if ad ~= bd then return ad end
            return a:lower() < b:lower()
        end)
        items = {}
        if path ~= "/" then table.insert(items, {name="..", up=true, dir=true}) end
        for _, name in ipairs(list) do
            local fp = api.joinPath(path, name)
            local isDir = fs.isDir(fp)
            if allowed(name, isDir) then table.insert(items, {name=name, dir=isDir}) end
        end
        if #items == 0 then items = {{name="(empty)", empty=true}} end
        sel = math.max(1, math.min(sel, #items))
        scroll = math.max(0, math.min(scroll, math.max(0, #items - 1)))
    end

    local wx, wy, ww, wh = api.fitWindow(options.w or 260, options.h or 170)
    local win = api.window(title, wx, wy, ww, wh)
    if not win then if callback then callback(nil) end; return nil end

    local function done(value)
        api.close(win)
        if callback then callback(value) end
    end

    local function selectedPath()
        local it = items[sel]
        if not it or it.empty then return nil, it end
        if it.up then return api.getDir(path), it end
        return api.joinPath(path, it.name), it
    end

    local function activate()
        local fp, it = selectedPath()
        if not fp or not it then return end
        if it.up or fs.isDir(fp) then
            if allowDirs and not it.up and options.pickDirs then done(fp); return end
            path = fp
            sel, scroll = 1, 0
            refresh()
            api.redrawContent(win)
        else
            done(fp)
        end
    end

    refresh()

    win.onDraw = function(_, cx, cy, cw, ch)
        if R2.drawButtonText then R2.drawButtonText(cx, cy, 38, 14, "Open", false)
        else R2.drawButton(cx, cy, 38, 14, false); api.drawText(cx+4, cy+3, "Open", 0, 2, 30) end
        if cw >= 84 then
            if R2.drawButtonText then R2.drawButtonText(cx + 42, cy, 38, 14, "Cancel", false)
            else R2.drawButton(cx+42, cy, 38, 14, false); api.drawText(cx+46, cy+3, "Cancel", 0, 2, 30) end
        end
        if cw >= 128 then api.drawText(cx + 86, cy + 3, status, 4, 2, cw - 90) end

        R2.drawW95Sunken(cx, cy + 18, math.max(8, cw), 14)
        api.drawText(cx + 4, cy + 21, path, 0, 2, cw - 8)

        local listY = cy + 38
        local rows = math.max(1, math.floor((ch - 52) / 8))
        for i = 1, rows do
            local idx = scroll + i
            local it = items[idx]
            if not it then break end
            local iy = listY + (i - 1) * 8
            local active = idx == sel
            if active then R2.fillRect(cx + 2, iy, cw - 4, 8, 19) end
            local prefix = it.up and "^ " or (it.dir and "[] " or "   ")
            api.drawText(cx + 6, iy, prefix .. it.name, active and 1 or 0, active and 19 or 2, cw - 12)
        end

        api.drawText(cx + 4, cy + ch - 10, "Enter=open  Backspace=up  Esc=cancel", 4, 2, cw - 8)
    end

    win.onClick = function(_, mx, my)
        if my >= 0 and my < 14 then
            if mx < 38 then activate()
            elseif mx >= 42 and mx < 80 then done(nil) end
            return
        end
        local rows = math.max(1, math.floor((win.ch - 21 - 52) / 8))
        for i = 1, rows do
            local iy = 38 + (i - 1) * 8
            if my >= iy and my < iy + 8 then
                sel = math.min(#items, scroll + i)
                api.redrawContent(win)
                return
            end
        end
    end

    win.onDoubleClick = function()
        activate()
    end

    win.onKey = function(_, k)
        local rows = math.max(1, math.floor((win.ch - 21 - 52) / 8))
        if k == keys.enter then activate()
        elseif k == keys.escape then done(nil)
        elseif k == keys.backspace then path = api.getDir(path); sel, scroll = 1, 0; refresh(); api.redrawContent(win)
        elseif k == keys.up and sel > 1 then sel = sel - 1; if sel <= scroll then scroll = math.max(0, scroll - 1) end; api.redrawContent(win)
        elseif k == keys.down and sel < #items then sel = sel + 1; if sel > scroll + rows then scroll = scroll + 1 end; api.redrawContent(win)
        elseif k == keys.pageUp then sel = math.max(1, sel - rows); scroll = math.max(0, scroll - rows); api.redrawContent(win)
        elseif k == keys.pageDown then sel = math.min(#items, sel + rows); scroll = math.min(math.max(0, #items - rows), scroll + rows); api.redrawContent(win)
        end
    end

    win.onScroll = function(_, dir)
        local rows = math.max(1, math.floor((win.ch - 21 - 52) / 8))
        local maxScroll = math.max(0, #items - rows)
        if dir < 0 then scroll = math.max(0, scroll - 3)
        else scroll = math.min(maxScroll, scroll + 3) end
        sel = math.max(1, math.min(#items, math.max(sel, scroll + 1)))
        api.redrawContent(win)
    end

    return win
end

function api.showError(title, message)
    local desktop = getDesktop()
    if desktop and desktop.showError then
        desktop.showError(title or "Error", message or "Unknown error")
    end
end

function api.notify(title, message, tone, duration)
    local desktop = getDesktop()
    if desktop and desktop.notify then
        desktop.notify(title or "CCOS", message or "", tone, duration)
    end
end

function api.listThemes()
    local desktop = getDesktop()
    local names = {}
    if desktop and desktop.themes then
        for name in pairs(desktop.themes) do names[#names + 1] = name end
        table.sort(names)
    end
    return names
end

function api.getThemeName()
    local desktop = getDesktop()
    return (desktop and desktop.themeName) or "classic"
end

function api.setTheme(name)
    local desktop = getDesktop()
    if desktop and desktop.applyTheme then return desktop.applyTheme(name) end
    return nil
end

function api.getCrashLogPath()
    local desktop = getDesktop()
    return (desktop and desktop.crashLogPath) or "/ccos/logs/crashes.log"
end

return api
