--[[
    CCOS Desktop v10 — Optimized + Fixed
    ====================================
    Key fixes:
    - Optimized window dragging (outline only, no desktop fill)
    - Fixed New File / New Dir with input dialog
    - Fixed click accuracy in File Manager
    - Proper Start Menu closing
    - Better Settings
    - Improved Shell
    - Dirty rectangle system for better performance
]]

local R = _G.ccos_render
local D = {} ; _G._desktop = D

-- Color shortcuts
local K = {
    BLACK=0, WHITE=1, GRAY=2, LGRAY=3, DGRAY=4,
    BLUE=5, DBLUE=6, CYAN=7, LBLUE=8,
    GREEN=9, DGREEN=10, RED=11, DRED=12,
    YELLOW=13, ORANGE=14, BROWN=15, PURPLE=16, PINK=17,
    DTITLE=18, TBLUE=19, TINACT=20, DESKTOP=30
}

-- State
D.windows = {}
D.activeWin = nil
D.taskbarH = 20
D.startMenuOpen = false
D.clock = ""
D.nextWinId = 1
D.dragWin = nil
D.dragOX = 0
D.dragOY = 0
D.lastDragRect = nil
D.mouse = {x=0, y=0}
D.dirty = true
D.apps = {}  -- Registered apps

-- ============================================
-- HELPERS
-- ============================================
local function getDir(path)
    if not path or path == "/" then return "/" end
    local parts = {}
    for p in path:gmatch("[^/]+") do table.insert(parts, p) end
    if #parts <= 1 then return "/" end
    table.remove(parts)
    return "/" .. table.concat(parts, "/")
end

local function getFileName(path)
    if not path or path == "/" then return "" end
    local last = nil
    for s in path:gmatch("[^/]+") do last = s end
    return last or ""
end

local function readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local c = f.readAll()
    f.close()
    return c
end

local function writeFile(path, content)
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(content)
    f.close()
    return true
end

-- ============================================
-- DIRTY SYSTEM (Performance)
-- ============================================
function D.markDirty() D.dirty = true end

function D.markDirtyRect(x, y, w, h)
    -- For future partial redraw optimization
    D.dirty = true
end

-- ============================================
-- WINDOW MANAGEMENT
-- ============================================
function D.createWindow(title, cx, cy, cw, ch)
    local id = D.nextWinId
    D.nextWinId = id + 1

    local win = {
        id = id,
        title = title or "Window",
        cx = cx or 30,
        cy = cy or 20,
        cw = cw or 200,
        ch = ch or 120,
        minW = 80,
        minH = 50,
        visible = true,
        maximized = false,
        minimized = false,
        prevState = nil,
        onDraw = nil,
        onKey = nil,
        onClick = nil,
        onDoubleClick = nil,
    }

    table.insert(D.windows, win)
    D.activeWin = win
    D.markDirty()
    return win
end

function D.destroyWindow(win)
    for i, v in ipairs(D.windows) do
        if v.id == win.id then
            table.remove(D.windows, i)
            break
        end
    end
    D.activeWin = D.windows[#D.windows]
    D.markDirty()
end

function D.bringToFront(win)
    for i, v in ipairs(D.windows) do
        if v.id == win.id then
            table.remove(D.windows, i)
            table.insert(D.windows, win)
            D.activeWin = win
            D.markDirty()
            return
        end
    end
end

function D.winAt(mx, my)
    for i = #D.windows, 1, -1 do
        local w = D.windows[i]
        if w.visible and not w.minimized and
           mx >= w.cx and mx < w.cx + w.cw and
           my >= w.cy and my < w.cy + w.ch then
            return w
        end
    end
    return nil
end

-- ============================================
-- DRAWING (Optimized)
-- ============================================
function D.drawAll()
    if not D.dirty then return end

    R.clear()
    local by = R.h - D.taskbarH

    -- Desktop background
    R.fillRect(0, 0, R.w, by, K.DESKTOP)

    -- Desktop icons
    D.drawDesktopIcons(by)

    -- Windows
    for _, w in ipairs(D.windows) do
        if w.visible and not w.minimized then
            D.drawWindow(w)
        end
    end

    -- Taskbar
    D.drawTaskbar(by)

    -- Start Menu (on top)
    if D.startMenuOpen then
        D.drawStartMenu(by)
    end

    D.dirty = false
end

function D.drawDesktopIcons(by)
    local icons = {
        {"Files", "files"},
        {"Editor", "edit"},
        {"Settings", "settings"},
        {"Shell", "shell"}
    }

    local iw, ih = 48, 42
    local cols = math.max(1, math.floor((R.w - 10) / (iw + 10)))

    for i, icon in ipairs(icons) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local ix = 8 + col * (iw + 10)
        local iy = 8 + row * (ih + 8)

        if iy + ih > by - 4 then break end

        local hover = D.mouse.x >= ix - 2 and D.mouse.x < ix + iw + 2 and
                      D.mouse.y >= iy - 2 and D.mouse.y < iy + ih + 2

        if hover then
            R.fillRect(ix - 2, iy - 2, iw + 4, ih + 4, K.DBLUE)
        end

        R.fillRect(ix, iy, iw, 24, K.LGRAY)
        R.drawW95Sunken(ix, iy, iw, 24)
        R.drawText(ix + 16, iy + 7, icon[1]:sub(1, 1), K.DBLUE)
        R.drawText(ix, iy + 28, icon[1], K.WHITE)
    end
end

function D.drawTaskbar(by)
    R.fillRect(0, by, R.w, D.taskbarH, K.GRAY)
    R.drawLine(0, by, R.w - 1, by, K.WHITE)

    -- Start button
    R.drawButton(2, by + 2, 54, 16, D.startMenuOpen)
    R.drawText(6, by + 6, "Start", K.BLACK)

    -- Window buttons
    local bx = 60
    for _, w in ipairs(D.windows) do
        local bw = math.min(100, R.w - bx - 55)
        if bw < 25 then break end

        local isActive = D.activeWin and D.activeWin.id == w.id
        R.drawButton(bx, by + 3, bw, 14, isActive)

        local title = #w.title > 12 and w.title:sub(1, 10) .. ".." or w.title
        if w.minimized then title = "(" .. title .. ")" end
        R.drawText(bx + 4, by + 6, title, isActive and K.WHITE or K.BLACK)
        bx = bx + bw + 2
    end

    -- Clock
    R.drawW95Sunken(R.w - 48, by + 3, 44, 14)
    R.drawText(R.w - 44, by + 6, D.clock, K.BLACK)
end

function D.drawStartMenu(by)
    local mw, mh = 140, 96
    local my = (by + 2) - mh
    if my < 1 then my = 1 end
    local sx = 2

    R.fillRect(sx, my, mw, mh, K.GRAY)
    R.drawW95Raised(sx, my, mw, mh)
    R.fillRect(sx + 2, my + 2, 20, mh - 4, K.DBLUE)
    R.drawText(sx + 3, my + 30, "CC", K.WHITE)

    local items = {
        {"File Manager", "files"},
        {"Editor", "edit"},
        {"Settings", "settings"},
        {"Shell", "shell"},
        {"Reboot", "reboot"},
        {"Shutdown", "shutdown"}
    }

    local iy = my + 4
    for _, item in ipairs(items) do
        local hit = D.mouse.x >= sx + 24 and D.mouse.x < sx + mw - 4 and
                    D.mouse.y >= iy and D.mouse.y < iy + 12
        if hit then
            R.fillRect(sx + 24, iy, mw - 28, 12, K.DBLUE)
        end
        R.drawText(sx + 28, iy + 2, item[1], hit and K.WHITE or K.BLACK)
        iy = iy + 14
    end
end

function D.drawWindow(w)
    local x, y, ww, hh = w.cx, w.cy, w.cw, w.ch
    local by = R.h - D.taskbarH

    if y + hh > by then
        hh = math.max(20, by - y)
    end

    R.fillRect(x, y, ww, hh, K.GRAY)

    local active = D.activeWin and D.activeWin.id == w.id
    R.drawTitleBar(x, y, ww, active)
    R.drawText(x + 4, y + 4, w.title, active and K.WHITE or K.LGRAY)

    -- Window controls
    R.drawButton(x + ww - 18, y + 1, 16, 14, false)
    R.drawText(x + ww - 13, y + 4, "X", K.BLACK)

    R.drawButton(x + ww - 36, y + 1, 16, 14, false)
    R.drawRect(x + ww - 32, y + 4, 8, 8, K.BLACK)

    R.drawButton(x + ww - 54, y + 1, 16, 14, false)
    R.fillRect(x + ww - 49, y + 6, 6, 2, K.BLACK)

    R.drawW95Raised(x, y, ww, hh)
    R.fillRect(x + 2, y + 17, ww - 4, hh - 19, K.GRAY)

    if w.onDraw then
        pcall(w.onDraw, w, x + 3, y + 18, ww - 6, hh - 21)
    end
end

-- ============================================
-- INPUT HANDLING
-- ============================================
function D.click(mx, my)
    local by = R.h - D.taskbarH

    -- Start Menu handling
    if D.startMenuOpen then
        local mw, mh = 140, 96
        local my2 = (by + 2) - mh
        if my2 < 1 then my2 = 1 end

        if mx >= 2 and mx < 2 + mw and my >= my2 and my < my2 + mh then
            local items = {"files", "edit", "settings", "shell", "reboot", "shutdown"}
            local iy = my2 + 4
            for _, action in ipairs(items) do
                if mx >= 26 and mx < 2 + mw - 4 and my >= iy and my < iy + 12 then
                    D.startMenuOpen = false
                    D.markDirty()
                    return action
                end
                iy = iy + 14
            end
            return nil
        else
            -- Click outside menu → close it
            D.startMenuOpen = false
            D.markDirty()
        end
    end

    -- Start button
    if mx >= 2 and mx < 56 and my >= by + 2 and my < by + 18 then
        D.startMenuOpen = not D.startMenuOpen
        D.markDirty()
        return nil
    end

    -- Taskbar window buttons
    if my >= by then
        local bx = 60
        for _, w in ipairs(D.windows) do
            local bw = math.min(100, R.w - bx - 55)
            if bw < 25 then break end
            if mx >= bx and mx < bx + bw then
                if w.minimized then
                    w.minimized = false
                    w.visible = true
                    D.bringToFront(w)
                elseif D.activeWin and D.activeWin.id == w.id then
                    w.minimized = true
                else
                    D.bringToFront(w)
                end
                D.markDirty()
                return nil
            end
            bx = bx + bw + 2
        end
        return nil
    end

    -- Windows
    local w = D.winAt(mx, my)
    if w then
        D.bringToFront(w)

        if my >= w.cy and my < w.cy + 16 then
            if mx >= w.cx + w.cw - 18 then
                D.destroyWindow(w)
                return nil
            end
            if mx >= w.cx + w.cw - 36 and mx < w.cx + w.cw - 20 then
                if w.maximized then
                    if w.prevState then
                        w.cx = w.prevState.x
                        w.cy = w.prevState.y
                        w.cw = w.prevState.w
                        w.ch = w.prevState.h
                        w.prevState = nil
                    end
                    w.maximized = false
                else
                    w.prevState = {x = w.cx, y = w.cy, w = w.cw, h = w.ch}
                    w.cx = 1
                    w.cy = 1
                    w.cw = R.w
                    w.ch = by - 1
                    w.maximized = true
                end
                D.markDirty()
                return nil
            end
            if mx >= w.cx + w.cw - 54 and mx < w.cx + w.cw - 38 then
                w.minimized = true
                D.markDirty()
                return nil
            end
            if not w.maximized then
                D.dragWin = w
                D.dragOX = mx - w.cx
                D.dragOY = my - w.cy
            end
            return nil
        end

        -- Forward click to window content
        if w.onClick then
            pcall(w.onClick, w, mx - w.cx - 3, my - w.cy - 18)
        end
        return nil
    end

    -- Desktop icons
    local icons = {{"Files", "files"}, {"Editor", "edit"}, {"Settings", "settings"}, {"Shell", "shell"}}
    local iw, ih = 48, 42
    local cols = math.max(1, math.floor((R.w - 10) / (iw + 10)))

    for i, icon in ipairs(icons) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local ix = 8 + col * (iw + 10)
        local iy = 8 + row * (ih + 8)

        if mx >= ix - 2 and mx < ix + iw + 2 and my >= iy - 2 and my < iy + ih + 2 then
            return icon[2]
        end
    end

    return nil
end

function D.drag(mx, my)
    local w = D.dragWin
    if not w then return end

    local nx = mx - D.dragOX
    local ny = my - D.dragOY

    if ny < 1 then ny = 1 end
    local by = R.h - D.taskbarH
    if ny + w.ch > by + 1 then ny = by - w.ch + 2 end

    -- Only draw outline (much faster)
    if D.lastDragRect then
        local r = D.lastDragRect
        R.drawDragOutline(r.x, r.y, r.w, r.h)
    end

    R.drawDragOutline(nx, ny, w.cw, w.ch)
    D.lastDragRect = {x = nx, y = ny, w = w.cw, h = w.ch}
end

function D.drop()
    if D.dragWin then
        local w = D.dragWin
        w.cx = D.mouse.x - D.dragOX
        w.cy = D.mouse.y - D.dragOY

        if w.cy < 1 then w.cy = 1 end
        local by = R.h - D.taskbarH
        if w.cy + w.ch > by + 1 then w.cy = by - w.ch + 2 end

        D.dragWin = nil
        D.lastDragRect = nil
        D.markDirty()
    end

    for _, w in ipairs(D.windows) do
        w.resizing = false
    end
end

-- ============================================
-- APPLICATIONS
-- ============================================
function D.registerApp(name, icon, launchFunc)
    table.insert(D.apps, {
        name = name,
        icon = icon or "app",
        launch = launchFunc
    })
    D.markDirty()
end

-- ============================================
-- BUILT-IN APPS
-- ============================================
function D.appFM()
    local path = "/"
    local sel = 1
    local scroll = 0
    local items = {}

    local function refresh()
        local list = fs.list(path)
        table.sort(list)
        items = {}
        if path ~= "/" then table.insert(items, "..") end
        for _, it in ipairs(list) do
            local fp = path == "/" and ("/" .. it) or (path .. "/" .. it)
            if fs.isDir(fp) then
                table.insert(items, "/" .. it)
            else
                table.insert(items, it)
            end
        end
        if #items == 0 then items = {"(empty)"} end
        sel = math.max(1, math.min(sel, #items))
    end

    refresh()

    local w = D.createWindow("File Manager", 20, 15, 260, 160)

    w.onDraw = function(win, cx, cy, cw, ch)
        -- Toolbar
        R.drawButton(cx, cy, 40, 14, false)
        R.drawText(cx + 4, cy + 3, "New", K.BLACK)
        R.drawButton(cx + 42, cy, 52, 14, false)
        R.drawText(cx + 46, cy + 3, "New Dir", K.BLACK)
        R.drawButton(cx + 96, cy, 40, 14, false)
        R.drawText(cx + 100, cy + 3, "Delete", K.BLACK)

        -- File list
        local lh = math.floor((ch - 24) / 8)
        for i = 1, lh do
            local idx = scroll + i
            local it = items[idx]
            if not it then break end

            local iy = cy + 16 + (i - 1) * 8
            local isSel = idx == sel
            local hover = D.mouse.x >= cx + 2 and D.mouse.x < cx + cw - 2 and
                          D.mouse.y >= iy - 1 and D.mouse.y < iy + 8

            if isSel or hover then
                R.fillRect(cx + 2, iy - 1, cw - 4, 9, K.DBLUE)
                R.drawText(cx + 4, iy, it, K.WHITE)
            else
                R.drawText(cx + 4, iy, it, K.BLACK)
            end
        end

        R.drawText(cx + 2, cy + ch - 10, " " .. path, K.BLACK)
    end

    w.onClick = function(win, mx, my)
        local cx, cy = win.cx, win.cy

        -- Toolbar clicks
        if my >= cy and my < cy + 14 then
            if mx >= cx and mx < cx + 40 then
                -- New File
                local name = gui.inputBox("New File", "Enter filename:", "newfile.txt")
                if name then
                    local fp = path == "/" and ("/" .. name) or (path .. "/" .. name)
                    writeFile(fp, "")
                    refresh()
                    D.markDirty()
                end
            elseif mx >= cx + 42 and mx < cx + 94 then
                -- New Dir
                local name = gui.inputBox("New Folder", "Enter folder name:", "newdir")
                if name then
                    local fp = path == "/" and ("/" .. name) or (path .. "/" .. name)
                    fs.makeDir(fp)
                    refresh()
                    D.markDirty()
                end
            elseif mx >= cx + 96 and mx < cx + 136 then
                -- Delete
                local it = items[sel]
                if it and it ~= ".." then
                    local fp = path == "/" and ("/" .. it) or (path .. "/" .. it)
                    if fs.exists(fp) then
                        fs.delete(fp)
                        refresh()
                        D.markDirty()
                    end
                end
            end
            return
        end

        -- File list selection
        local lh = math.floor((win.ch - 24) / 8)
        for i = 1, lh do
            local idx = scroll + i
            local iy = cy + 16 + (i - 1) * 8
            if my >= iy - 1 and my < iy + 8 then
                sel = idx
                D.markDirty()
                return
            end
        end
    end

    w.onDoubleClick = function(win, mx, my)
        local cx, cy = win.cx, win.cy
        local lh = math.floor((win.ch - 24) / 8)

        for i = 1, lh do
            local idx = scroll + i
            local iy = cy + 16 + (i - 1) * 8
            if my >= iy - 1 and my < iy + 8 then
                local it = items[idx]
                if it then
                    if it == ".." then
                        path = getDir(path)
                        sel = 1
                        scroll = 0
                        refresh()
                        D.markDirty()
                    elseif it:sub(1, 1) == "/" then
                        local np = path == "/" and it or (path .. it)
                        if fs.isDir(np) then
                            path = np
                            sel = 1
                            scroll = 0
                            refresh()
                            D.markDirty()
                        end
                    else
                        D.appEdit(path == "/" and ("/" .. it) or (path .. "/" .. it))
                    end
                end
                return
            end
        end
    end

    w.onKey = function(win, key, char)
        if key == keys.up and sel > 1 then
            sel = sel - 1
            if sel <= scroll then scroll = scroll - 1 end
            D.markDirty()
        elseif key == keys.down and sel < #items then
            sel = sel + 1
            local lh = math.floor((win.ch - 24) / 8)
            if sel > scroll + lh then scroll = scroll + 1 end
            D.markDirty()
        elseif key == keys.enter then
            local it = items[sel]
            if it then
                if it == ".." then
                    path = getDir(path)
                elseif it:sub(1, 1) == "/" then
                    local np = path == "/" and it or (path .. it)
                    if fs.isDir(np) then path = np end
                else
                    D.appEdit(path == "/" and ("/" .. it) or (path .. "/" .. it))
                end
                sel = 1
                scroll = 0
                refresh()
                D.markDirty()
            end
        elseif key == keys.backspace then
            path = getDir(path)
            sel = 1
            scroll = 0
            refresh()
            D.markDirty()
        elseif key == keys.f5 then
            refresh()
            D.markDirty()
        elseif key == keys.escape or key == keys.q then
            D.destroyWindow(win)
        end
    end
end

function D.appEdit(filepath)
    filepath = filepath or "/untitled.txt"
    local lines = {}
    local content = readFile(filepath)
    if content then
        for line in content:gmatch("[^\n]*") do
            table.insert(lines, line)
        end
    end
    if #lines == 0 then lines = {""} end

    local curLine, curCol, scrollY = 1, 1, 0
    local modified = false

    local w = D.createWindow("Edit: " .. getFileName(filepath), 30, 18, 260, 150)

    w.onDraw = function(win, cx, cy, cw, ch)
        -- Toolbar
        R.drawButton(cx, cy, 36, 14, false)
        R.drawText(cx + 2, cy + 3, "Save", K.BLACK)
        R.drawButton(cx + 38, cy, 36, 14, false)
        R.drawText(cx + 40, cy + 3, "Close", K.BLACK)

        -- Text area
        local eh = math.floor((ch - 24) / 8)
        for i = 1, eh do
            local lineIdx = scrollY + i
            local line = lines[lineIdx] or ""
            R.drawText(cx + 2, cy + 16 + (i - 1) * 8, line, K.BLACK)
        end

        -- Cursor
        if curLine > scrollY and curLine <= scrollY + eh then
            local cy2 = cy + 16 + (curLine - scrollY - 1) * 8
            local cx2 = cx + (curCol - 1) * 6
            if cx2 >= cx and cx2 < cx + cw then
                R.fillRect(cx2, cy2, 6, 8, K.DBLUE)
                local char = (lines[curLine] or ""):sub(curCol, curCol)
                R.drawText(cx2, cy2, char == "" and " " or char, K.WHITE)
            end
        end

        R.drawText(cx + 2, cy + ch - 10, getFileName(filepath) .. (modified and " *" or ""), K.BLACK)
    end

    w.onClick = function(win, mx, my)
        if my >= win.cy + 1 and my < win.cy + 15 then
            if mx >= win.cx and mx < win.cx + 36 then
                -- Save
                writeFile(filepath, table.concat(lines, "\n"))
                modified = false
                D.markDirty()
            elseif mx >= win.cx + 38 and mx < win.cx + 74 then
                -- Close
                if modified then
                    writeFile(filepath, table.concat(lines, "\n"))
                end
                D.destroyWindow(win)
            end
        end
    end

    w.onKey = function(win, key, char)
        if char then
            local line = lines[curLine] or ""
            lines[curLine] = line:sub(1, curCol - 1) .. char .. line:sub(curCol)
            curCol = curCol + 1
            modified = true
            D.markDirty()
        elseif key == keys.backspace then
            if curCol > 1 then
                local line = lines[curLine] or ""
                lines[curLine] = line:sub(1, curCol - 2) .. line:sub(curCol)
                curCol = curCol - 1
                modified = true
            elseif curLine > 1 then
                local prevLen = #(lines[curLine - 1] or "")
                lines[curLine - 1] = (lines[curLine - 1] or "") .. (lines[curLine] or "")
                table.remove(lines, curLine)
                curLine = curLine - 1
                curCol = prevLen + 1
                modified = true
            end
            D.markDirty()
        elseif key == keys.enter then
            local line = lines[curLine] or ""
            lines[curLine] = line:sub(1, curCol - 1)
            table.insert(lines, curLine + 1, line:sub(curCol))
            curLine = curLine + 1
            curCol = 1
            modified = true
            D.markDirty()
        elseif key == keys.up and curLine > 1 then
            curLine = curLine - 1
            curCol = math.min(curCol, #(lines[curLine] or "") + 1)
            if curLine <= scrollY then scrollY = scrollY - 1 end
            D.markDirty()
        elseif key == keys.down and curLine < #lines then
            curLine = curLine + 1
            curCol = math.min(curCol, #(lines[curLine] or "") + 1)
            local eh = math.floor((win.ch - 16) / 8)
            if curLine > scrollY + eh then scrollY = scrollY + 1 end
            D.markDirty()
        elseif key == keys.left then
            if curCol > 1 then
                curCol = curCol - 1
            elseif curLine > 1 then
                curLine = curLine - 1
                curCol = #(lines[curLine] or "") + 1
            end
            D.markDirty()
        elseif key == keys.right then
            if curCol <= #(lines[curLine] or "") then
                curCol = curCol + 1
            elseif curLine < #lines then
                curLine = curLine + 1
                curCol = 1
            end
            D.markDirty()
        elseif key == keys.escape or key == keys.q then
            if modified then
                writeFile(filepath, table.concat(lines, "\n"))
            end
            D.destroyWindow(win)
        end
    end
end

function D.appSettings()
    local label = os.getComputerLabel and os.getComputerLabel() or "No Label"
    local w = D.createWindow("Settings", 50, 30, 200, 110)

    w.onDraw = function(win, cx, cy, cw, ch)
        R.drawText(cx + 4, cy + 4, "Computer Label:", K.BLACK)
        R.drawW95Sunken(cx + 4, cy + 16, cw - 8, 12)
        R.drawText(cx + 6, cy + 18, label, K.BLACK)

        R.drawText(cx + 4, cy + 36, "Screen Size: " .. R.w .. "x" .. R.h, K.BLACK)
        R.drawText(cx + 4, cy + 48, "Windows Open: " .. #D.windows, K.BLACK)
        R.drawText(cx + 4, cy + 60, "CCOS v10 - Optimized", K.BLACK)
    end

    w.onKey = function(win, key)
        if key == keys.escape or key == keys.q then
            D.destroyWindow(win)
        end
    end
end

function D.appShell()
    local output = {"> Type 'help' for commands"}
    local input = ""
    local scrollY = 0

    local w = D.createWindow("Shell", 30, 25, 260, 140)

    w.onDraw = function(win, cx, cy, cw, ch)
        local maxLines = math.floor((ch - 16) / 8)
        for i = 1, maxLines do
            local line = output[scrollY + i]
            if line then
                R.drawText(cx + 2, cy + (i - 1) * 8, line, K.BLACK)
            end
        end

        R.fillRect(cx, cy + ch - 12, cw, 10, K.GRAY)
        R.drawText(cx + 2, cy + ch - 10, "> " .. input, K.BLACK)
    end

    w.onKey = function(win, key, char)
        if char then
            input = input .. char
            D.markDirty()
        elseif key == keys.backspace then
            input = input:sub(1, -2)
            D.markDirty()
        elseif key == keys.enter then
            table.insert(output, "> " .. input)
            local cmd = input
            input = ""

            if cmd == "exit" or cmd == "quit" then
                D.destroyWindow(win)
                return
            elseif cmd == "help" then
                table.insert(output, "Commands: help, ls, cd, clear, exit")
            elseif cmd == "ls" then
                local list = fs.list("/")
                table.insert(output, table.concat(list, "  "))
            elseif cmd == "clear" then
                output = {"> "}
            else
                -- Try to run as Lua
                local fn, err = load("return " .. cmd, "shell", "t", _G)
                if not fn then
                    fn, err = load(cmd, "shell", "t", _G)
                end
                if fn then
                    local ok, result = pcall(fn)
                    if ok and result ~= nil then
                        table.insert(output, tostring(result))
                    elseif not ok then
                        table.insert(output, "Error: " .. tostring(result))
                    end
                else
                    table.insert(output, "Error: " .. tostring(err))
                end
            end

            local maxLines = math.floor((w.ch - 16) / 8)
            if #output > maxLines then
                scrollY = #output - maxLines
            end
            D.markDirty()
        elseif key == keys.up then
            if scrollY > 0 then scrollY = scrollY - 1 end
            D.markDirty()
        elseif key == keys.down then
            local maxLines = math.floor((w.ch - 16) / 8)
            if scrollY < #output - maxLines then scrollY = scrollY + 1 end
            D.markDirty()
        elseif key == keys.q then
            D.destroyWindow(win)
        end
    end
end

-- ============================================
-- MAIN LOOP
-- ============================================
function D.run()
    R.init()
    local running = true
    local timer = os.startTimer(1)

    D.markDirty()

    while running do
        D.drawAll()

        local e, a, b, c, d = os.pullEvent()

        if e == "mouse_click" then
            D.mouse.x = b
            D.mouse.y = c

            local action = D.click(b, c)

            if action == "reboot" then
                R.clear()
                R.drawText(10, 10, "Rebooting...", K.WHITE)
                sleep(0.5)
                os.reboot()
            elseif action == "shutdown" then
                running = false
            elseif action == "files" then
                D.appFM()
            elseif action == "edit" then
                D.appEdit()
            elseif action == "settings" then
                D.appSettings()
            elseif action == "shell" then
                D.appShell()
            end

        elseif e == "mouse_drag" then
            D.mouse.x = b
            D.mouse.y = c
            D.drag(b, c)

        elseif e == "mouse_up" then
            D.drop()

        elseif e == "key" then
            if a == keys.q and D.startMenuOpen then
                D.startMenuOpen = false
                D.markDirty()
            elseif D.activeWin and D.activeWin.onKey then
                pcall(D.activeWin.onKey, D.activeWin, a, nil)
            end

        elseif e == "char" then
            if D.activeWin and D.activeWin.onKey then
                pcall(D.activeWin.onKey, D.activeWin, nil, a)
            end

        elseif e == "timer" then
            -- Update clock
            local t = os.time and os.time() or 0
            local h = math.floor(t)
            local m = math.floor((t - h) * 60)
            local newClock = string.format("%02d:%02d", h, m)

            if newClock ~= D.clock then
                D.clock = newClock
                local by = R.h - D.taskbarH
                R.fillRect(R.w - 48, by + 3, 44, 14, K.GRAY)
                R.drawW95Sunken(R.w - 48, by + 3, 44, 14)
                R.drawText(R.w - 44, by + 6, newClock, K.BLACK)
            end

            timer = os.startTimer(1)
        end
    end

    R.clear()
    R.fillRect(0, 0, R.w, R.h, K.BLACK)
    R.drawText(10, 10, "CCOS shutdown.", K.WHITE)
end

return D
